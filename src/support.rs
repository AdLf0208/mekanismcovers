//! Game-side glue: the registry cache the host-free recipe needs, the cover component, and the
//! reads and writes of a transmitter's own saved data.
//!
//! Upstream keeps the cover in a mixin field on `TileEntityTransmitter` and saves it under
//! `CoverState`. A separate Horizon package cannot add a field to another package's block entity
//! type, and the pin has no per-position state of its own, so the cover rides the transmitter's
//! **own saved data** under [`runtime::COVER_KEY`]: `BlockEntityRef::data` reads it on both sides
//! and `merge_data`/`replace_data` write it through `/data merge block`'s path, which is
//! transactional, dirties the chunk and sends clients the update. The parent port's cable tick
//! reads the whole compound and writes it back, so the key survives every tick (measured in the
//! e2e: still there after 40 ticks and after a save/reload).

use mod_api::{
    self, BlockEntityRef, BlockShapeKind, Component, ComponentTypesEvent, CraftingGrid,
    CraftingRecipeCodec, CraftingRecipeKind, Hand, Host, HostBlockStates, HostSide,
    HostTransaction, ItemDrop, ItemKey, ItemPlace, ItemResource, ItemStack, LevelHost, LevelRef,
    Registrar, RegistrationContext, ServerHost, Tag, TagsUpdatedEvent, Text,
};

use crate::runtime::{self, Cell, Plan};

/// The filled cover item.
pub(crate) const COVER_ITEM: &str = "mekanismcovers:cover";
/// The empty cover item.
pub(crate) const EMPTY_COVER_ITEM: &str = "mekanismcovers:empty_cover";

/// A block-placing item and the block it places (`BlockItem.getBlock`).
#[derive(Clone, Debug)]
struct Placed {
    /// The item.
    item: ItemKey,
    /// The block the item places.
    block: String,
}

/// The two registry facts the host-free recipe needs: which item places which block
/// (`instanceof BlockItem` plus `getBlock`), and which item is block `x`'s (`Block.asItem`).
///
/// `CraftingRecipeKind::matches`/`assemble`/`remaining_items` take no host, so these are cached
/// whenever one is available: [`reload`] runs after every registry/tag load.
static PLACED: std::sync::RwLock<Vec<Placed>> = std::sync::RwLock::new(Vec::new());
/// Block id to its own item, for the block a stripped cover gives back.
static BLOCK_ITEMS: std::sync::RwLock<Vec<(String, ItemKey)>> = std::sync::RwLock::new(Vec::new());

/// Re-reads the item registry: which item places which block, and each block's own item.
pub(crate) fn refresh_registry(host: &dyn Host) {
    let mut placed = Vec::new();
    let mut block_items = Vec::new();
    for item in host.item_keys() {
        let Some(block) = host.item_block(item) else {
            continue;
        };
        let block_id = block.id(host);
        placed.push(Placed {
            item,
            block: block_id.clone(),
        });
        if let Some(own) = host.block_item(block) {
            block_items.push((block_id, own));
        }
    }
    *PLACED
        .write()
        .unwrap_or_else(std::sync::PoisonError::into_inner) = placed;
    *BLOCK_ITEMS
        .write()
        .unwrap_or_else(std::sync::PoisonError::into_inner) = block_items;
}

/// The block the stack places, when it places one: upstream's `instanceof BlockItem`.
fn placed_block(stack: &ItemStack) -> Option<String> {
    let item = stack.item();
    PLACED
        .read()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
        .iter()
        .find(|placed| placed.item == item)
        .map(|placed| placed.block.clone())
}

/// Block `id`'s own item stack, which stripping a cover gives back.
fn block_item_stack(id: &str) -> Option<ItemStack> {
    let key = BLOCK_ITEMS
        .read()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
        .iter()
        .find(|(block, _)| block == id)
        .map(|(_, item)| *item)?;
    ItemStack::new(key, 1)
}

