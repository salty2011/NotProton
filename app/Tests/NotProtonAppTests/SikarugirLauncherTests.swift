import Foundation
import Testing

@testable import NotProtonApp

@Suite("Sikarugir game launcher")
struct SikarugirLauncherTests {
    @Test("A generated launcher restores library lookup after the macOS system shell")
    func librariesSurviveSystemShell() throws {
        let log = try runLauncher()
        #expect(log.contains("DYLD_DEPENDENCY_OK"))
    }

    @Test("AoE's adapter workaround is scoped to DXMT and preserves launch options")
    func adapterProfile() throws {
        let custom = "d3d11.preferredMaxFrameRate=60"
        let aoe = try runLauncher(["SteamAppId": "1017900", "WINEDLLPATH_DXMT": "/dxmt", "DXMT_CONFIG": custom])
        #expect(aoe.contains("[AoEDE_s.exe];dxgi.customVendorId=1002;dxgi.customDeviceId=7340;\(custom)"))
        let other = try runLauncher(["SteamAppId": "1234", "WINEDLLPATH_DXMT": "/dxmt", "DXMT_CONFIG": custom])
        #expect(other.contains("NP_PROFILE \(custom)\n"))
        let dxvk = try runLauncher(["SteamAppId": "1017900", "WINEDLLPATH_DXMT": "", "DXMT_CONFIG": custom])
        #expect(dxvk.contains("NP_PROFILE \(custom)\n"))
    }

    @Test("AoE's DXVK adapter file is scoped and respects an explicit config file")
    func dxvkAdapterProfile() throws {
        let aoe = try runLauncher(["SteamAppId": "1017900", "WINEDLLPATH_DXVK": "/dxvk"])
        #expect(aoe.contains("dxgi.customVendorId = 1002\ndxgi.customDeviceId = 7340\n"))
        let custom = try runLauncher(["SteamAppId": "1017900", "WINEDLLPATH_DXVK": "/dxvk",
            "DXVK_CONFIG_FILE": "Z:/custom.conf"])
        #expect(custom.contains("NP_DXVK_FILE Z:/custom.conf\n"))
        #expect(!custom.contains("dxgi.customVendorId = 1002"))
        let other = try runLauncher(["SteamAppId": "1234", "WINEDLLPATH_DXVK": "/dxvk"])
        #expect(other.contains("NP_DXVK_FILE \n"))
    }

    private func runLauncher(_ extraEnvironment: [String: String] = [:]) throws -> String {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: "np-launcher-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let libraries = root.appending(path: "Libraries")
        try fm.createDirectory(at: libraries, withIntermediateDirectories: true)
        try Data("sikarugir\n".utf8).write(to: root.appending(path: "notproton-provider"))
        let librarySource = root.appending(path: "library.c")
        try Data("int launcher_test(void) { return 1; }".utf8).write(to: librarySource)
        try Shell.check("/usr/bin/clang", ["-dynamiclib", librarySource.path,
            "-o", libraries.appending(path: "libnotproton-launcher-test.dylib").path])
        let mediaLibraries = libraries.appending(path: "GStreamer.framework/Libraries")
        try fm.createDirectory(at: mediaLibraries, withIntermediateDirectories: true)
        try Shell.check("/usr/bin/clang", ["-dynamiclib", librarySource.path,
            "-o", mediaLibraries.appending(path: "libnotproton-media-test.dylib").path])
        let probeSource = root.appending(path: "probe.c")
        try Data("""
            #include <dlfcn.h>
            #include <stdio.h>
            #include <stdlib.h>
            int main(void) {
                if (!dlopen("libnotproton-launcher-test.dylib", RTLD_NOW)
                    || !dlopen("libnotproton-media-test.dylib", RTLD_NOW)) {
                    puts("DYLD_DEPENDENCY_MISSING"); return 41;
                }
                puts("DYLD_DEPENDENCY_OK");
                printf("NP_PROFILE %s\\n", getenv("DXMT_CONFIG") ? getenv("DXMT_CONFIG") : "");
                const char *config = getenv("DXVK_CONFIG_FILE");
                printf("NP_DXVK_FILE %s\\n", config ? config : "");
                if (config && config[0] == 'Z' && config[1] == ':') {
                    FILE *file = fopen(config + 2, "r");
                    if (file) { int c; while ((c = fgetc(file)) != EOF) putchar(c); fclose(file); }
                }
                return 0;
            }
            """.utf8).write(to: probeSource)
        let probe = root.appending(path: "wine-probe")
        try Shell.check("/usr/bin/clang", [probeSource.path, "-o", probe.path])

        let repo = URL(filePath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repo.appending(path: "dylib/feats/compat_run.sh"), encoding: .utf8)
        let start = try #require(source.range(of: "cat > \"$loader_macos/launcher\" <<LAUNCHER\n"))
        let end = try #require(source.range(of: "\nLAUNCHER\n", range: start.upperBound..<source.endIndex))
        // Render the real here-document, substituting only its outer shell variables.
        let launcher = String(source[start.upperBound..<end.lowerBound])
            .replacingOccurrences(of: "$WINELOADER", with: probe.path)
            .replacingOccurrences(of: "$loader_root", with: root.path)
            .replacingOccurrences(of: "\\$", with: "$")
        let script = root.appending(path: "launcher")
        try Data(launcher.utf8).write(to: script)
        var environment = ProcessInfo.processInfo.environment
        environment["CX_ROOT"] = root.path
        environment["DYLD_FALLBACK_LIBRARY_PATH"] = libraries.path
        environment["STEAM_DYLD_INSERT_LIBRARIES"] = ""
        environment["NOTPROTON_GAME_CWD"] = ""
        environment["DXMT_CONFIG"] = ""
        environment["DXVK_CONFIG_FILE"] = ""
        environment["WINEDLLPATH_DXMT"] = ""
        environment["WINEDLLPATH_DXVK"] = ""
        environment.merge(extraEnvironment) { _, new in new }
        // /bin/sh is protected by SIP and removes DYLD_* before it executes the script.
        let result = try Shell.run("/bin/sh", [script.path], environment: environment)
        let log = try String(contentsOf: root.appending(path: "notproton-wine.log"), encoding: .utf8)
        #expect(result.status == 0, Comment(rawValue: log))
        return log
    }
}
