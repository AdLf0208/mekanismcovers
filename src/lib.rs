//! Mekanism Covers for Horizon — one flat SDK package (mod API 0.2).
//!
//! Port of **Mekanism Covers** (`D4rkness_King`, MPL-2.0). Upstream adds a cosmetic cover to
//! Mekanism's transmitters: craft four empty covers, fill one with a full block, then right-click
//! a cable, pipe or tube with it and the transmitter wears that block; a second cover replaces the
//! first and drops it, a wrench strips one, and breaking the transmitter drops it.
//!
//! This first port carries the **mechanical half** in full — both items, the `cover_block`
//! component, the shaped empty-cover recipe, the special fill/strip recipe as a crafting kind, and
//! the per-transmitter cover state with its replace/strip/drop rules — and records the
//! **appearance half** (the cover's model, the full-block collision shape, the cover's light) as an
//! appearance gap: the pin has no per-position appearance, shape or light override for a block
//! another package registers. `notes.md` names every missing symbol.
//!
//! The rules live in [`runtime`]; [`support`] is the glue (registry cache, component, block entity
//! reads and writes), and this file is the one `impl Hooks` plus the two item Parts.
use mod_api::{
    self, BlockDropsEvent, ClientHost, ComponentTypesEvent, Flow, Hooks, HostSide,
    InteractionResult, ItemPart, LevelHost, LevelRef, Registrar, RegistrationContext, ServerHost,
    TagsUpdatedEvent, Text, TooltipEvent, UseOnEvent,
};

mod support;

pub mod runtime;

/// `ChatFormatting.DARK_PURPLE`, the colour upstream gives the worn block's name.
const BLOCK_COLOUR: u32 = 0xFFAA_00AA;
/// `ChatFormatting.GRAY`, the colour upstream gives the "Empty" line.
const EMPTY_COLOUR: u32 = 0xFFAA_AAAA;

/// The mod. It keeps no state of its own: everything a hook needs is the clicked stack, the block
/// and the transmitter's saved data.
#[derive(Default)]
struct Mod;

/// Drop a filled cover at the block at `pos`, as upstream's
/// `Containers.dropItemStack(x + 0.5, y + 0.5, z + 0.5)`.
fn drop_cover(host: &mut dyn ServerHost, level: LevelRef, pos: [i32; 3], cover: &str) {
    let Some(drop) = support::cover_drop(cover, pos) else {
        return;
    };
    let _ = level.spawn_item(
        host,
        drop.position[0],
        drop.position[1],
        drop.position[2],
        drop.stack,
        drop.pickup_delay,
    );
}

/// The server half of a cover click: put the held cover on the transmitter, or take one off.
///
/// Upstream's `CoverItem.useOn`: it needs a transmitter, a filled cover in hand and a block that
/// may be a cover, then replaces any cover already worn (dropping it), writes the new one and
/// consumes the held item. The empty cover strips a cover only with sneak held — the pin has no
/// Mekanism Configurator for upstream's wrench, which the parent port does not register
/// (`notes.md`, "Deviations").
fn cover_click(host: &mut dyn ServerHost, event: &UseOnEvent<'_>) -> Option<InteractionResult> {
    let level = host.level(host.dimension())?;
    support::transmitter_at(&*host, level, event.pos)?;
    let entity = host.block_entity(level, event.pos)?;
    let worn = support::worn_at(&*host, entity);
    let Some(incoming) = support::worn_by(event.stack) else {
        // An empty cover: strip, with sneak held.
        let sneaking = host
            .player(event.player)
            .and_then(|player| player.entity().is_shift_key_down(&*host))
            .unwrap_or(false);
        let worn = worn?;
        if !sneaking {
            return None;
        }
        return support::set_cover(host, entity, None).then(|| {
            drop_cover(host, level, event.pos, &worn);
            InteractionResult::Success
        });
    };
    if !runtime::is_identifier(&incoming)
        || !support::may_cover(&*host, level, &incoming, event.pos)
    {
        return Some(InteractionResult::Fail);
    }
    let (_, dropped) = runtime::attach(worn.as_deref(), &incoming);
    if !support::set_cover(host, entity, Some(&incoming)) {
        return Some(InteractionResult::Fail);
    }
    if let Some(old) = dropped {
        drop_cover(host, level, event.pos, &old);
    }
    support::consume_one(host, event.player, event.hand, event.stack);
    Some(InteractionResult::Success)
}

