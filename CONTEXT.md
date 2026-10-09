# NotProton Runtime Context

NotProton makes Windows Steam compatibility tools available in macOS Steam. These terms distinguish a runtime release from a game's persistent state and its compatibility evidence.

## Language

**Runner Build**: An exact version and architecture of a Wine engine paired with its matching Steam bridge. A different compiled or patched engine is a different build.
_Avoid_: interchangeable Wine binary

**Runtime Package**: A versioned, verified distribution of a runner build with its required free libraries, graphics layers and provenance.
_Avoid_: installation prefix, game bottle

**Compatibility Tool**: A Steam-selectable entry that identifies the runner build used to launch a game.
_Avoid_: game prefix

**Prefix**: A game's persistent Windows filesystem and registry state, associated with the runner build that last prepared it.
_Avoid_: runtime installation

**Capability**: A setting or behavior an exact runtime and host combination implements, distinguished from whether that behavior has been qualified.
_Avoid_: universal game compatibility

**Qualification**: Recorded evidence for a particular behavior, host, runtime and game or probe; launch, gameplay, media and session stability are separate results.
_Avoid_: launched means fully supported

**Game Profile**: Verified defaults scoped to a game and compatible runtime/renderer combinations, subordinate to explicit player choices.
_Avoid_: proprietary compatibility database

**Dependency Recipe**: A scoped, versioned preparation procedure with presence detection and a checked postcondition for a game's missing prerequisite.
_Avoid_: install every dependency
