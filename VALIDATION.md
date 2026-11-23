# VALIDATION — mekanismcovers 0.2.0 / 0.2.1

## 0.2.1 — the required parent declaration (2026-11-23)

A manifest-only fix: `horizon-mod.toml` now declares Mekanism as a required parent
(`[dependencies] mekanism = { version = ">=0.2.2", reason = "…", url = "https://github.com/AdLf0208/mekanism" }`).
The floor is the first Mekanism package whose cable this port actually ran against in game
(0.2.2); see `notes.md` §0.2.1 for the reasoning. No behaviour changed.

| # | step | command | evidence | result |
|---|---|---|---|---|
| 1 | tests | `cargo test --offline` | `sdk-test.log` | **14 passed**, 0 failed (regenerated for 0.2.1) |
| 2 | lints | `cargo clippy --all-targets --offline -- -D warnings` | `sdk-clippy.log` | 0 warnings, EXIT 0 |
| 3 | format | `cargo fmt -- --check` | `sdk-fmt.log` | EXIT 0 |
| 4 | build ×2 | `rm -f Cargo.lock && cargo horizon-mod build` twice, then strip the probe's `Cargo.lock` | `sdk-build.log`, `sdk-build-second.log` | **108,910 B**, SHA-256 `e12b57be0a0465ceca3bbc04f6c86ab602c23e3ebf38e5b14e14447d03fd8942`, `CMP-IDENTICAL`, 24 entries, no packed lock |
| 5 | check | `cargo horizon-mod check mekanismcovers.hmod` | `sdk-check.log` | `mekanismcovers 0.2.1 (native-mod, …)`, `108910 bytes, SHA-256 e12b57be…8942`, EXIT 0 |
| 6 | fits, pin | `cargo horizon-mod fits … --build 0a875da` | `sdk-fits-pin.log` | `0a875da  made for`, EXIT 0 |
| 7 | fits, other | `cargo horizon-mod fits … --build 0b14f8a` | `sdk-fits-0b14f8a.log` | `0b14f8a  fits`, EXIT 0 |
| 8 | package gate | `python3 ports/tools/verify-sdk-package.py mekanismcovers` | run output | **1/1** |
| 9 | manifest deps | `python3 ports/tools/check-manifest-deps.py mekanismcovers` | run output | `ok declared=['mekanism']`, exit 0 |
| 10 | absence proof | `horizon-launcher native-build` on a set of **only** `mekanismcovers` | `dep-absent.log` | `error: mekanismcovers requires missing mod mekanism (…)`, EXIT 1 |
| 11 | pair build | `tools/build-game.sh` | `pair-build-0.2.1.log` | `Compiling mekanism (1 of 2)` / `Compiling mekanismcovers (2 of 2)`; built `native-0a875da-b55bc848e005` |
| 12 | main leg | `tools/e2e.sh` (`CONTROL=0`) | `mekanismcovers-e2e/e2e.log` | **PASS**, `EXIT:0` (A–J) |
| 13 | control | `CONTROL=1` | `mekanismcovers-e2e/e2e-control.log` | **PASS**, `EXIT:0` |
| 14 | control counterfactual | `NEGATIVE=1 CONTROL=1` | `mekanismcovers-e2e/e2e-control-negative.log` | **FAIL**, `EXIT:1` (as required) |
| 15 | selftest | `SELFTEST=1 CONTROL=0` | `mekanismcovers-e2e/e2e-selftest.log` | **FAIL**, `EXIT:1` (as required) |
| 16 | e2e log gate | `check-e2e-logs.py mekanismcovers-e2e --strict` | run output | `logs=4 ok=4 missing-exit=0 bad-exit=0` |

The refusal text, verbatim:

```
error: mekanismcovers requires missing mod mekanism (The covers are worn by Mekanism transmitters and the cover state lives in the transmitter's saved data; this package binds to mekanism:basic_universal_cable and its block entity. https://github.com/AdLf0208/mekanism)
```

The pair build ran against the current parent (`mekanism` 0.2.8). The four in-game logs are the
same A–J scenario as 0.2.0; see the coverage table below.

