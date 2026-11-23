# Mekanism Covers → Horizon — first port (0.2.0), required parent declared (0.2.1)

Port of **Mekanism Covers 1.3-BETA+1.21** (`dev.lucaargolo.mekanismcovers`, author D4rkness_King,
**MPL-2.0**), the exact ATM10 jar `mekanismcovers-1.3-BETA+1.21.jar` (Modrinth
`E3sGVcD8` / version `89QaQ0n0`, SHA-1 `1cfb68fcc9b833af7b992024943dc1e8d45799af`, 136,513 B; kept
as evidence at `ports/_shared/licence-cache/`). Upstream behaviour was read from
`github.com/lucaargolo/mekanism-covers` at `47a3c49` (`mod_version=1.3-BETA+1.21`) — analysis
only, no Java was translated.

**Class `integration`, tier `machines`** (`ports/ledger.csv`). Licence **MPL-2.0 → rank 0**; the
carried art (two 16×16 block textures and the mod's icon) is the mod's own, redistributed under
the same MPL-2.0 (`LICENSE`, `LICENSE-NOTICE.md`). Not on the upstream registry before this
version: a **first publication** (`dispatch-gate.py` exit 0).

Skills: superpowers/using-superpowers,brainstorming,writing-plans,test-driven-development,systematic-debugging,verification-before-completion; BeautifulRust/rust-best-practices

## 0.2.1 — the required parent, declared (2026-11-23)

**Why this version exists.** Two reviewers refused sibling packages for the same defect
(#1605 `industrialforegoingsouls`, #1663 `industrialization_overdrive`): a package that resolves
another mod's ids declared no `[dependencies]`, and the pinned resolver reads **declared
dependencies**, not block ids or README prose (`horizon/launcher/src/native_mods/dependencies.rs`
at the pin). `ports/tools/check-manifest-deps.py mekanismcovers` found the class here too:

```
mekanismcovers               FAIL declared=-    HARD  uses mekanism in ['code'] with no declaration
```

A cover is worn by `mekanism:basic_universal_cable` and the cover key lives in that transmitter's
own saved data, so Mekanism is a **required** parent, not an optional integration. The declaration
is now in `horizon-mod.toml`:

```toml
[dependencies]
mekanism = { version = ">=0.2.2", reason = "…", url = "https://github.com/AdLf0208/mekanism" }
```

**Why the floor is 0.2.2.** The surface this package calls is the cable's block entity and its
saved data. The first Mekanism package whose cable this port actually ran against in game is
**0.2.2** (`VALIDATION.md`, the 2026-11-21 leg, staged at 12:35); 0.2.0 had no in-game run at all
(its validation gap 1) and 0.2.1 was the review fix. 0.2.3's only change (the chemical tank) leaves
the cable and its saved data byte-identical, and the leg below ran against the current parent,
0.2.8. A lower floor would accept a parent nobody has exercised the cover against.

### Proof (a): with Mekanism absent the loader refuses the package by name

`tools/dep-absent.log`: a native mod set containing only `mekanismcovers` is handed to the
launcher's `native-build` — the pinned resolver, before any mod code is compiled or registered:

```
$ horizon-launcher native-build /tmp/opencode/mekanismcovers-absent-set --instance e2e --trust-native-code --json
error: mekanismcovers requires missing mod mekanism (The covers are worn by Mekanism transmitters and the cover state lives in the transmitter's saved data; this package binds to mekanism:basic_universal_cable and its block entity. https://github.com/AdLf0208/mekanism)
EXIT:1
```

The refusal names both mods, quotes the declaration's own `reason` and `url`, and happens before
compilation, so it is a named refusal, not a registration crash. **Counterfactual:** the same set
with the `[dependencies]` table removed (an ad-hoc copy at `/tmp/opencode/mcprobe`) builds with no
refusal and packs no lock, so the refusal is the declaration's effect.

### Proof (b): with Mekanism present every existing leg still passes

`tools/build-game.sh` stages both source trees and the launcher compiles them together
(`pair-build-0.2.1.log`: `Compiling mekanism (1 of 2)` / `Compiling mekanismcovers (2 of 2)`).
The cover scenario (phases A–J) is unchanged, and the four required runs are green:

| leg | log | result |
|---|---|---|
| main | `mekanismcovers-e2e/e2e.log` | PASS, `EXIT:0` (A–J) |
| control (plain build) | `mekanismcovers-e2e/e2e-control.log` | PASS, `EXIT:0` |
| control counterfactual | `mekanismcovers-e2e/e2e-control-negative.log` | FAIL, `EXIT:1` (as required) |
| selftest | `mekanismcovers-e2e/e2e-selftest.log` | FAIL, `EXIT:1` (as required) |

`check-e2e-logs.py mekanismcovers-e2e --strict` → `logs=4 ok=4 missing-exit=0 bad-exit=0`.

The pair build that ran the legs (`native-0a875da-b55bc848e005`) and the final rebuilt pair
(`native-0a875da-0784a7933142`, after the README edit) produce **byte-identical**
`libmekanismcovers.so` (SHA-256 `d99f825e934237a2ad4ab0b0a5bc0ce555f166516d9a31e06eae65f4a721e9bd`)
and `libmekanism.so` (`676d2f759160abec566b28c7c2f99a53b8128e576ed4d930606af35ad7231bb5`), so the
logs test the delivered source, not an older compile.

### The 0.2.1 ladder

| step | result |
|---|---|
| tests | `cargo test --offline` → **14 passed**, 0 failed (`sdk-test.log`, regenerated for 0.2.1) |
| lints | clippy 0 warnings, `cargo fmt --check` clean (`sdk-clippy.log`, `sdk-fmt.log`) |
| build ×2 | **108,910 B**, SHA-256 `e12b57be0a0465ceca3bbc04f6c86ab602c23e3ebf38e5b14e14447d03fd8942`, `cmp` identical, 24 entries |
| check | `mekanismcovers 0.2.1 (native-mod, format native-1/0a875da…/e59da90…, for 26.3)`, `108910 bytes, SHA-256 e12b57be…8942`, **EXIT 0** (`sdk-check.log`) |
| fits, pin | `0a875da  made for`, EXIT 0 (`sdk-fits-pin.log`) |
| fits, other | `0b14f8a  fits`, EXIT 0 (`sdk-fits-0b14f8a.log`) |
| package gate | `verify-sdk-package.py mekanismcovers` → **1/1** |
| manifest deps | `check-manifest-deps.py mekanismcovers` → `ok declared=['mekanism']`, exit 0 |

**The probe-generated lock.** `cargo horizon-mod build` now runs a probe for a manifest that
declares a dependency, and that probe creates a `Cargo.lock` (8,835 B) which the packer includes.
This package has no *Cargo* registry dependency — the SDK is a path dependency and the launcher
builds against Horizon's own lock — so the delivery strips the probe file with
`zip -q -d … Cargo.lock` after each build. Both stripped builds are byte-identical and the gate's
"no packed Cargo.lock" check is green. Without the declaration the same build packs none.

No behaviour changed: the family table and coverage below are the 0.2.0 ones, and every phase
passed again. Only the manifest, the version strings and two harness fixes changed
(`tools/e2e.sh` now honours `E2E_TMP`; `tools/build-game.sh` falls back to the base Nightly's
prepared 26.3 resources when a prebuilt-base version carries no `.local/`).

## What the mod is

A cover is a cosmetic sleeve for a Mekanism transmitter. Upstream: craft four empty covers
(osmium nuggets + wood dust + glass), use the mod's own `crafting_special_cover` recipe to fill one
with any full block, then right-click a cable, pipe or tube with it — the transmitter wears that
block, a second cover replaces the first and drops it, a wrench strips one, and breaking the
transmitter drops it as a filled cover. The cover is saved on the transmitter (`CoverState`).

## The family table (jar inventory first, then the port)

Every row comes from `unzip -l` of the jar plus its `assets/` and `data/` files, not from the
mod's name. `tested` names the e2e phase in `tools/e2e.sh` that exercises it.

| family (jar) | what the jar has | this port | coverage |
|---|---|---|---|
| item `empty_cover` | `EmptyCoverItem`, tooltip "Empty", shares the cover's name | declared in `data/mekanismcovers/horizon/item/empty_cover.json` (template `paper`), own name `Empty Cover` (deviation 3), tooltip via the item Part | **tested** — e2e A (give/read back), B (crafted 4×), F (strip click) |
| item `cover` | `CoverItem`, `mekanismcovers:cover_block` component, block-name tooltip | same item + a string component `mekanismcovers:cover_block` (id registered in `component_types`) | **tested** — e2e A, C (`held.components` read back = `minecraft:stone`), D/E/F/I/J |
| recipe `mekanismcovers:cover` (shaped → 4 empty covers) | `crafting_shaped`, `c:nuggets/osmium` + `c:dusts/wood` + `c:glass_blocks` | carried shape `#R#/RGR/#R#`; ingredients adapted (deviation 1): `#c:nuggets/iron`, `minecraft:oak_planks`, `#c:glass_blocks` (both `c:` tags declared by this package) | **tested** — e2e B: result 4 × `empty_cover`, all nine cells consumed |
| recipe `mekanismcovers:crafting_special_cover` | `CustomRecipe`: fill / strip with the block returned | registered as a `CraftingRecipeKind` (`crafting_special_cover`) with the same rule in `runtime::special` | **tested** — e2e C (fill), H (fill with a non-cube), J (strip + the block returned as the remainder) |
| attach to a transmitter | `CoverItem.useOn` + `TileEntityTransmitterMixin` field | the cover rides the **transmitter's own saved data** under `mekanismcovers:cover` (`/data merge block` path); click through the item Part's `use_on` | **tested** — e2e D (key absent → `minecraft:stone` after the click, still there 40 ticks later), E, F, I |
| replace (old cover drops) | `removeCover(..., true)` before the new state | `runtime::attach` + `level.spawn_item` of a filled cover | **tested** — e2e E, differentially against D (1 → 0 vs 1 → 1) |
| strip with a wrench + sneak | `BlockBaseMixin.useItemOn`, `MekanismUtils.canUseAsWrench` | sneak + right-click with an **empty cover** (deviation 2: the parent port ships no Configurator) | **tested** — e2e F (key gone, the cover dropped, the empty cover kept) |
| drop on removal | `BlockMekanismMixin.onRemove` | `Hooks::block_drops` pushes a filled cover beside the block's own loot | **tested** — e2e I (cover + cable both drop) |
| creative tab entry | `BuildCreativeModeTabContentsEvent` → Building Blocks | own creative tab `mekanismcovers:covers` | registered (a tab is not a behaviour; the items are given directly in e2e A) |
| Jade plugin (`CoverComponentProvider`) | client info panel | **not ported** — Jade is a client-info mod the campaign has not ported; nothing to attach to |
| config (`disableAdvancedCoverRendering`, `enableShaderCompatibleRendering`) | renderer switches | **not ported** — both switch a renderer this pin cannot draw (see the gap below) |
| **cover rendering** (block model over the transmitter, translucency, CTM, Sodium/Embeddium, shader path) | 8 client mixins + `ShaderCoverRendering` | **blocked(no-foreign-block-appearance)** — see the parent-surface table |
| **full-block collision shape** while covered | `BlockTransmitterMixin.getRealShape` → `Shapes.block()` | **blocked(no-foreign-block-shape)** — `update_shape` is a *replace* hook that answers only for the mod's own blocks; a Part cannot be attached to another package's block |
| **the cover's light** (`dynamic_light`, `AuxiliaryLightManager`) | `BlockTransmitterMixin.getLightEmission` | **blocked(no-foreign-dynamic-light)** — `light_emission` is asked only for a block the package declares with `dynamic_light: true` |
| **appearance for other mods** (`getAppearance` → the cover state) | `BlockTransmitterMixin.getAppearance` | **blocked(no-get-appearance-hook)** — the pin has no `getAppearance` counterpart |
| clearing fluid logging on attach | `BlockStateHelper.FLUID_LOGGED` | **not ported** — the parent port's cable declares no fluid-logged state to clear |

## Parent surface (ruling 2026-11-21: an add-on needs the parent's *surface*, not its status)

`mekanismcovers` binds to `mekanism`, whose ledger status is `ported` — which is **not** evidence
that the surface this add-on needs exists. Each parent symbol was grepped before the code was
written:

| parent symbol / behaviour the jar needs | present here? | evidence |
|---|---|---|
| a Mekanism **transmitter** block with a block entity | **yes, one**: `mekanism:basic_universal_cable` | `ports/mekanism/src/support.rs:25` (`CABLE`), `:34` (`CABLE_TYPE`), `:118-126` (`block_entity_type(CABLE_TYPE).blocks(&[CABLE_TYPE])` + `block_entity_part`) |
| the transmitter's **saved data**, readable and writable from another package | **yes**: `BlockEntityRef::data` + `merge_data`/`replace_data` (the `/data merge block` path) | SDK `horizon-mod-vocab/src/host/block_entities.rs`; proven in e2e D (`/data get block` reads the key the click wrote) |
| the transmitter's tick **keeps** a foreign key in its compound | **yes**: the cable's Part reads the whole compound and writes it back | `ports/mekanism/src/support.rs:368` (`Tag::Compound(event.entity.nbt.clone())`), `write_state`, e2e D's 40-tick re-read |
| `MekanismItems.CONFIGURATOR` (the wrench) + `MekanismUtils.canUseAsWrench` | **no** — the parent port does not ship the Configurator (its manifest says so) | `ports/mekanism/horizon-mod.toml` description ("Not ported: … the Configurator"); `grep -rn configurator ports/mekanism/src` → nothing |
| `IStateFluidLoggable` / `BlockStateHelper.FLUID_LOGGED` | **no** — the cable declares no fluid-logged property | `ports/mekanism/data/mekanism/horizon/block/basic_universal_cable.json` (template + hardness + shapes only) |
| `TileEntityTransmitter.getModelData`, `COVER_STATE` model property | **no** — no model-data hook, no per-position model override for a foreign block | `surface.json` has no `getAppearance`/model-data hook; `bake_model_loader`/`block_render_visibility` are state-global |
| **all other transmitter families** (pipes, tubes, thermodynamic conductors, 21 tiers) | **no** — the parent port ships one cable | `ports/mekanism` registers one transmitter block |

The **core mechanic binds to a surface that exists** (the cable's block entity and its saved
data), so this is not a `mifa`-style stop: the items are not inert — they craft, fill, strip,
attach, replace, drop and refuse, all proven in game. The two halves that need a symbol the pin
does not have (appearance, shape/light) are recorded as `blocked(<symbol>)` rows above, not faked.

## Deviations (each one is a decision, not an omission)

1. **The shaped recipe's ingredients.** Upstream wants `c:nuggets/osmium` and `c:dusts/wood`. This
   pack has **no osmium at all** (the parent port's item set is five blocks and three dusts), and
   no wood dust; a recipe naming an empty tag can never craft. Following the parent port's own
   precedent ("vanilla stand-ins … recorded in the description as a deviation"), the port keeps the
   shape and the 4:1 yield and uses `#c:nuggets/iron` (declared here with `minecraft:iron_nugget`),
   `minecraft:oak_planks` and `#c:glass_blocks` (declared here with glass and tinted glass). A user
   notices cheaper ingredients, not a different recipe.
2. **The strip gesture.** Upstream needs a Mekanism Configurator in wrench mode + sneak. The parent
   port has no Configurator, so the strip is **sneak + right-click with an empty cover** — the
   mod's own item, discoverable, and it consumes nothing (a strip should not cost a cover). The
   wrench path is `blocked(no-parent-wrench)`.
3. **`empty_cover`'s name.** Upstream makes both items share the cover's description id ("Cover",
   distinguished by the "Empty" tooltip). This port names the empty one "Empty Cover" and keeps
   the tooltip line; a shared id is not expressible for two separate item declarations.
4. **The fill rule's two extra conditions** (`isCollisionShapeFullBlock`, not an `EntityBlock`) are
   checked **when the cover is put on**, not when it is crafted: `CraftingRecipeKind` has no host,
   so a block cannot be resolved at craft time. A cover filled with a torch (e2e H) is refused on
   the transmitter and stays in hand — nothing is lost, and the rule is still enforced where it
   matters.
5. **The block id, not a serialised block state.** Upstream saves
   `BlockStateParser.serialize(stateForPlacement(...))`; the pin has no `state_for_placement` for a
   block another package declares, so a cover names its **block** and the transmitter's saved data
   holds that id. A directional cover (a log, a stair) therefore wears the block's default state
   rather than the clicked one — invisible today (nothing draws it) and recorded for the appearance
   slice.

## Where the cover lives (the integration contract)

The cover is stored in the **transmitter's own saved data**, key `mekanismcovers:cover`, value a
block id string:

* `use_on` reads it with `BlockEntityRef::data`, writes it with `merge_data` (attach) or
  `replace_data` (strip) — the transactional `/data merge block` path, which marks the chunk and
  sends clients the update.
* The parent cable's tick reads the whole compound and writes it back (`support.rs:368`), so the
  key survives every tick; the e2e re-reads it 40 ticks after the click.
* `block_drops` reads the same key through `LevelHost::block_entity_data` (that hook gets a
  `LevelHost`, not a `Host`, and the two do not upcast).

This is a **world-state interop contract** on a key name, exactly as `ARCHITECTURE.md` §3 allows
for add-ons ("re-implemented in the child crate using the parent port as the pattern"); no Rust
symbol of the parent is referenced.

The 0.2.0 leg ran against the parent port as staged at 12:35 on 2026-11-21 (`mekanism` 0.2.2
sources). The parent moved to 0.2.3 while this port was being verified (another agent's
chemical-tank slice); `diff` of the two trees shows the change touches
`is_chemical_tank`/`chemical_readout`/`chemical_insert` and rustfmt only — `CABLE`, `CABLE_TYPE`,
the cable's Part and its `write_state` are byte-identical, so the contract is unaffected. The
0.2.1 leg (`tools/build-game.sh`, 2026-11-23) ran against the current parent, **0.2.8**, and every
phase passed. Re-run `tools/build-game.sh` before the next slice and the leg picks the current
parent up.

## What a user can do today

Craft covers, fill one with stone/glass/any full block, right-click a Mekanism cable and the cable
*carries* that cover (visible in `/data get block`), replace it, strip it with sneak + empty cover,
and break the cable to get the cover back. **Nothing draws the cover yet** — that is the one
blocked family, and the report says so rather than pretending.

## Verification (evidence in `ports/_shared/evidence/mekanismcovers/`)

| step | command | result |
|---|---|---|
| red | `cargo test` before the rules existed | **EXIT 101**, 49 errors naming `special`, `attach`, `is_transmitter`, `Cell`, `Plan`, `Tip` (`tdd-red.log`) |
| unit | `cargo test --offline` | **14 passed**, 0 failed (`sdk-test.log`) |
| clippy | `cargo clippy --all-targets -- -D warnings` | **0 warnings**, exit 0 (`sdk-clippy.log`) |
| fmt | `cargo fmt -- --check` | exit 0 (`sdk-fmt.log`) |
| build ×2 | `rm -f Cargo.lock && cargo horizon-mod build` twice | 105,498 B, SHA-256 `2cf0fa6f…eade`, `cmp` identical (`sdk-build.log`, `sdk-build-second.log`) |
| check | `cargo horizon-mod check mekanismcovers.hmod` | `0.2.0 (native-mod, format native-1/0a875da…/e59da90…, for 26.3)`, **EXIT 0** (`sdk-check.log`) |
| fits, pin | `cargo horizon-mod fits … --build 0a875da` | `0a875da  made for`, EXIT 0 (`sdk-fits-pin.log`) |
| fits, other | `cargo horizon-mod fits … --build 0b14f8a` | `0b14f8a  fits`, EXIT 0 (`sdk-fits-0b14f8a.log`) |
| data dialect | `python3 ports/tools/check_261_dialect.py mekanismcovers.hmod` | 2 recipe files, every one in the 26.3 dialect |
| e2e | `tools/e2e.sh` on the paired build | **PASS**, `EXIT:0` (`-e2e/e2e.log`) |
| e2e control | the same Nightly without either package | **PASS** with "the item is unknown", `EXIT:0` (`-e2e/e2e-control.log`) |
| e2e control, counterfactual | `NEGATIVE=1 CONTROL=1` | **FAIL**, `EXIT:1` (`-e2e/e2e-control-negative.log`) |
| e2e selftest | `SELFTEST=1` | **FAIL**, `EXIT:1` (`-e2e/e2e-selftest.log`) |

## Traps this port hit (worth knowing before the next add-on)

* `Cell::Block(..)` in the pure module made `fits --build 0b14f8a` **false-fail** ("the type `Block`
  can no longer be built with a literal"). The analyzer reads the variant as a `mod_api::Block`
  construction; renaming it `Cell::Places(..)` fixed it. Same family as the brief's trap 4, and it
  fires on an *enum variant*, not only on a local type.
* A recipe in the 1.21.1 ingredient dialect (`{"item": …}` / `{"tag": …}`) **loads as invalid** and
  the crafting table silently has no result: `recipes: invalid ingredient (unresolved tag or
  malformed input)` in the game log. `check_261_dialect.py` catches it before the run.
* A **creative** hand consumes nothing (`ItemPlace::extract` on a creative player's hand gives
  without losing any, vanilla's rule), so "the cover is consumed" can only be asserted in survival;
  the world phases switch with `gamemode survival @s` and give a pickaxe for the break.
* A drop lands **inside pickup range** of the player who made it, so a bare `ground` count proves
  nothing: the assertions use inventory + floor (`total`), and the two attach phases are compared
  differentially (first attach 1 → 0, replace 1 → 1).
* `--headless` hangs `ctl screen`/`menu`; the recipe phases need `--offscreen`.
* The parent's cable needs a **pickaxe** to drop (`requires_tool: true` in its content), so the
  break phase selects a diamond pickaxe — and `open_table` clears the inventory, so the pickaxe is
  given after the last table phase.

## Next slice

The appearance half, as soon as the pin (or the parent port) offers one hook:

1. **`block_appearance`/`get_appearance` (or a per-position model override) for a block another
   package declares** — then `mekanismcovers` can return the worn block's state for the cable at
   `pos` and the client meshes it (upstream's `getAppearance` + the 8 client mixins). Assertion:
   `ctl screenshot` at the covered cable shows the cover's texture, and the same cable stripped
   shows the cable again.
2. **`shape`/`dynamic_light` for a foreign block** — the full-block collision and the cover's light;
   assertion: a player cannot walk through a covered cable and `ctl light` at the cable reads the
   cover's emission.
3. Parent-side: the **Configurator** lands in `ports/mekanism`, which restores upstream's
   wrench+sneak strip (keep the empty-cover route as a second spelling).
4. Parent-side: the other transmitter families (pipes, tubes), which this port already accepts by
   id (`is_transmitter` matches `mekanism:*_cable|_pipe|_tube`) with no code change.
