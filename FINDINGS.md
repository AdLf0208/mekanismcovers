# FINDINGS — Mekanism Covers 1.3-BETA+1.21

Upstream: `github.com/lucaargolo/mekanism-covers`, read at commit `47a3c49`
(`mod_version=1.3-BETA+1.21`, `minecraft_version=1.21.1`, `neo_version=21.1.82`). The ATM10 jar
`mekanismcovers-1.3-BETA+1.21.jar` (Modrinth `E3sGVcD8` / `89QaQ0n0`, SHA-1
`1cfb68fcc9b833af7b992024943dc1e8d45799af`, 136,513 B, kept at `ports/_shared/licence-cache/`)
is the artefact of record. Analysis only: the port is a clean-room Rust rewrite, no Java was
translated.

## Jar inventory (59 entries)

| area | contents |
|---|---|
| code | `CoverItem`, `EmptyCoverItem`, `CoverRecipe`, `ModConfig`, `MekanismCovers`, `MekanismCoversClient`, `ShaderCoverRendering`, `CompatMixinPlugin`, `mixed/TileEntityTransmitterMixed`, `jade/JadePlugin`, 11 mixins (6 common, 5 client, 2 of them Sodium/Embeddium) |
| assets | `lang/en_us.json`, `models/block/cover.json` (cube_all), `models/item/cover.json` (`builtin/entity`), `models/item/empty_cover.json` (cube_all), `textures/block/{cover,empty_cover}.png` (16×16), `icon.png` (512×512) |
| data | `recipe/cover.json` (shaped → 4 empty covers), `recipe/cover_special.json` (`mekanismcovers:crafting_special_cover`) |
| meta | `META-INF/neoforge.mods.toml` (`license="Mozilla Public License 2.0"`, `modId="mekanismcovers"`), `mekanismcovers.mixins.json` |

No blocks, no block entities, no loot tables, no worldgen, no commands. The one registry surface is
two items, one data-component type (`mekanismcovers:cover_block`) and one recipe serializer
(`crafting_special_cover`).

## Behaviours extracted (file → rule)

* **`MekanismCovers.java`** — registers `empty_cover`, `cover`, the `cover_block`
  (`ResourceLocation`) component and the `crafting_special_cover` serializer; `removeCover` builds a
  filled `cover` stack and `Containers.dropItemStack(x+.5, y+.5, z+.5)`; a cover id resolves through
  `BuiltInRegistries.BLOCK` and a missing one is `null`.
* **`CoverItem.useOn`** — needs a `TileEntityTransmitter`; takes the held cover's block, asks it for
  its placement state, **drops any existing cover first** (`removeCover(..., true)`), writes the new
  state, `setChanged`, shrinks the stack by one, clears fluid-logging and updates the light engine.
  Returns SUCCESS; FAIL for anything else.
* **`EmptyCoverItem`** — no use behaviour at all; its description id is the cover's, and its
  tooltip is the "Empty" line.
* **`CoverRecipe`** — `matches`: exactly one cover-family item, and (empty cover + exactly one
  full-cube, non-`EntityBlock` block) or (filled cover + nothing). `assemble`: fill or empty cover.
  `getRemainingItems`: for a filled cover, the block's **item** comes back. `canCraftInDimensions`:
  `width*height >= 2`.
* **`TileEntityTransmitterMixin`** — keeps a `BlockState coverState` field, saves it under
  `CoverState` (`BlockStateParser.serialize`), syncs it in `getReducedUpdateTag`, reads it in
  `handleUpdateTag`, feeds it to `getModelData`, and drives the auxiliary light.
* **`BlockTransmitterMixin`** — `getRealShape` → `Shapes.block()` when covered (the wrench-held
  context gets the real cable shape); `getLightEmission` from the auxiliary light manager;
  `hasDynamicLightEmission`/`hasDynamicShape` true; `getAppearance` → the cover state.
* **`BlockMekanismMixin.onRemove`** — drops the cover when a transmitter is removed or replaced.
* **`BlockBaseMixin.useItemOn`** — sneak + a wrench (`MekanismUtils.canUseAsWrench`) strips a cover.
* **`BlockStateBaseMixin`** — adds a client ticker for transmitters (the light update).
* **Client mixins** (`ClientBlockTransmitterMixin`, `TransmitterBakedModelMixin`,
  `ModelBlockRendererMixin`, `MinecraftMixin`, Sodium/Embeddium, `ShaderCoverRendering`) — draw the
  cover's quads in place of the cable, with a translucent variant and a shader-compatible path.
* **`ModConfig`** — `disableAdvancedCoverRendering` (default false) and
  `enableShaderCompatibleRendering` (default true); both switch renderers only.
* **`JadePlugin`** — a Jade component provider naming the cover.

## The two recipe files, verbatim

```json
{"type":"minecraft:crafting_shaped","pattern":["#R#","RGR","#R#"],
 "key":{"#":{"tag":"c:nuggets/osmium"},"R":{"tag":"c:dusts/wood"},"G":{"tag":"c:glass_blocks"}},
 "result":{"id":"mekanismcovers:empty_cover","count":4}}
{"type":"mekanismcovers:crafting_special_cover","category":"misc"}
```

## Where the rewrite differs (see notes.md for the reasoning)

* the cover rides the transmitter's own saved data (`mekanismcovers:cover`, a block id) instead of a
  mixin field, because a separate package cannot add a field to another package's block entity;
* the shaped recipe's osmium nugget and wood dust become an iron nugget and oak planks (this pack
  has neither material);
* the wrench strip becomes sneak + empty cover (the parent port ships no Configurator);
* the fill rule's "full cube, no block entity" half is checked at attach instead of at craft time
  (the recipe hook has no host);
* rendering, the full-block shape, the cover's light and `getAppearance` are `blocked(<symbol>)`:
  the pin has no per-position appearance, shape or light for a block another package declares.