#[mod_api::horizon_mod]
impl Hooks for Mod {
    /// Declare the parts, the `cover_block` component and the special crafting kind.
    fn register(&self, registrar: &mut dyn Registrar, context: &RegistrationContext) {
        support::declare(registrar, context);
    }

    /// Register the material component id, so a saved stack's `mekanismcovers:cover_block` is a
    /// known, networked component.
    fn component_types(&self, context: &RegistrationContext, event: &mut ComponentTypesEvent<'_>) {
        support::register_components(context, event);
    }

    /// The registry and its tags were (re)published: the special recipe matches without a host, so
    /// keep its view of which item places which block.
    fn tags_updated(&self, host: HostSide, event: &mut TagsUpdatedEvent) {
        support::reload(host, event);
    }

    /// A transmitter broke: a cover it wears drops as a filled cover, beside the block's own loot.
    /// The block entity is still in the level here, so its saved data still holds the cover.
    fn block_drops(&self, level: &dyn LevelHost, event: &mut BlockDropsEvent<'_>) -> Flow {
        let Some(entity) = event.block_entity else {
            return Flow::Continue;
        };
        let Some(block) = level.state_block(event.state) else {
            return Flow::Continue;
        };
        if !runtime::is_transmitter(block) {
            return Flow::Continue;
        }
        let Some(cover) = support::worn_in_level(level, entity) else {
            return Flow::Continue;
        };
        let pos = [event.pos.x, event.pos.y, event.pos.z];
        if let Some(drop) = support::cover_drop(&cover, pos) {
            event.drops.push(drop);
        }
        Flow::Continue
    }
}

#[mod_api::horizon_part]
impl ItemPart for support::CoverPart {
    /// Upstream's `CoverItem.appendHoverText`: the worn block's name, or "Empty".
    fn tooltip(&self, _host: &dyn ClientHost, event: &mut TooltipEvent<'_>) {
        let worn = support::worn_by(event.stack);
        let colour = match runtime::tip(worn.as_deref()) {
            runtime::Tip::Empty => EMPTY_COLOUR,
            runtime::Tip::Block => BLOCK_COLOUR,
        };
        event
            .lines
            .push((support::tooltip_line(event.stack), colour));
    }

    /// Upstream's `CoverItem.useOn`.
    fn use_on(&self, host: HostSide, event: &mut UseOnEvent<'_>) -> Option<InteractionResult> {
        match host {
            HostSide::Server(host) => cover_click(host, event),
            HostSide::Client(host) => {
                // The server decides whether the block may be worn; the client only swings the
                // hand over a transmitter, as upstream answers SUCCESS on both sides.
                let level = host.level(host.dimension())?;
                support::transmitter_at(&*host, level, event.pos)?;
                Some(InteractionResult::Success)
            }
        }
    }
}

#[mod_api::horizon_part]
impl ItemPart for support::EmptyCoverPart {
    /// Upstream's `EmptyCoverItem.appendHoverText`: always "Empty".
    fn tooltip(&self, _host: &dyn ClientHost, event: &mut TooltipEvent<'_>) {
        event.lines.push((
            Text::translate(runtime::EMPTY_KEY, Vec::new()),
            EMPTY_COLOUR,
        ));
    }

    /// The strip route: sneak + right-click a covered transmitter with an empty cover.
    fn use_on(&self, host: HostSide, event: &mut UseOnEvent<'_>) -> Option<InteractionResult> {
        match host {
            HostSide::Server(host) => cover_click(host, event),
            HostSide::Client(_) => None,
        }
    }
}
