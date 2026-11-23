//! The rules of Mekanism Covers, with no game access: which blocks a cover may sit on, what a
//! second cover does to the first, and what the special crafting recipe accepts.
//!
//! The glue in [`crate`] reads the clicked block, the held stack and the transmitter's saved data;
//! this module decides, and the tests below are the mod's own numbers and rules.
//!
//! The constants land first and the rules are written from the tests (TDD): the red run for this
//! file is recorded in `VALIDATION.md`.

/// The saved-data key a covered transmitter carries: the id of the block it wears.
///
/// Upstream saves the cover as a serialised `BlockState` under `CoverState`; this port keeps the
/// block id, because the pin has no per-position state-for-placement for a block outside the
/// package (see `notes.md`), and a block id is what the item component holds too.
pub const COVER_KEY: &str = "mekanismcovers:cover";

/// The item component a filled cover carries: the id of the block it puts on a transmitter.
pub const COMPONENT: &str = "mekanismcovers:cover_block";

/// The tooltip line both cover items share: the mod's own translation key, "Empty".
pub const EMPTY_KEY: &str = "text.mekanismcovers.empty";

/// The namespace whose transmitters a cover may sit on.
pub const TRANSMITTER_NAMESPACE: &str = "mekanism";

/// The path suffixes upstream's `TileEntityTransmitter` family ends with: an energy cable, a
/// mechanical pipe, a pressurised tube.
pub const TRANSMITTER_SUFFIXES: [&str; 3] = ["_cable", "_pipe", "_tube"];

/// Whether `block` is a Mekanism transmitter, the only family upstream covers
/// (`CoverItem.useOn` asks `entity instanceof TileEntityTransmitter`).
///
/// The pin cannot name another package's block entity *type* at a click, so the family is read
/// from the block id the parent port registers: `mekanism:basic_universal_cable` and the rest of
/// the `<meta>_cable` / `_pipe` / `_tube` naming every Mekanism transmitter uses.
#[must_use]
pub fn is_transmitter(block: &str) -> bool {
    let Some((namespace, path)) = block.split_once(':') else {
        return false;
    };
    namespace == TRANSMITTER_NAMESPACE
        && TRANSMITTER_SUFFIXES
            .iter()
            .any(|suffix| path.len() > suffix.len() && path.ends_with(suffix))
}

/// Whether `id` is a namespaced block id this port may store: `minecraft:stone`, `mymod:a_block`.
///
/// A cover names a block, so the value has to survive a round trip through the item component and
/// the block entity's saved data; a malformed id is refused rather than stored and read back as
/// `None`.
#[must_use]
pub fn is_identifier(id: &str) -> bool {
    let Some((namespace, path)) = id.split_once(':') else {
        return false;
    };
    let well_formed = |part: &str| {
        !part.is_empty()
            && part.bytes().all(|byte| {
                byte.is_ascii_lowercase() || byte.is_ascii_digit() || b"_./-".contains(&byte)
            })
    };
    well_formed(namespace) && well_formed(path)
}

/// What putting `incoming` on a transmitter does to the cover it already wears.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Attach {
    /// The transmitter wore no cover: only the new one is written.
    First,
    /// The transmitter wore a cover, which comes off as a filled cover item.
    Replaced,
}

/// What one attach does: whether a cover falls off, and which one.
///
/// Upstream drops the old cover on *every* attach, an identical one included
/// (`MekanismCovers.removeCover(..., true)` before the new state is written), so a player never
/// loses a cover to a mis-click.
#[must_use]
pub fn attach(existing: Option<&str>, incoming: &str) -> (Attach, Option<String>) {
    debug_assert!(is_identifier(incoming), "the caller validates {incoming}");
    match existing {
        None => (Attach::First, None),
        Some(old) => (Attach::Replaced, Some(old.to_owned())),
    }
}