/// The material a cover is made of: the `mekanismcovers:cover_block` component's block id.
#[derive(Clone, Copy, Debug, Default)]
pub(crate) struct CoverBlock;

impl Component for CoverBlock {
    type Value = String;

    fn id(&self) -> &str {
        runtime::COMPONENT
    }

    fn decode(&self, value: &Tag) -> Option<Self::Value> {
        match value {
            Tag::String(id) => {
                let id = id.to_string_lossy();
                runtime::is_identifier(&id).then_some(id)
            }
            _ => None,
        }
    }

    fn encode(&self, value: Self::Value) -> Tag {
        Tag::String(value.as_str().into())
    }
}

/// The block a filled cover stack wears.
pub(crate) fn worn_by(stack: &ItemStack) -> Option<String> {
    stack.get(&CoverBlock)
}

/// The block a transmitter's saved data says it wears.
fn worn_in(data: &mod_api::Compound) -> Option<String> {
    match data.get(&runtime::COVER_KEY.into()) {
        Some(Tag::String(id)) => {
            let id = id.to_string_lossy();
            runtime::is_identifier(&id).then_some(id)
        }
        _ => None,
    }
}

/// The block the transmitter `entity` wears, read from its own saved data.
pub(crate) fn worn_at(host: &dyn Host, entity: BlockEntityRef) -> Option<String> {
    worn_in(&entity.data(host)?)
}

/// The same read from a hook that only has the level (`block_drops` gets a [`LevelHost`]).
pub(crate) fn worn_in_level(level: &dyn LevelHost, entity: BlockEntityRef) -> Option<String> {
    worn_in(&level.block_entity_data(entity)?)
}

/// Write `cover` into the transmitter's saved data, or take it away for `None`.
///
/// The write goes through `/data merge block`'s path: it loads the compound transactionally,
/// marks the chunk changed and sends the block update, so a client sees the new cover and the
/// parent port's own tick writes the key back untouched.
pub(crate) fn set_cover(
    host: &mut dyn ServerHost,
    entity: BlockEntityRef,
    cover: Option<&str>,
) -> bool {
    let Some(mut data) = entity.data(&*host) else {
        return false;
    };
    match cover {
        Some(id) => {
            data.insert(runtime::COVER_KEY.into(), Tag::String(id.into()));
            entity.merge_data(host, data).unwrap_or(false)
        }
        None => {
            if data.remove(&runtime::COVER_KEY.into()).is_none() {
                return true;
            }
            entity.replace_data(host, data).unwrap_or(false)
        }
    }
}

/// A filled cover as an item drop at `pos`.
pub(crate) fn cover_drop(cover: &str, pos: [i32; 3]) -> Option<ItemDrop> {
    let key = cover_item()?;
    let mut stack = ItemStack::new(key, 1)?;
    stack.set(&CoverBlock, cover.to_owned()).ok()?;
    Some(ItemDrop::new(stack, runtime::centre(pos), [0.0; 3], 10))
}

/// The filled cover item's key, resolved once at registration.
static COVER_ITEM_KEY: std::sync::RwLock<Option<ItemKey>> = std::sync::RwLock::new(None);

/// The empty cover item's key, resolved once at registration.
static EMPTY_ITEM_KEY: std::sync::RwLock<Option<ItemKey>> = std::sync::RwLock::new(None);

/// The filled cover item's key.
pub(crate) fn cover_item() -> Option<ItemKey> {
    *COVER_ITEM_KEY
        .read()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
}

/// The empty cover item's key.
pub(crate) fn empty_cover_item() -> Option<ItemKey> {
    *EMPTY_ITEM_KEY
        .read()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
}

