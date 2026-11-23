# Mekanism Covers for Horizon

A port of **Mekanism Covers** 1.3-BETA+1.21 (MPL-2.0) to Horizon 26.3, as one flat SDK package
(`api = "0.2"`, `mekanismcovers.hmod`, version **0.2.1**): content and code in the same file. It
**requires Mekanism** (`[dependencies] mekanism = ">=0.2.2"` in `horizon-mod.toml`), because the
cover is worn by a Mekanism transmitter and its state lives in that transmitter's own saved data.

Craft four empty covers from an iron nugget frame, oak planks and glass; fill one with any full
block through the mod's own `crafting_special_cover` recipe; right-click a Mekanism transmitter
(cable, pipe or tube) with it and the transmitter carries that block. A second cover replaces the
first and drops it, sneak + right-click with an empty cover strips one, and breaking the
transmitter drops the cover beside its own loot.

## Shape

```text
horizon-mod.toml   the only manifest: id, version 0.2.1, api 0.2, [dependencies] mekanism, [native] pins
Cargo.toml         the crate, depending on the pinned SDK (fetched into .horizon/sdk)
src/lib.rs         the one impl mod_api::Hooks + the two item Parts
src/runtime.rs     the rules (which blocks a cover may sit on, attach/replace, the special recipe)
src/support.rs     glue: registry cache for the host-free recipe, the component, block entity I/O
data/              two item declarations, the two recipes, the c tags they name, a creative tab
assets/            item models, two textures (the mod's own), lang
tools/e2e.sh       the in-game leg (phases A–J, control and selftest legs)
tools/build-game.sh  builds mekanism + mekanismcovers into one game for the leg
LICENSE, LICENSE-NOTICE.md   MPL-2.0 and the notice
notes.md, FINDINGS.md, VALIDATION.md
```

## What is not here (and why)

The **appearance** half — the cover drawn over the transmitter, the full-block collision shape, the
cover's light and `getAppearance` for other mods — is `blocked(<symbol>)`: the pinned API has no
per-position appearance, shape or light override for a block another package declares.
`notes.md` lists each missing symbol and the parent-surface check that found it.

## Commands

Everything runs through the campaign's slot registry, from the campaign root:

```sh
# unit tests, lints
ports/tools/build-slot.sh run --job W1-mekanismcovers --port ports/mekanismcovers --step test -- \
    env CARGO_INCREMENTAL=0 cargo test --offline
ports/tools/build-slot.sh run --job W1-mekanismcovers --port ports/mekanismcovers --step lint -- \
    env CARGO_INCREMENTAL=0 cargo clippy --offline --all-targets -- -D warnings

# the package
BUILD_LOCAL=1 ports/tools/build-slot.sh run --job W1-mekanismcovers --port ports/mekanismcovers \
    --step build -- bash -c 'cd ports/mekanismcovers && rm -f Cargo.lock && CARGO_INCREMENTAL=0 cargo horizon-mod build'
cargo horizon-mod check mekanismcovers.hmod        # from the port
cargo horizon-mod fits mekanismcovers.hmod --build 0b14f8a

# the in-game leg: one game carrying this package AND its parent (the cable's block entity is the
# parent's code, and --dev-mod loads content only)
BUILD_LOCAL=1 ports/tools/build-slot.sh run --job W1-mekanismcovers --port ports/mekanismcovers \
    --step build -- bash ports/mekanismcovers/tools/build-game.sh
eval "$(ports/mekanismcovers/tools/build-game.sh --env)"
BUILD_LOCAL=1 ports/tools/build-slot.sh run --job W1-mekanismcovers --port ports/mekanismcovers \
    --step e2e -- bash ports/mekanismcovers/tools/e2e.sh        # SELFTEST=1 / NEGATIVE=1 flip it
```

## Licence

MPL-2.0, the same as the original mod. The carried textures and the icon are the author's, under
that licence; all behaviour is a clean-room Rust rewrite. See `LICENSE-NOTICE.md`.