/// One cell of the crafting grid, as the special cover recipe sees it.
///
/// Each cell carries the facts the rule needs to refuse a stack it would destroy: a cover knows
/// whether it carries components of its own, and a block item knows whether its block has a block
/// entity and whether the stack carries components. The recipe consumes the stacks it is given and
/// keeps only a block id, so a stack with anything else in it (contents, a name, an enchantment, a
/// dye) would come back as a plain item after the cover is stripped.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Cell {
    /// Nothing in the cell.
    Empty,
    /// A cover or an empty cover.
    Cover {
        /// The block it wears, when it is filled.
        worn: Option<String>,
        /// Whether the stack carries components besides the mod's own `cover_block`.
        components: bool,
    },
    /// An item that places a block. Not named `Block`: the `fits` analyzer reads a `Block(..)`
    /// variant as a `mod_api::Block` construction and false-fails a later build (`notes.md`,
    /// trap 4).
    Places {
        /// The block the item places.
        block: String,
        /// Whether that block has a block entity, so the item carries state a block id cannot
        /// keep (a shulker box's contents live in its block entity).
        block_entity: bool,
        /// Whether the stack carries components of its own (contents, a name, an enchantment).
        components: bool,
    },
    /// Any other item.
    Other(String),
}

/// What one reading of the grid makes.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Plan {
    /// An empty cover and one block: a cover wearing that block.
    Fill(String),
    /// A filled cover alone: an empty cover, and the block it wore comes back.
    Strip(String),
}

/// Upstream's `CoverRecipe.matches`/`assemble`, as a rule over the grid: exactly one cover-family
/// item, and either one block beside an empty cover (fill) or nothing beside a filled one (strip).
///
/// A stack is only consumed when the cover can give back what it took. The recipe keeps a **block
/// id**, so it refuses:
///
/// * a block item whose block has a block entity (a shulker box's contents, a chest's inventory
///   live in the entity, not in the item's id);
/// * a stack that carries components of its own (contents, a custom name, an enchantment, damage);
/// * a cover stack that carries anything besides its own `cover_block`.
///
/// Upstream has the same rule for a block entity at attach time (`!(item.getBlock() instanceof
/// EntityBlock)`); the component half is the defect this port fixes, because a filled shulker box
/// used to become a cover that stripped back to an **empty** box (`notes.md`, "Upstream defects
/// fixed"). A refused stack is never consumed: no plan, no result.
///
/// Upstream also refuses a block whose default state is not a full collision cube; the recipe hook
/// at this pin has no host, so that half stays checked when the cover is put on a transmitter
/// (`notes.md`, "Deviations").
#[must_use]
pub fn special(cells: &[Cell]) -> Option<Plan> {
    let mut cover: Option<&Option<String>> = None;
    let mut cover_components = false;
    let mut block: Option<&str> = None;
    let mut block_lossy = false;
    for cell in cells {
        match cell {
            Cell::Empty => {}
            Cell::Cover { worn, components } => {
                if cover.is_some() {
                    return None;
                }
                cover = Some(worn);
                cover_components = *components;
            }
            Cell::Places {
                block: id,
                block_entity,
                components,
            } => {
                if block.is_some() {
                    return None;
                }
                block = Some(id.as_str());
                block_lossy = *block_entity || *components;
            }
            Cell::Other(_) => return None,
        }
    }
    if cover_components {
        return None;
    }
    match (cover, block) {
        (Some(None), Some(id)) if !block_lossy => Some(Plan::Fill(id.to_owned())),
        (Some(None), Some(_)) => None,
        (Some(Some(worn)), None) => Some(Plan::Strip(worn.clone())),
        _ => None,
    }
}

/// The tooltip a cover item shows under its name: the block it wears, or "Empty".
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Tip {
    /// The `text.mekanismcovers.empty` line.
    Empty,
    /// The worn block's own name.
    Block,
}

/// Which tooltip line a cover stack shows: a filled one names its block, an empty one says so.
#[must_use]
pub fn tip(worn: Option<&str>) -> Tip {
    match worn {
        Some(_) => Tip::Block,
        None => Tip::Empty,
    }
}

