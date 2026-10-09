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

    @Test("A fatal Wine exception is reported even when the Wine process exits zero")
    func fatalExceptionStatus() throws {
        let log = try runLauncher(["NP_TEST_FATAL": "1"], expectedStatus: 70)
        #expect(log.contains("wine: Unhandled illegal instruction"))
        #expect(log.contains("NP_LAUNCH_STATUS 70"))
    }

    @Test("Ordinary Wine diagnostics do not turn a successful launch into a crash")
    func ordinaryDiagnosticStatus() throws {
        let log = try runLauncher(["NP_TEST_NOISE": "1"])
        #expect(log.contains("NP_LAUNCH_STATUS 0"))
    }

    @Test("A nonzero Wine exit is preserved independently of LaunchServices")
    func nonzeroStatus() throws {
        let log = try runLauncher(["NP_TEST_EXIT": "23"], expectedStatus: 23)
        #expect(log.contains("NP_LAUNCH_STATUS 23"))
    }

    @Test("AoE's adapter workaround is scoped to DXMT and preserves launch options")
    func adapterProfile() throws {
        let custom = "d3d11.preferredMaxFrameRate=60"
        let aoe = try runLauncher(["SteamAppId": "1017900", "WINEDLLPATH_DXMT": "/dxmt", "DXMT_CONFIG": custom])
        #expect(aoe.contains(custom))
        #expect(aoe.contains("dxgi.customVendorId=1002"))
        #expect(aoe.contains("dxgi.customDeviceId=7340"))
        let other = try runLauncher(["SteamAppId": "1234", "WINEDLLPATH_DXMT": "/dxmt", "DXMT_CONFIG": custom])
        #expect(other.contains("NP_PROFILE \(custom)\n"))
        let dxvk = try runLauncher(["SteamAppId": "1017900", "WINEDLLPATH_DXMT": "", "DXMT_CONFIG": custom])
        #expect(dxvk.contains("NP_PROFILE \(custom)\n"))
    }

    @Test("AoE's DXVK adapter file is scoped and respects an explicit config file")
    func dxvkAdapterProfile() throws {
        let aoe = try runLauncher(["SteamAppId": "1017900", "WINEDLLPATH_DXVK": "/dxvk"])
        #expect(aoe.contains("dxgi.customVendorId = 1002"))
        #expect(aoe.contains("dxgi.customDeviceId = 7340"))
        let custom = try runLauncher(["SteamAppId": "1017900", "WINEDLLPATH_DXVK": "/dxvk",
            "NP_TEST_USER_CONFIG": "dxgi.customVendorId = 10de\ndxgi.customDeviceId = 1234\nuser.keep = True\n"])
        #expect(custom.contains("dxgi.customVendorId = 10de"))
        #expect(custom.contains("user.keep = True"))
        #expect(!custom.contains("dxgi.customVendorId = 1002"))
        let other = try runLauncher(["SteamAppId": "1234", "WINEDLLPATH_DXVK": "/dxvk"])
        #expect(other.contains("NP_DXVK_FILE \n"))
    }

    @Test("Versioned profiles obey per-key settings, executable scope and disable controls")
    func profileControls() throws {
        let custom = "dxgi.customVendorId=10de;other.option=True"
        let applied = try runLauncher(["SteamAppId": "1017900", "WINEDLLPATH_DXMT": "/dxmt", "DXMT_CONFIG": custom])
        #expect(applied.contains(custom))
        #expect(applied.contains("dxgi.customDeviceId=7340"))
        #expect(!applied.contains("dxgi.customVendorId=1002"))
        #expect(applied.contains("profile=aoe-de-adapter revision=1"))
        for control in [["NOTPROTON_DISABLE_PROFILES": "1"], ["NP_TEST_TARGET": "vcredist.exe"], ["NP_TEST_RUNTIME": "freewine-unknown"], ["NP_TEST_ARCH": "i386"]] {
            let env = ["SteamAppId": "1017900", "WINEDLLPATH_DXMT": "/dxmt", "DXMT_CONFIG": custom].merging(control) { _, new in new }
            let unchanged = try runLauncher(env)
            #expect(unchanged.contains("NP_PROFILE \(custom)\n"))
            #expect(!unchanged.contains("dxgi.customDeviceId=7340"))
        }
    }

    private func runLauncher(_ extraEnvironment: [String: String] = [:], expectedStatus: Int32 = 0) throws -> String {
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
                if (getenv("NP_TEST_FATAL")) puts("wine: Unhandled illegal instruction at address 00000001420B3880 (thread 011c), starting debugger...");
                if (getenv("NP_TEST_NOISE")) puts("002c:err:virtual:try_map_free_area mmap() error Cannot allocate memory");
                printf("NP_PROFILE %s\\n", getenv("DXMT_CONFIG") ? getenv("DXMT_CONFIG") : "");
                const char *config = getenv("DXVK_CONFIG_FILE");
                printf("NP_DXVK_FILE %s\\n", config ? config : "");
                if (config && config[0] == 'Z' && config[1] == ':') {
                    FILE *file = fopen(config + 2, "r");
                    if (file) { int c; while ((c = fgetc(file)) != EOF) putchar(c); fclose(file); }
                }
                return getenv("NP_TEST_EXIT") ? atoi(getenv("NP_TEST_EXIT")) : 0;
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
            .replacingOccurrences(of: "$appinfo_tool", with: repo.appending(path: "out/appinfo").path)
            .replacingOccurrences(of: "$app_id", with: extraEnvironment["SteamAppId"] ?? "0")
            .replacingOccurrences(of: "$np_build", with: extraEnvironment["NP_TEST_RUNTIME"] ?? "sikarugir-11.0_1")
            .replacingOccurrences(of: "$STEAM_COMPAT_DATA_PATH", with: root.path)
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
        environment["NP_EFFECTIVE_BACKEND"] = extraEnvironment["WINEDLLPATH_DXMT"]?.isEmpty == false ? "dxmt" : extraEnvironment["WINEDLLPATH_DXVK"]?.isEmpty == false ? "dxvk" : "wined3d"
        environment.merge(extraEnvironment) { _, new in new }
        let target = root.appending(path: extraEnvironment["NP_TEST_TARGET"] ?? "AoEDE_s.exe")
        var pe = Data(repeating: 0, count: 134)
        pe[0] = 0x4d; pe[1] = 0x5a; pe[60] = 128
        pe[128] = 0x50; pe[129] = 0x45; pe[132] = 0x64; pe[133] = 0x86
        if extraEnvironment["NP_TEST_ARCH"] == "i386" { pe[132] = 0x4c; pe[133] = 0x01 }
        try pe.write(to: target)
        if let text = extraEnvironment["NP_TEST_USER_CONFIG"] {
            let file = root.appending(path: "custom.conf")
            try Data(text.utf8).write(to: file)
            environment["DXVK_CONFIG_FILE"] = "Z:" + file.path
        }
        // /bin/sh is protected by SIP and removes DYLD_* before it executes the script.
        let result = try Shell.run("/bin/sh", [script.path, "C:\\Program Files (x86)\\Steam\\steam.exe", "Z:" + target.path], environment: environment)
        let log = try String(contentsOf: root.appending(path: "notproton-wine.log"), encoding: .utf8)
        #expect(result.status == expectedStatus, Comment(rawValue: log))
        let status = (try? String(contentsOf: root.appending(path: "notproton-launch-status"), encoding: .utf8)) ?? "missing"
        return log + "\nNP_LAUNCH_STATUS \(status.trimmingCharacters(in: .whitespacesAndNewlines))\n"
    }
}