**Packed lock.** A manifest with `[dependencies]` makes `cargo horizon-mod build` probe the crate,
which creates a `Cargo.lock` that the packer includes. The package has no Cargo registry
dependency (the SDK is a path dep; the launcher uses Horizon's own lock), so each build's archive
is delivered with that probe file stripped (`zip -q -d … Cargo.lock`); both stripped builds are
byte-identical. Without the declaration the same build packs none (ad-hoc `/tmp/opencode/mcprobe`).

## 0.2.0 — the first package (2026-11-21)

Every step ran inside a `ports/tools/build-slot.sh` lease (`CARGO_INCREMENTAL=0`, no
`--target-dir`, no private `BUILD_SLOTS_DIR`), from the campaign root, at pin
**`0a875da91dbb0fdcb7ba8c42c11341aa229af51a`** + horizon-mixins
**`e59da9094f0c2fdda6c627fe9eff22dec6a906f0`** (game 26.3, launcher 0.2.92).

Evidence: `ports/_shared/evidence/mekanismcovers/` (ladder) and
`ports/_shared/evidence/mekanismcovers-e2e/` (in-game legs). Iteration logs from the e2e work are
in `ports/_shared/evidence/mekanismcovers/attempts/`.

## Ladder

| # | step | command | evidence | result |
|---|---|---|---|---|
| 1 | red | `cargo test --offline` before the rules existed | `tdd-red.log` | **EXIT 101**, 49 errors: `cannot find function special/attach/is_transmitter/is_identifier/tip/centre`, `cannot find type Cell/Plan/Attach/Tip` |
| 2 | unit tests | `cargo test --offline` | `sdk-test.log` | **14 passed**, 0 failed, EXIT 0 |
| 3 | clippy | `cargo clippy --all-targets -- -D warnings` | `sdk-clippy.log` | 0 warnings, EXIT 0 |
| 4 | fmt | `cargo fmt -- --check` | `sdk-fmt.log` | EXIT 0 |
| 5 | build 1 | `rm -f Cargo.lock && cargo horizon-mod build` | `sdk-build.log` | `Built ./target/horizon-mod/mekanismcovers.hmod`, 105,498 B |
| 6 | build 2 | the same, again | `sdk-build-second.log` | 105,498 B, SHA-256 `2cf0fa6f5b8a2ba48de455bf10c36920276b33a21be68ab4b85e0c89c374eade`, `cmp` **identical** |
| 7 | check | `cargo horizon-mod check mekanismcovers.hmod` | `sdk-check.log` | `mekanismcovers 0.2.0 (native-mod, format native-1/0a875da…/e59da90…, for 26.3)`, `105498 bytes, SHA-256 2cf0fa6f…eade`, **EXIT 0** |
| 8 | fits, pin (tautology) | `cargo horizon-mod fits … --build 0a875da` | `sdk-fits-pin.log` | `0a875da  made for`, EXIT 0 |
| 9 | fits, other build | `cargo horizon-mod fits … --build 0b14f8a` | `sdk-fits-0b14f8a.log` | `0b14f8a  fits`, EXIT 0 |
| 10 | data dialect | `python3 ports/tools/check_261_dialect.py mekanismcovers.hmod` | `sdk-dialect.log` | `2 recipe/loot file(s), every one in the 26.3 dialect` |
| 11 | package gate | `python3 ports/tools/verify-sdk-package.py mekanismcovers` | run output | **7/7** (see the report) |
| 12 | e2e logs | `python3 ports/tools/check-e2e-logs.py mekanismcovers-e2e --strict` | run output | exit 0 |

The red proof, verbatim from `tdd-red.log`:

```
error[E0425]: cannot find function `special` in this scope
error[E0425]: cannot find function `attach` in this scope
error[E0425]: cannot find function `is_transmitter` in this scope
error[E0433]: cannot find type `Cell` in this scope
error[E0433]: cannot find type `Plan` in this scope
error: could not compile `mekanismcovers` (lib test) due to 49 previous errors; 1 warning emitted
```

## In-game legs

The package needs its **parent compiled into the same game**: a cover is worn by
`mekanism:basic_universal_cable`, whose block entity is declared by `ports/mekanism`'s code.
`tools/build-game.sh` stages both packages in one folder and calls the launcher's
`native-build <folder-of-mods>`, which prints `Compiling mekanism (1 of 2)` /
`Compiling mekanismcovers (2 of 2)`; the control game is the same Nightly with neither package.
The parent staged for these legs is `mekanism` 0.2.2 (2026-11-21 12:35); the parent's later 0.2.3
edit is its chemical tank and rustfmt, and leaves the cable and its saved data byte-identical.

```sh
BUILD_LOCAL=1 ports/tools/build-slot.sh run --job W1-mekanismcovers --port ports/mekanismcovers \
    --step build -- bash ports/mekanismcovers/tools/build-game.sh     # 1 s, 2 mods
eval "$(ports/mekanismcovers/tools/build-game.sh --env)"               # GAME/CTL/CONTROL_GAME/RES
BUILD_LOCAL=1 ports/tools/build-slot.sh run --job W1-mekanismcovers --port ports/mekanismcovers \
    --step e2e -- bash ports/mekanismcovers/tools/e2e.sh
```

| leg | command | evidence | result |
|---|---|---|---|
| main | `tools/e2e.sh` (`CONTROL=0`) | `mekanismcovers-e2e/e2e.log` | **PASS**, `EXIT:0` — phases A–J |
| control | `tools/e2e.sh` (`CONTROL=1`, default) | `mekanismcovers-e2e/e2e-control.log` | **PASS**, `EXIT:0` — the same Nightly without either package knows neither id and places no cable |
| control, counterfactual | `NEGATIVE=1 CONTROL=1` | `mekanismcovers-e2e/e2e-control-negative.log` | **FAIL**, `EXIT:1` — the control's "the id is unknown" assertion is proven able to fail |
| selftest | `SELFTEST=1` | `mekanismcovers-e2e/e2e-selftest.log` | **FAIL**, `EXIT:1` — "expected the replace to drop nothing (1 -> 1)" |

### What the main leg proves (phase → assertion)

| phase | assertion | how it could fail |
|---|---|---|
| A | both items are given and read back; an unknown id is refused | a missing registration reads 0; the refusal is the command's own reply |
| B | the shaped recipe makes **4** `empty_cover` and consumes all 9 cells | a wrong pattern or a dead tag leaves the result empty (it did, in attempts/) |
| C | the special recipe fills an empty cover with stone, and the held stack's `components` reads `mekanismcovers:cover_block: "minecraft:stone"` | a wrong component id or a host-free decode failure |
| D | the cable's saved data has **no** `mekanismcovers:cover` before the click and `"minecraft:stone"` after it, still there 40 ticks later; the held cover is consumed | `merge_data` refusal, the parent tick overwriting the key, the item not consumed (survival) |
| E | a second cover (glass) replaces the first: the data reads glass and the replaced cover comes back (total 1 → 1, against D's 1 → 0) | no drop leaves total at 0 — the differential is what makes it fail-capable |
| F | sneak + right-click with an empty cover removes the key and drops the cover; the empty cover is kept | without sneak the strip must not happen (the same click, unsneaked, is phase G's control) |
| G | a click on a stone block changes nothing and consumes nothing | a missing `is_transmitter` guard would attach to a non-transmitter |
| H | a cover filled with a **torch** is refused on the cable: no key, not consumed | the fill-rule half of upstream's rule is enforced at attach |
| I | breaking a covered cable drops the cover **and** the cable | `block_drops` reading the key before the block entity goes |
| J | the special recipe strips a filled cover back to an empty one and returns the block as the recipe's remainder | a missing `remaining_items` loses the block |

## Packaging

```
mekanismcovers.hmod   105,498 bytes
sha256                2cf0fa6f5b8a2ba48de455bf10c36920276b33a21be68ab4b85e0c89c374eade
entries               22 (horizon-mod.toml, Cargo.toml, LICENSE, 3 src/*.rs, 6 assets/*, 7 data/*,
                      icon.png, uses.json)
declared version      0.2.0 (horizon-mod.toml == the registry entry == the release)
Cargo.lock            not packed
```

The delivered `src/*.rs`, `horizon-mod.toml` and `Cargo.toml` are **byte-identical** to the ones
inside the package (checked with `unzip -p … | sha256sum` against the tree).