/// Where a drop from the block at `pos` appears: the block's centre, as upstream's
/// `Containers.dropItemStack(x + 0.5, y + 0.5, z + 0.5)`.
#[must_use]
pub fn centre(pos: [i32; 3]) -> [f64; 3] {
    [
        f64::from(pos[0]) + 0.5,
        f64::from(pos[1]) + 0.5,
        f64::from(pos[2]) + 0.5,
    ]
}

#[cfg(test)]
mod tests {
    use super::*;

    /// An empty cover with nothing on it.
    fn empty_cover() -> Cell {
        Cell::Cover {
            worn: None,
            components: false,
        }
    }

    /// A filled cover wearing `block`.
    fn cover_of(block: &str) -> Cell {
        Cell::Cover {
            worn: Some(block.to_owned()),
            components: false,
        }
    }

    /// A plain block item that places `block`.
    fn plain_block(block: &str) -> Cell {
        Cell::Places {
            block: block.to_owned(),
            block_entity: false,
            components: false,
        }
    }

    /// Every transmitter family the parent port's naming covers is a transmitter.
    #[test]
    fn a_cable_a_pipe_and_a_tube_are_transmitters() {
        for block in [
            "mekanism:basic_universal_cable",
            "mekanism:advanced_universal_cable",
            "mekanism:basic_mechanical_pipe",
            "mekanism:ultimate_pressurized_tube",
        ] {
            assert!(is_transmitter(block), "{block} is a transmitter");
        }
    }

    /// A machine, a plain block and another mod's cable are not transmitters.
    #[test]
    fn a_machine_or_another_namespace_is_not_a_transmitter() {
        for block in [
            "mekanism:basic_energy_cube",
            "minecraft:stone",
            "mekanismcovers:cover",
            "othermod:basic_universal_cable",
            "mekanism:cable",
            "mekanism:",
            "cable",
        ] {
            assert!(!is_transmitter(block), "{block} is not a transmitter");
        }
    }

    /// A stored cover id is a namespaced, lowercase id and nothing else.
    #[test]
    fn a_cover_names_a_namespaced_lowercase_block() {
        assert!(is_identifier("minecraft:stone"));
        assert!(is_identifier("mekanism:basic_universal_cable"));
        assert!(is_identifier("mymod:a_block/with.slash-dash"));
        for id in [
            "",
            "Stone",
            "minecraft:",
            ":stone",
            "minecraft:Stone",
            "a:b:c",
            "no namespace",
        ] {
            assert!(!is_identifier(id), "{id:?} is not a block id");
        }
    }

    /// The first cover on a bare transmitter drops nothing.
    #[test]
    fn the_first_cover_replaces_nothing() {
        assert_eq!(attach(None, "minecraft:stone"), (Attach::First, None));
    }

    /// A second cover takes the first one off, the same block included.
    #[test]
    fn a_second_cover_drops_the_one_it_replaces() {
        assert_eq!(
            attach(Some("minecraft:stone"), "minecraft:glass"),
            (Attach::Replaced, Some("minecraft:stone".to_owned()))
        );
        assert_eq!(
            attach(Some("minecraft:stone"), "minecraft:stone"),
            (Attach::Replaced, Some("minecraft:stone".to_owned()))
        );
    }

    /// An empty cover and one block make a cover wearing that block.
    #[test]
    fn an_empty_cover_and_a_block_fill_it() {
        let cells = [empty_cover(), plain_block("minecraft:stone"), Cell::Empty];
        assert_eq!(
            special(&cells),
            Some(Plan::Fill("minecraft:stone".to_owned()))
        );
    }

    /// A filled cover alone strips back to an empty one and gives the block back.
    #[test]
    fn a_filled_cover_alone_strips_back_to_empty() {
        assert_eq!(
            special(&[cover_of("minecraft:stone")]),
            Some(Plan::Strip("minecraft:stone".to_owned()))
        );
    }

    /// An empty cover alone, a block alone, and an empty grid make nothing.
    #[test]
    fn an_empty_cover_alone_makes_nothing() {
        assert_eq!(special(&[empty_cover()]), None);
        assert_eq!(special(&[plain_block("minecraft:stone")]), None);
        assert_eq!(special(&[]), None);
        assert_eq!(special(&[Cell::Empty, Cell::Empty]), None);
    }

