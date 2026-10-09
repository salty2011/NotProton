import Testing
@testable import NotProtonApp

@Suite("Reviewed runtime setting policy")
struct RuntimePolicyTests {
    @Test("Automatic resolves the same renderer for every known free revision")
    func automatic() throws {
        let document = try #require(RuntimePolicy.document)
        for (id, runtime) in document.runtimes {
            let result = try RuntimePolicy.resolve(build: id, renderer: "")
            #expect(result.renderer == runtime.automatic)
            #expect(result.state == .supported)
        }
    }
    @Test("Unavailable renderer and feature requests fail rather than changing choice")
    func unavailable() throws {
        #expect(throws: StepFailure.self) { try RuntimePolicy.resolve(build: "freewine-26.3_2", renderer: "d3dmetal") }
        #expect(throws: StepFailure.self) {
            try RuntimePolicy.resolve(build: "freewine-26.3_2", renderer: "dxvk", options: ["DXMT_ENABLE_NVEXT": "1"])
        }
        #expect(throws: StepFailure.self) { try RuntimePolicy.resolve(build: "freewine-unknown", renderer: nil) }
    }
    @Test("Every existing toggle has a classification and renderer scope")
    func options() throws {
        let document = try #require(RuntimePolicy.document)
        #expect(Set(document.options.keys) == ["MTL_HUD_ENABLED", "ROSETTA_ADVERTISE_AVX", "WINEMSYNC",
            "NOTPROTON_RETINA", "NOTPROTON_RAW_CONTROLLERS", "DXMT_ENABLE_NVEXT",
            "DXMT_METALFX_SPATIAL_SWAPCHAIN", "D3DM_ENABLE_METALFX"])
        for (id, runtime) in document.runtimes {
            for (key, option) in document.options {
                let state = try #require(runtime.capabilities[option.feature].flatMap(RuntimePolicy.State.init(rawValue:)))
                if state == .unavailable {
                    #expect(throws: StepFailure.self) { try RuntimePolicy.resolve(build: id, renderer: nil, options: [key: "1"]) }
                } else {
                    let renderer = try #require(option.renderers.first)
                    let result = try RuntimePolicy.resolve(build: id, renderer: renderer, options: [key: "1"])
                    #expect(result.experimentalOptions.contains(option.label) == (state == .experimental))
                }
            }
        }
    }
    @Test("Installed package descriptors agree with reviewed capabilities")
    func catalog() throws {
        let document = try #require(RuntimePolicy.document)
        for package in RuntimeCatalog.packages {
            let policy = try #require(document.runtimes[package.id])
            for (feature, state) in package.descriptor.capabilities {
                #expect(policy.capabilities[feature] == state)
            }
        }
    }
}
