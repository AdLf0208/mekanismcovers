# Licence notice — mekanismcovers (Mekanism Covers for Horizon)

## The original mod

- **Name:** Mekanism Covers, version `1.3-BETA+1.21` for Minecraft 1.21.1 (NeoForge)
- **Author:** D4rkness_King — <https://github.com/lucaargolo/mekanism-covers>
- **Licence:** Mozilla Public License Version 2.0 (MPL-2.0), as declared in the jar's
  `META-INF/neoforge.mods.toml` (`license="Mozilla Public License 2.0"`). The jar carries no
  `LICENSE` file of its own, so the licence text kept beside this notice is the MPL-2.0 text
  (`LICENSE`), the same licence the mod declares.
- **What was copied:** the mod's two item names, its lang strings, its two 16×16 block textures
  (`assets/mekanismcovers/textures/block/{cover,empty_cover}.png`), its icon, and the *shapes* of its
  two recipes. They are the original mod's assets, carried to 26.3 and kept under the MPL-2.0.
- **What was rewritten:** all behaviour. The Java source was read for behaviour only (which
  statements exist, what the attach/replace/strip/drop rules are); the Rust in `src/` is a
  clean-room rewrite against the pinned Horizon hooks, not a translation of decompiled code.

## This port

- **Licence:** MPL-2.0, the same as the original. Redistribution and modification are permitted
  under its terms, provided the complete corresponding source travels with the binaries and the
  notices are kept.
- **Source:** `horizon-mod.toml`, `Cargo.toml`, `src/lib.rs`, `src/runtime.rs`, `src/support.rs`,
  `assets/`, `data/` — everything needed to rebuild `mekanismcovers.hmod`.
- **Status:** a first publication (0.2.2). The MPL-2.0 permits redistribution with its source; the
  campaign's maintainer signs off the submission (ARCHITECTURE.md §8).

## Provenance of the pack jar

`mekanismcovers-1.3-BETA+1.21.jar` (136,513 B, SHA-1 `1cfb68fcc9b833af7b992024943dc1e8d45799af`,
Modrinth version `89QaQ0n0` of project `E3sGVcD8`) matched the ATM10 pack's record for the mod and
is kept as evidence at `ports/_shared/licence-cache/`. The port pins Horizon
`0a875da91dbb0fdcb7ba8c42c11341aa229af51a` and horizon-mixins
`e59da9094f0c2fdda6c627fe9eff22dec6a906f0` (game 26.3).