/// Whether `id` may be a cover: a block that exists, whose default state is a full collision
/// cube and has no block entity — upstream's `state.isCollisionShapeFullBlock(level, ZERO)` and
/// `!(blockItem.getBlock() instanceof EntityBlock)`, asked when the cover is put on a transmitter
/// because the recipe hook has no host.
pub(crate) fn may_cover(host: &dyn Host, level: LevelRef, id: &str, pos: [i32; 3]) -> bool {
    let Some(block) = host.block_key(id) else {
        return false;
    };
    let Some(state) = host.block_state_default(block) else {
        return false;
    };
    if host.block_states().has_block_entity(state) != Some(false) {
        return false;
    }
    let Some(boxes) = level.block_shape(host, state, pos, BlockShapeKind::Collision) else {
        return false;
    };
    is_full_cube(&boxes)
}

/// Whether a collision-shape box list is exactly one whole block.
fn is_full_cube(boxes: &[[f64; 6]]) -> bool {
    const FULL: [f64; 6] = [0.0, 0.0, 0.0, 1.0, 1.0, 1.0];
    boxes.len() == 1
        && boxes[0]
            .iter()
            .zip(FULL.iter())
            .all(|(got, want)| (got - want).abs() < 1e-6)
}

/// The block id at `pos`, when it is a Mekanism transmitter.
pub(crate) fn transmitter_at(host: &dyn Host, level: LevelRef, pos: [i32; 3]) -> Option<String> {
    let block = level.block(host, pos)?;
    let id = block.id(host);
    runtime::is_transmitter(&id).then_some(id)
}

/// Consume one of the stack the click holds, as vanilla's `ItemStack.shrink(1)` does.
pub(crate) fn consume_one(host: &mut dyn ServerHost, player: u128, hand: Hand, stack: &ItemStack) {
    let resource = ItemResource::of(stack);
    let place = ItemPlace::PlayerHand { player, hand };
    let _ = host.transaction(|host, tx| {
        place.extract(host, tx, &resource, 1);
        Ok::<(), ()>(())
    });
}

/// Upstream's line under a cover's name: the worn block's own name, or "Empty".
pub(crate) fn tooltip_line(stack: &ItemStack) -> Text {
    match runtime::tip(worn_by(stack).as_deref()) {
        runtime::Tip::Empty => Text::translate(runtime::EMPTY_KEY, Vec::new()),
        runtime::Tip::Block => {
            let id = worn_by(stack).unwrap_or_default();
            // `Block.getDescriptionId` is `block.<namespace>.<path>`.
            let key = match id.split_once(':') {
                Some((namespace, path)) => format!("block.{namespace}.{path}"),
                None => runtime::EMPTY_KEY.to_owned(),
            };
            Text::translate(key, Vec::new())
        }
    }
}

/// The grid as [`runtime::special`] reads it.
fn cells_of(grid: &CraftingGrid) -> Vec<Cell> {
    let cover = cover_item();
    let empty = empty_cover_item();
    grid.cells
        .iter()
        .map(|cell| match cell {
            None => Cell::Empty,
            Some(stack) => {
                let item = stack.item();
                if Some(item) == empty {
                    Cell::Cover(None)
                } else if Some(item) == cover {
                    Cell::Cover(worn_by(stack))
                } else if let Some(block) = placed_block(stack) {
                    Cell::Places(block)
                } else {
                    Cell::Other(String::new())
                }
            }
        })
        .collect()
}

/// The recipe's decoded body: the category, which is all a `crafting_special_cover` file carries.
#[derive(Clone, Debug, PartialEq, Eq, mod_api::Wire)]
pub(crate) struct SpecialCover {
    /// The recipe book category (`misc`).
    pub category: String,
}

impl SpecialCover {
    /// The category upstream's file declares.
    const DEFAULT: &'static str = "misc";
    /// The recipe type id.
    const KIND: &'static str = "mekanismcovers:crafting_special_cover";
}

/// Upstream's `crafting_special_cover`: fill an empty cover with a block, or strip a filled one.
pub(crate) struct CoverRecipe {
    /// The filled cover item.
    cover: ItemKey,
    /// The empty cover item.
    empty: ItemKey,
}

impl CraftingRecipeKind for CoverRecipe {
    type Value = SpecialCover;