    /// Two covers in the grid make nothing, filled or not.
    #[test]
    fn two_covers_in_the_grid_make_nothing() {
        assert_eq!(special(&[empty_cover(), empty_cover()]), None);
        assert_eq!(
            special(&[cover_of("minecraft:stone"), cover_of("minecraft:glass")]),
            None
        );
    }

    /// A second block beside an empty cover cannot fill it: upstream wants exactly one.
    #[test]
    fn an_empty_cover_takes_exactly_one_block() {
        assert_eq!(
            special(&[
                empty_cover(),
                plain_block("minecraft:stone"),
                plain_block("minecraft:glass"),
            ]),
            None
        );
    }

    /// An item that places no block cannot fill a cover.
    #[test]
    fn a_non_block_item_cannot_fill_a_cover() {
        assert_eq!(
            special(&[empty_cover(), Cell::Other("minecraft:stick".to_owned())]),
            None
        );
    }

    /// A filled cover beside a block cannot strip: upstream wants the cover alone.
    #[test]
    fn a_filled_cover_beside_a_block_cannot_strip() {
        assert_eq!(
            special(&[cover_of("minecraft:stone"), plain_block("minecraft:glass")]),
            None
        );
    }

    /// A filled shulker box is refused: the recipe keeps only a block id, so its contents would be
    /// lost (the strip would hand back an empty box). No plan means no result and no consumption.
    #[test]
    fn a_filled_shulker_box_cannot_fill_a_cover() {
        assert_eq!(
            special(&[
                empty_cover(),
                Cell::Places {
                    block: "minecraft:shulker_box".to_owned(),
                    block_entity: true,
                    components: true,
                },
            ]),
            None
        );
    }

    /// An empty shulker box (or a chest, a furnace) is refused too: its block entity is where the
    /// item's state lives, and a cover stores a block id.
    #[test]
    fn a_block_with_a_block_entity_cannot_fill_a_cover() {
        for block in [
            "minecraft:shulker_box",
            "minecraft:chest",
            "minecraft:white_shulker_box",
        ] {
            assert_eq!(
                special(&[
                    empty_cover(),
                    Cell::Places {
                        block: block.to_owned(),
                        block_entity: true,
                        components: false,
                    },
                ]),
                None,
                "{block} has a block entity and cannot be a cover"
            );
        }
    }

    /// A named, enchanted or otherwise component-carrying block is refused: the component would
    /// not survive the round trip through the cover's block id.
    #[test]
    fn a_block_with_components_cannot_fill_a_cover() {
        assert_eq!(
            special(&[
                empty_cover(),
                Cell::Places {
                    block: "minecraft:stone".to_owned(),
                    block_entity: false,
                    components: true,
                },
            ]),
            None
        );
    }

    /// A cover that carries components of its own is refused on both routes: filling it would
    /// drop them, and stripping it would hand back a bare empty cover.
    #[test]
    fn a_cover_with_components_of_its_own_is_refused() {
        let named = |worn: Option<&str>| Cell::Cover {
            worn: worn.map(str::to_owned),
            components: true,
        };
        assert_eq!(
            special(&[named(None), plain_block("minecraft:stone")]),
            None,
            "a named empty cover cannot be filled"
        );
        assert_eq!(
            special(&[named(Some("minecraft:stone"))]),
            None,
            "a named filled cover cannot be stripped"
        );
    }

    /// A filled cover names its block in the tooltip; an empty one says "Empty".
    #[test]
    fn the_tooltip_follows_the_cover() {
        assert_eq!(tip(None), Tip::Empty);
        assert_eq!(tip(Some("minecraft:stone")), Tip::Block);
    }

    /// A drop leaves from the middle of the block, not its corner.
    #[test]
    fn a_drop_leaves_from_the_block_centre() {
        assert_eq!(centre([8, 64, -3]), [8.5, 64.5, -2.5]);
    }
}