    fn codec(&self) -> Option<CraftingRecipeCodec<Self::Value>> {
        Some(CraftingRecipeCodec::wire())
    }

    fn decode(&self, json: &str) -> Result<Self::Value, String> {
        use mod_api::serde_json::Value;
        let value: Value =
            mod_api::serde_json::from_str(json).map_err(|error| error.to_string())?;
        if let Some(kind) = value.get("type").and_then(Value::as_str)
            && kind != SpecialCover::KIND
        {
            return Err(format!("{kind} is not a special cover recipe"));
        }
        let category = value
            .get("category")
            .and_then(Value::as_str)
            .unwrap_or(SpecialCover::DEFAULT);
        Ok(SpecialCover {
            category: category.to_owned(),
        })
    }

    fn write(&self, value: &Self::Value) -> Result<String, String> {
        Ok(format!(
            "{{\"type\":\"{}\",\"category\":\"{}\"}}",
            SpecialCover::KIND,
            value.category
        ))
    }

    fn matches(&self, _value: &Self::Value, grid: CraftingGrid) -> bool {
        runtime::special(&cells_of(&grid)).is_some()
    }

    fn assemble(&self, _value: &Self::Value, grid: CraftingGrid) -> Option<ItemStack> {
        match runtime::special(&cells_of(&grid))? {
            Plan::Fill(block) => {
                let mut out = ItemStack::new(self.cover, 1)?;
                out.set(&CoverBlock, block).ok()?;
                Some(out)
            }
            Plan::Strip(_) => ItemStack::new(self.empty, 1),
        }
    }

    fn remaining_items(
        &self,
        _value: &Self::Value,
        grid: CraftingGrid,
    ) -> Option<Vec<Option<ItemStack>>> {
        let block = match runtime::special(&cells_of(&grid))? {
            Plan::Strip(block) => block,
            // A fill keeps everything it is given: the block becomes the cover's material.
            Plan::Fill(_) => return Some(vec![None; grid.cells.len()]),
        };
        let remainder = block_item_stack(&block);
        Some(
            grid.cells
                .iter()
                .map(|cell| match cell {
                    Some(stack) if Some(stack.item()) == cover_item() => remainder.clone(),
                    _ => None,
                })
                .collect(),
        )
    }
}

/// Register the parts, the component and the special crafting kind.
pub(crate) fn declare(registrar: &mut dyn Registrar, context: &RegistrationContext) {
    let cover = registrar.item_key(COVER_ITEM);
    let empty = registrar.item_key(EMPTY_COVER_ITEM);
    *COVER_ITEM_KEY
        .write()
        .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(cover);
    *EMPTY_ITEM_KEY
        .write()
        .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(empty);
    registrar.register_crafting_recipe_serializer(
        "crafting_special_cover",
        CoverRecipe { cover, empty },
    );
    registrar.item_part(cover, CoverPart);
    registrar.item_part(empty, EmptyCoverPart);
    let _ = context;
}

/// Register the material component id so a saved stack's `mekanismcovers:cover_block` is a known,
/// networked component.
pub(crate) fn register_components(
    _context: &RegistrationContext,
    event: &mut ComponentTypesEvent<'_>,
) {
    if !event.types.iter().any(|known| known == runtime::COMPONENT) {
        event.types.push(runtime::COMPONENT.to_owned());
    }
}

/// Keep the host-free recipe's registry view fresh after every registry/tag load.
pub(crate) fn reload(host: HostSide, _event: &mut TagsUpdatedEvent) {
    match host {
        HostSide::Server(host) => refresh_registry(host),
        HostSide::Client(host) => refresh_registry(host),
    }
}

/// The cover item: attach on a transmitter, tooltip the worn block.
#[derive(Clone, Copy, Debug)]
pub(crate) struct CoverPart;

/// The empty cover item: strip with sneak + right-click, tooltip "Empty".
#[derive(Clone, Copy, Debug)]
pub(crate) struct EmptyCoverPart;
