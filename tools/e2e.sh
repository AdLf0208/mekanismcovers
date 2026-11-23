#!/usr/bin/env bash
# In-game check for Mekanism Covers (flat SDK package, mod API 0.2):
# `mekanismcovers:empty_cover` and `mekanismcovers:cover`, the jar's shaped empty-cover recipe, the
# mod's own `crafting_special_cover` fill/strip recipe, and the cover a Mekanism transmitter
# carries in its own saved data — attach, replace (the old cover drops), sneak-strip, the drop on
# breaking the transmitter, the two refusals (a block that is not a full cube, a click that is
# not a transmitter), and the two stack-carrying refusals: the fill's (a filled shulker box, a
# named block, a cover carrying components of its own) and the click's (a filled cover carrying
# components of its own, which the transmitter's block id cannot keep) — no result, nothing
# consumed.
#
# The package needs its parent compiled into the same game: a cover is worn by
# `mekanism:basic_universal_cable`, whose block entity is declared by the `mekanism` port's code.
# `tools/build-game.sh` builds both in one game (`Compiling mekanism (1 of 2)` /
# `Compiling mekanismcovers (2 of 2)`) and prints GAME/CTL/CONTROL_GAME/RES; there is no
# `--dev-mod` route, because that loads content only and the cable's block entity is code.
#
# Run (one lease, one leg):
#   BUILD_LOCAL=1 ports/tools/build-slot.sh run --job W1-mekanismcovers --port ports/mekanismcovers \
#       --step e2e -- bash ports/mekanismcovers/tools/e2e.sh
#
# The End arena (stone floor at y=63, cleared volume to y=74, every non-player entity removed):
#   C  =  8,64,8   the spare cable everything is attached to, replaced and broken
#   T  = 12,64,8   a second cable, for the filled-shulker gesture of phase M and the named cover
#                  of phase N
#   X  = 16,64,8   a stone block: the fix "not a transmitter" control
#   B  = 20,64,8   the crafting table the recipes are made on
#
# CONTROL=1 (the default) also launches the same Nightly **without either package**, where
# `mekanismcovers:empty_cover` is unknown and the cable cannot be placed, so nothing the main run
# proves can come from the plain build. SELFTEST=1 flips the replace phase's "exactly one cover
# dropped" assertion, SELFTEST=refusal flips the filled-shulker refusal and SELFTEST=named flips
# the named cover's click refusal, so any of those runs MUST exit 1. NEGATIVE=1 flips the control
# leg's "the plain build does not know this item" assertion, so the control is proven able to fail
# too (that leg needs CONTROL=1 and CONTROL_GAME).
set -Eeuo pipefail
export LC_ALL=C
[ -z "${MC_DEBUG:-}" ] || set -x

SELFTEST=${SELFTEST:-0}
NEGATIVE=${NEGATIVE:-0}
CONTROL=${CONTROL:-1}
KEEP=${KEEP:-0}

CLONE=${CLONE:-$(cd "$(dirname "$0")/../../.." && pwd)}
PORT=$CLONE/ports/mekanismcovers
# /tmp is a small tmpfs on this box: the harness may point E2E_TMP at a disk-backed root.
# The game runs from the per-run scratch root, so its `saves/`, options.txt and caches stay there:
# a leg starts a fresh world, and no Mojang file lands in the campaign tree.
TMP_ROOT=${E2E_TMP:-/tmp/opencode}
SOCK=${SOCK:-$TMP_ROOT/mekanismcovers-e2e.sock}
RES=${RES:-${HORIZON_RES:?RES must point at the prepared 26.3 resources}}
GAME=${GAME:?GAME must be the paired build's client (tools/build-game.sh --env)}
CTL=${CTL:?CTL must be the paired build's horizon-ctl}
CONTROL_GAME=${CONTROL_GAME:-}
WORLD=MekCoversE2E
CONTROL_WORLD=MekCoversControl

COVER=mekanismcovers:cover
EMPTY=mekanismcovers:empty_cover
CABLE=mekanism:basic_universal_cable

C_X=8; C_Y=64; C_Z=8
T_X=12; T_Z=8
X_X=16; X_Z=8
B_X=20; B_Z=8

mkdir -p "$TMP_ROOT"
SCRATCH=$(mktemp -d "$TMP_ROOT"/mekanismcovers-e2e.XXXXXX)
LOG=$SCRATCH/run.log
trap 'status=$?; echo "EXIT:$status"' EXIT
exec > >(tee -a "$LOG") 2>&1

say() { printf '%s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*"; exit 1; }
ctl() { "$CTL" --socket "$SOCK" "$@"; }

# Stand next to the block at X Z and right-click it: the interaction range is a few blocks, and
# every phase happens at its own arena position.
use_block() { # use_block X Y Z LABEL
    local x=$1 y=$2 z=$3
    ctl command "execute in minecraft:the_end run tp @s $((x)).5 $y $((z + 1)).5" >/dev/null
    ctl wait 3 >/dev/null
    ctl interact "$x" "$y" "$z" >/dev/null || printf '  interact %s,%s,%s answered %s\n' "$x" "$y" "$z" "$?"
    ctl wait 5 >/dev/null
}

launch() { # world dir game
    local world=$1 dir=$2 game=$3
    mkdir -p "$dir"/{data,config,home,game}
    (
        # The game's folder is its working directory: `saves/`, options.txt and caches land there,
        # not in the campaign tree, and every run starts from a fresh world.
        cd "$dir" || exit 1
        export HORIZON_HOME=$dir/game XDG_DATA_HOME=$dir/data XDG_CONFIG_HOME=$dir/config HOME=$dir/home
        rm -f "$SOCK"
        ctl launch --game "$game" --world "$world" --seed 20261121 --creative --offscreen --wait \
            --resources "$RES"
    )
}

stop_game() {
    ctl quit >/dev/null 2>&1 || true
    local lock="$SCRATCH/saves/$WORLD/session.lock"
    for _ in $(seq 1 40); do [ -e "$lock" ] || break; sleep 1; done
    sleep 2
}

# The End arena: a stone floor, the air above it cleared, and no stray entities. The two recipes
# open a crafting table, so the client runs `--offscreen`: a headless client never opens a screen
# and `ctl screen` hangs there.
arena() {
    ctl command "execute in minecraft:the_end run tp @s 0.5 64 3.5" >/dev/null
    local loaded=false
    for _ in $(seq 1 120); do
        ctl wait 5 >/dev/null
        if [ "$(ctl block $C_X 63 $C_Z | jq -r '.loaded // false')" = true ]; then loaded=true; break; fi
    done
    [ "$loaded" = true ] || fail "the End arena chunk never loaded"
    ctl command "execute in minecraft:the_end run fill -8 63 -8 32 63 32 minecraft:stone" >/dev/null
    ctl command "execute in minecraft:the_end run fill -8 64 -8 32 74 32 minecraft:air" >/dev/null
    ctl command "execute in minecraft:the_end run kill @e[type=!player]" >/dev/null
    ctl command "execute in minecraft:the_end run setblock $X_X $C_Y $X_Z minecraft:stone" >/dev/null
    ctl command "execute in minecraft:the_end run setblock $B_X $C_Y $B_Z minecraft:crafting_table" >/dev/null
    ctl wait 20 >/dev/null
}

# ---------------------------------------------------------------- readings
count() { ctl inventory | jq -r --arg i "$1" '.counts[$i] // 0'; }
ground() { # ground ITEM: how many of ITEM lie on the floor within 32 blocks
    ctl entities 32 item \
        | jq --arg item "$1" '[.entities[] | select(.kind == "item" and .item.item == $item) | .item.count] | add // 0'
}
# Everything of one item the run can see: in the inventory plus on the floor. A drop lands
# within pickup range of the player who made it, so a bare floor count proves nothing.
total() { echo $(( $(count "$1") + $(ground "$1") )); }
# Wait up to 20 ticks for a total to reach WANT, then echo what it reads. An item spawned by a
# click reaches the control client's entity list (and a nearby player's inventory) a tick or two
# after the action, so sampling once right after the click can read 0 although the drop is there.
await_total() { # await_total ITEM WANT
    local got; got=$(total "$1")
    for _ in $(seq 1 10); do
        [ "$got" = "$2" ] && break
        ctl wait 2 >/dev/null
        got=$(total "$1")
    done
    echo "$got"
}
# Select the hotbar slot that holds ITEM, 1-based. `ctl give` lands in the first free slot, so a
# leftover (a cover an earlier phase picked up) can take slot 0 and `select 1` would hold it.
select_item() { # select_item ITEM
    local slot
    slot=$(ctl inventory | jq -r --arg i "$1" \
        '[.hotbar | to_entries[] | select(.value.item == $i) | .key] | first // empty')
    [ -n "$slot" ] || fail "no $1 in the hotbar"
    ctl select $((slot + 1)) >/dev/null; ctl wait 2 >/dev/null
}
reply() { ctl command "$1" | jq -r '.chat // [] | join(" | ")'; }
ok_of() { ctl command "$1" | jq -r '.ok'; }
data_all() { reply "execute in minecraft:the_end run data get block $1 $2 $3"; }
cover_key() { reply "execute in minecraft:the_end run data get block $1 $2 $3 mekanismcovers:cover"; }

expect_cover() { # expect_cover X Y Z ID LABEL
    local got; got=$(cover_key "$1" "$2" "$3")
    case "$got" in
        *"\"$4\""*) say "  $5 -> the transmitter wears $4" ;;
        *) fail "$5: expected $4 in the transmitter's saved data, got: $got" ;;
    esac
}
expect_no_cover() { # X Y Z LABEL
    local got; got=$(cover_key "$1" "$2" "$3")
    case "$got" in
        *"Found no elements"*) say "  $4 -> the transmitter wears no cover" ;;
        *) fail "$4: expected no cover, got: $got" ;;
    esac
}

# ---------------------------------------------------------------- crafting
# The crafting table's menu: 3x3 grid at 100..108 (row-major) and the result at 200; the player's
# own slots keep their inventory numbers. `click-slot <grid>` puts a whole stack in a cell, so each
# cell is right-clicked with one item, as the campaign's other recipe legs do.
GRID=(100 101 102 103 104 105 106 107 108)
RESULT=200

menu_slots() { ctl screen | jq -c '.slots // []'; }
slot_item() { menu_slots | jq -r --argjson s "$1" '[.[] | select(.slot == $s) | .item] | first // ""'; }
slot_where() { menu_slots | jq -r --arg i "$1" '[.[] | select(.item == $i) | .slot] | first // ""'; }

open_table() {
    ctl command "clear @s" >/dev/null
    ctl command "execute in minecraft:the_end run tp @s 19.5 64 8.5" >/dev/null
    ctl wait 3 >/dev/null
    ctl interact $B_X $C_Y $B_Z >/dev/null || true
    ctl wait 5 >/dev/null
    [ "$(menu_slots)" != "[]" ] || fail "the crafting table did not open"
}

place_one() { # place_one ITEM SLOT
    local from; from=$(slot_where "$1")
    [ -n "$from" ] || fail "no $1 in the inventory while crafting"
    ctl click-slot "$from" >/dev/null; ctl wait 1 >/dev/null
    ctl click-slot "$2" right >/dev/null; ctl wait 1 >/dev/null
    ctl click-slot "$from" >/dev/null; ctl wait 2 >/dev/null
}

expect_result() { # expect_result ITEM COUNT LABEL
    local got; got=$(slot_item $RESULT)
    [ "$got" = "$1" ] || fail "$3: expected $1 at the result, got '$got'"
    local n; n=$(menu_slots | jq -r --argjson s $RESULT '[.[] | select(.slot == $s) | .count] | first // 0')
    [ "$n" = "$2" ] || fail "$3: expected $2 $1 at the result, got $n"
    say "  $3 -> $n x $1"
}

expect_no_result() { # expect_no_result LABEL
    local got; got=$(slot_item $RESULT)
    [ -z "$got" ] || fail "$1: expected no crafting result, got '$got'"
    say "  $1 -> no crafting result"
}

# One stack of the open menu as JSON, by item id: its `components` prove the stack the grid holds
# still carries what it had (a shulker box's contents, a custom name).
stack_json() { # stack_json ITEM
    menu_slots | jq -c --arg i "$1" '[.[] | select(.item == $i)] | first // {}'
}

take_result() { # take_result HOTBAR
    ctl click-slot $RESULT >/dev/null; ctl wait 2 >/dev/null
    ctl click-slot "$1" >/dev/null; ctl wait 2 >/dev/null
}

close_table() { ctl close >/dev/null; ctl wait 3 >/dev/null; }

# ================================================================ main leg
say "== launch: the paired build (mekanism + mekanismcovers) =="
launch "$WORLD" "$SCRATCH" "$GAME" || fail "the game did not launch"
say "  version: $(ctl state | jq -r '.launch.game')"
arena

say "== A. both items exist and an unknown id is refused =="
ctl command "clear @s" >/dev/null
ctl give $EMPTY 2 >/dev/null
ctl give $COVER 2 >/dev/null
ctl wait 3 >/dev/null
[ "$(count $EMPTY)" = 2 ] || fail "expected 2 empty covers, got $(count $EMPTY)"
[ "$(count $COVER)" = 2 ] || fail "expected 2 covers, got $(count $COVER)"
say "  empty_cover x2 and cover x2 are in the inventory"
unknown=$(reply "give @s mekanismcovers:not_a_thing 1")
case "$unknown" in
    *Unknown*|*unknown*|*"not exist"*) say "  an unknown id is refused: $unknown" ;;
    *) fail "an unknown item id was not refused: $unknown" ;;
esac

say "== B. the jar's shaped empty-cover recipe (4 nuggets, 4 planks, 1 glass) =="
open_table
ctl give minecraft:iron_nugget 4 >/dev/null
ctl give minecraft:oak_planks 4 >/dev/null
ctl give minecraft:glass 1 >/dev/null
ctl wait 3 >/dev/null
# pattern: # R # / R G R / # R #
place_one minecraft:iron_nugget 100
place_one minecraft:oak_planks 101
place_one minecraft:iron_nugget 102
place_one minecraft:oak_planks 103
place_one minecraft:glass 104
place_one minecraft:oak_planks 105
place_one minecraft:iron_nugget 106
place_one minecraft:oak_planks 107
place_one minecraft:iron_nugget 108
expect_result $EMPTY 4 "shaped cover recipe"
take_result 0
ctl wait 3 >/dev/null
[ "$(slot_where minecraft:iron_nugget)" = "" ] || fail "the nuggets were not consumed"
[ "$(slot_where minecraft:oak_planks)" = "" ] || fail "the planks were not consumed"
[ "$(slot_where minecraft:glass)" = "" ] || fail "the glass was not consumed"
say "  its four nuggets, four planks and glass were consumed"
close_table
ctl select 1 >/dev/null; ctl wait 2 >/dev/null
[ "$(count $EMPTY)" = 4 ] || fail "the craft did not give 4 empty covers, got $(count $EMPTY)"
ctl command "clear @s" >/dev/null

say "== C. the special cover recipe fills an empty cover with a block =="
open_table
ctl give $EMPTY 1 >/dev/null
ctl give minecraft:stone 1 >/dev/null
ctl wait 3 >/dev/null
place_one $EMPTY 100
place_one minecraft:stone 101
expect_result $COVER 1 "fill empty cover + stone"
take_result 0
ctl wait 3 >/dev/null
[ "$(slot_where $EMPTY)" = "" ] || fail "the empty cover was not consumed by the fill"
[ "$(slot_where minecraft:stone)" = "" ] || fail "the block was not consumed by the fill"
close_table
ctl select 1 >/dev/null; ctl wait 2 >/dev/null
[ "$(count $COVER)" = 1 ] || fail "the fill did not give a cover, got $(count $COVER)"
held_component=$(ctl inventory | jq -r '.held.components // ""')
case "$held_component" in
    *'"mekanismcovers:cover_block":"minecraft:stone"'*) say "  the held cover carries cover_block=minecraft:stone" ;;
    *) fail "the filled cover's component is $held_component, expected cover_block=minecraft:stone" ;;
esac

# The world phases run in survival: a creative hand gives items without losing any (vanilla's
# own rule), so "the cover is consumed" could only ever be asserted where consumption happens.
ctl command "gamemode survival @s" >/dev/null
ctl wait 5 >/dev/null

say "== D. right-clicking a Mekanism cable covers it (state in the cable's saved data) =="
ctl command "execute in minecraft:the_end run setblock $C_X $C_Y $C_Z $CABLE" >/dev/null
ctl wait 5 >/dev/null
[ "$(ctl block $C_X $C_Y $C_Z | jq -r '.block')" = "$CABLE" ] || fail "the parent's cable did not place"
expect_no_cover $C_X $C_Y $C_Z "before the click"
use_block $C_X $C_Y $C_Z "the click"
expect_cover $C_X $C_Y $C_Z minecraft:stone "after the click"
[ "$(count $COVER)" = 0 ] || fail "the held cover was not consumed, $(count $COVER) left"
ctl wait 40 >/dev/null
expect_cover $C_X $C_Y $C_Z minecraft:stone "40 ticks later (the cable's own tick keeps the key)"

say "== E. a second cover replaces the first, which drops =="
open_table
ctl give $EMPTY 1 >/dev/null
ctl give minecraft:glass 1 >/dev/null
ctl wait 3 >/dev/null
place_one $EMPTY 100
place_one minecraft:glass 101
expect_result $COVER 1 "fill empty cover + glass"
take_result 0
close_table
ctl select 1 >/dev/null; ctl wait 2 >/dev/null
cover_before=$(total $COVER)
[ "$cover_before" = 1 ] || fail "expected one cover in hand before the replace, got $cover_before"
use_block $C_X $C_Y $C_Z "the replace"
expect_cover $C_X $C_Y $C_Z minecraft:glass "the replace"
cover_after=$(await_total $COVER "$cover_before")
if [ "$SELFTEST" = 1 ]; then
    # Counterfactual: the run claims the replaced cover did NOT drop, so this must fail.
    [ "$cover_after" = $((cover_before - 1)) ] \
        || fail "SELFTEST: expected the replace to drop nothing ($cover_before -> $cover_after)"
    say "SELFTEST: claiming the replaced cover did not drop"
    fail "SELFTEST: the replace both consumed the held cover and dropped one"
fi
# Differentially: the first attach (D) took the held cover with nothing dropped (1 -> 0), while
# this one took the held cover and put the replaced one back (1 -> 1).
if [ "$cover_after" != "$cover_before" ]; then
    fail "the replace did not drop the cover it replaced ($cover_before -> $cover_after; inventory $(count $COVER), floor $(ground $COVER); items: $(ctl entities 32 item | jq -c '[.entities[] | select(.kind == "item") | .item.item]'))"
fi
say "  the cable wears glass, the held cover is gone and the stone cover came back (1 -> 1)"

say "== F. sneak + right-click with an empty cover strips it =="
# The replaced cover is on the floor a block away and would be picked up into the hotbar slot
# `select 1` picks, so the level's dropped items are cleared first: this phase is about the empty
# cover in hand, and E already proved the drop.
ctl command "clear @s" >/dev/null
ctl command "execute in minecraft:the_end run kill @e[type=item]" >/dev/null
ctl wait 5 >/dev/null
ctl give $EMPTY 1 >/dev/null
ctl wait 3 >/dev/null
select_item $EMPTY
[ "$(ctl inventory | jq -r '.held.item')" = "$EMPTY" ] \
    || fail "the empty cover is not the held item ($(ctl inventory | jq -c '.held'))"
stripped_before=$(total $COVER)
ctl command "execute in minecraft:the_end run tp @s $((C_X)).5 $C_Y $((C_Z + 1)).5" >/dev/null
ctl wait 3 >/dev/null
ctl key shift down >/dev/null; ctl wait 3 >/dev/null
ctl interact $C_X $C_Y $C_Z >/dev/null || say "  interact answered $?"
ctl wait 5 >/dev/null
ctl key shift up >/dev/null; ctl wait 3 >/dev/null
expect_no_cover $C_X $C_Y $C_Z "after the sneak strip"
stripped_after=$(await_total $COVER $((stripped_before + 1)))
[ "$stripped_after" = $((stripped_before + 1)) ] \
    || fail "the stripped glass cover did not drop ($stripped_before -> $stripped_after)"
[ "$(count $EMPTY)" = 1 ] || fail "the empty cover was consumed by the strip ($(count $EMPTY) left)"
say "  the cable is bare again and the glass cover dropped"

say "== G. a non-transmitter is never covered and nothing is consumed =="
open_table
ctl command "clear @s" >/dev/null
ctl give $EMPTY 1 >/dev/null
ctl give minecraft:stone 1 >/dev/null
ctl wait 3 >/dev/null
place_one $EMPTY 100
place_one minecraft:stone 101
take_result 0
close_table
ctl select 1 >/dev/null; ctl wait 2 >/dev/null
before=$(count $COVER)
use_block $X_X $C_Y $X_Z "the stone block"
[ "$(count $COVER)" = "$before" ] || fail "a click on a stone block consumed the cover"
[ "$(ctl block $X_X $C_Y $X_Z | jq -r '.block')" = "minecraft:stone" ] || fail "the stone block changed"
say "  a stone block is not a transmitter: the cover stays in hand"

say "== H. a block that is not a full cube is refused when it is put on =="
open_table
ctl command "clear @s" >/dev/null
ctl give $EMPTY 1 >/dev/null
ctl give minecraft:torch 1 >/dev/null
ctl wait 3 >/dev/null
place_one $EMPTY 100
place_one minecraft:torch 101
expect_result $COVER 1 "fill empty cover + torch (the recipe takes any block item)"
take_result 0
close_table
ctl select 1 >/dev/null; ctl wait 2 >/dev/null
refused_before=$(count $COVER)
use_block $C_X $C_Y $C_Z "the torch cover"
[ "$(count $COVER)" = "$refused_before" ] || fail "the torch cover was consumed although it was refused"
expect_no_cover $C_X $C_Y $C_Z "after the refused torch cover"
say "  the torch cover is refused and stays in hand"

say "== I. breaking a covered cable drops the cover and the cable =="
open_table
ctl command "clear @s" >/dev/null
ctl give $EMPTY 1 >/dev/null
ctl give minecraft:stone 1 >/dev/null
ctl wait 3 >/dev/null
place_one $EMPTY 100
place_one minecraft:stone 101
take_result 0
close_table
ctl select 1 >/dev/null; ctl wait 2 >/dev/null
use_block $C_X $C_Y $C_Z "before the break"
expect_cover $C_X $C_Y $C_Z minecraft:stone "before the break"
covers_before=$(total $COVER)
cables_before=$(total $CABLE)
ctl give minecraft:diamond_pickaxe 1 >/dev/null
ctl wait 3 >/dev/null
ctl select diamond_pickaxe >/dev/null || say "  select answered $?"
ctl wait 3 >/dev/null
ctl break $C_X $C_Y $C_Z >/dev/null || say "  break answered $?"
ctl wait 10 >/dev/null
[ "$(ctl block $C_X $C_Y $C_Z | jq -r '.block')" = "minecraft:air" ] || fail "the cable did not break"
covers_after=$(total $COVER)
cables_after=$(total $CABLE)
[ "$covers_after" = $((covers_before + 1)) ] \
    || fail "the broken cable did not drop its cover ($covers_before -> $covers_after)"
[ "$cables_after" = $((cables_before + 1)) ] \
    || fail "the broken cable did not drop itself ($cables_before -> $cables_after)"
say "  the cover and the cable both dropped"

say "== J. the special recipe strips a filled cover and gives the block back =="
open_table
ctl give $EMPTY 1 >/dev/null
ctl give minecraft:stone 1 >/dev/null
ctl wait 3 >/dev/null
place_one $EMPTY 100
place_one minecraft:stone 101
expect_result $COVER 1 "fill, for the strip"
take_result 0
ctl wait 3 >/dev/null
[ "$(slot_where minecraft:stone)" = "" ] || fail "the block was not consumed by the fill"
place_one $COVER 100
expect_result $EMPTY 1 "strip a filled cover"
take_result 0
ctl wait 3 >/dev/null
# The block the cover wore comes back as the recipe's remainder, in the cell the cover left.
[ "$(slot_where minecraft:stone)" != "" ] || fail "the stripped cover did not give its block back"
say "  the strip returned an empty cover and the block it wore"
close_table

say "== K. a filled shulker box fills nothing, and nothing is consumed =="
# The recipe keeps only a block id, so a stack whose item carries state (a shulker box's contents)
# would be handed back empty after the strip. It must produce no result and consume nothing.
open_table
ctl command "item replace entity @s hotbar.1 with minecraft:shulker_box[minecraft:container=[{slot:0b,item:{id:\"minecraft:diamond\",count:1}}]] 1" >/dev/null
ctl give $EMPTY 1 >/dev/null
ctl wait 3 >/dev/null
place_one $EMPTY 100
place_one minecraft:shulker_box 101
shulker_in=$(stack_json minecraft:shulker_box)
case "$shulker_in" in
    *container*) say "  the shulker box in the grid carries its contents: $shulker_in" ;;
    *) fail "the shulker box in the grid lost its contents before the craft: $shulker_in" ;;
esac
expect_no_result "fill empty cover + filled shulker box"
if [ "$SELFTEST" = refusal ]; then
    # Counterfactual: claim the filled shulker box DID fill the cover, so this leg must fail.
    [ "$(slot_item $RESULT)" = "$COVER" ] \
        || fail "SELFTEST: expected the filled shulker box to fill a cover, and the recipe refused it"
    say "SELFTEST: claiming the filled shulker box filled a cover"
fi
ctl click-slot $RESULT >/dev/null; ctl wait 2 >/dev/null
[ -n "$(slot_where $EMPTY)" ] || fail "the empty cover was consumed by the refused fill"
[ -n "$(slot_where minecraft:shulker_box)" ] || fail "the filled shulker box was consumed by the refused fill"
shulker_after=$(stack_json minecraft:shulker_box)
case "$shulker_after" in
    *container*) say "  nothing was consumed and the shulker box still carries its contents" ;;
    *) fail "the refused fill emptied the shulker box: $shulker_after" ;;
esac
close_table

say "== L. a named block is refused the same way, and a plain one still fills =="
open_table
ctl command "item replace entity @s hotbar.1 with minecraft:stone[minecraft:custom_name='{\"text\":\"Named\"}'] 1" >/dev/null
ctl give $EMPTY 1 >/dev/null
ctl wait 3 >/dev/null
place_one $EMPTY 100
place_one minecraft:stone 101
named_in=$(stack_json minecraft:stone)
case "$named_in" in
    *custom_name*) say "  the block in the grid is named: $named_in" ;;
    *) fail "the named stone lost its component before the craft: $named_in" ;;
esac
expect_no_result "fill empty cover + named stone"
ctl click-slot $RESULT >/dev/null; ctl wait 2 >/dev/null
[ -n "$(slot_where $EMPTY)" ] || fail "the empty cover was consumed by the refused fill"
[ -n "$(slot_where minecraft:stone)" ] || fail "the named stone was consumed by the refused fill"
say "  the named stone is untouched"
close_table
# Differential in the same table: the identical gesture with a plain stone fills, so "no result"
# is the stack's property and not a broken table.
open_table
ctl give $EMPTY 1 >/dev/null
ctl give minecraft:stone 2 >/dev/null
ctl wait 3 >/dev/null
place_one $EMPTY 100
place_one minecraft:stone 101
expect_result $COVER 1 "fill empty cover + plain stone (same table)"
take_result 0
ctl wait 3 >/dev/null
close_table
ctl select 1 >/dev/null; ctl wait 2 >/dev/null
[ "$(count $COVER)" = 1 ] || fail "the plain fill did not give a cover, got $(count $COVER)"
[ "$(count minecraft:stone)" = 1 ] || fail "the plain fill did not consume exactly one stone, got $(count minecraft:stone) left"
say "  the plain stone filled a cover and exactly one stone was consumed"

say "== M. a filled shulker box clicked on a cable applies no cover =="
ctl command "clear @s" >/dev/null
ctl command "execute in minecraft:the_end run setblock $T_X $C_Y $T_Z $CABLE" >/dev/null
ctl wait 5 >/dev/null
[ "$(ctl block $T_X $C_Y $T_Z | jq -r '.block')" = "$CABLE" ] || fail "the second cable did not place"
ctl command "item replace entity @s hotbar.0 with minecraft:shulker_box[minecraft:container=[{slot:0b,item:{id:\"minecraft:diamond\",count:1}}]] 1" >/dev/null
ctl wait 3 >/dev/null
ctl select 1 >/dev/null; ctl wait 2 >/dev/null
[ "$(ctl inventory | jq -r '.held.item')" = "minecraft:shulker_box" ] \
    || fail "the shulker box is not the held item ($(ctl inventory | jq -c '.held'))"
ctl command "execute in minecraft:the_end run tp @s $((T_X)).5 $C_Y $((T_Z + 1)).5" >/dev/null
ctl wait 3 >/dev/null
ctl key shift down >/dev/null; ctl wait 3 >/dev/null
ctl interact $T_X $C_Y $T_Z >/dev/null || say "  interact answered $?"
ctl wait 5 >/dev/null
ctl key shift up >/dev/null; ctl wait 3 >/dev/null
expect_no_cover $T_X $C_Y $T_Z "after the shulker click"
[ "$(ctl block $T_X $C_Y $T_Z | jq -r '.block')" = "$CABLE" ] || fail "the shulker box was placed over the cable"
[ "$(count minecraft:shulker_box)" = 1 ] || fail "the shulker box was consumed by the click"
say "  no cover was applied and the shulker box stays in hand"
ctl command "clear @s" >/dev/null

say "== N. a filled cover carrying components of its own is refused on the cable =="
# The fill can no longer make such a stack (phases K/L), so the only way to hold one is by hand.
# The click keeps a block id, so a cover renamed in an anvil would lose its name on the strip; it is
# the fill's rule on the other consumption path. Phase D's plain cover still writes minecraft:stone.
ctl command "item replace entity @s hotbar.0 with $COVER[mekanismcovers:cover_block=\"minecraft:stone\",minecraft:custom_name='{\"text\":\"Named\"}'] 1" >/dev/null
ctl wait 3 >/dev/null
ctl select 1 >/dev/null; ctl wait 2 >/dev/null
[ "$(ctl inventory | jq -r '.held.item')" = "$COVER" ] \
    || fail "the named cover is not the held item ($(ctl inventory | jq -c '.held'))"
held=$(ctl inventory | jq -r '.held.components // ""')
case "$held" in
    *mekanismcovers:cover_block*minecraft:stone*) ;;
    *) fail "the held stack is not a stone cover before the click: $held" ;;
esac
case "$held" in
    *custom_name*) say "  the cover in hand is named: $held" ;;
    *) fail "the named cover lost its name before the click: $held" ;;
esac
[ "$(ctl block $T_X $C_Y $T_Z | jq -r '.block')" = "$CABLE" ] \
    || fail "the second cable is gone before the named cover click"
ctl command "execute in minecraft:the_end run tp @s $((T_X)).5 $C_Y $((T_Z + 1)).5" >/dev/null
ctl wait 3 >/dev/null
ctl key shift down >/dev/null; ctl wait 3 >/dev/null
ctl interact $T_X $C_Y $T_Z >/dev/null || say "  interact answered $?"
ctl wait 5 >/dev/null
ctl key shift up >/dev/null; ctl wait 3 >/dev/null
if [ "$SELFTEST" = named ]; then
    # Counterfactual: claim the named cover DID cover the cable, so this leg must fail.
    expect_cover $T_X $C_Y $T_Z minecraft:stone "SELFTEST: the named cover"
    say "SELFTEST: claiming the named cover covered the cable"
    fail "SELFTEST: the named cover covered the cable"
fi
expect_no_cover $T_X $C_Y $T_Z "after the named cover click"
[ "$(count $COVER)" = 1 ] || fail "the named cover was consumed by the refused click, $(count $COVER) left"
[ "$(ctl block $T_X $C_Y $T_Z | jq -r '.block')" = "$CABLE" ] || fail "the named cover was placed over the cable"
say "  the named cover is refused and stays in hand, while phase D's plain cover wrote minecraft:stone"
ctl command "clear @s" >/dev/null

say "PASS: covers, both recipes, attach, replace, strip, the break drop, the attach refusals, the fill refusals and the named-cover refusal"
stop_game

# ================================================================ control
if [ "$CONTROL" = 1 ]; then
    say "== control: the same Nightly without either package =="
    if [ -z "$CONTROL_GAME" ] || [ ! -x "$CONTROL_GAME" ]; then
        say "SKIP: no CONTROL_GAME; the control leg needs the plain build"
    else
        launch "$CONTROL_WORLD" "$SCRATCH/control" "$CONTROL_GAME" || fail "the control game did not launch"
        arena
        if [ "$NEGATIVE" = 1 ]; then
            # The control's own counterfactual: claim the plain build DOES know the item, which it
            # does not, so this leg must fail — the control assertion is not vacuous.
            [ "$(count $EMPTY)" -ge 1 ] \
                || fail "NEGATIVE: the plain build does not know $EMPTY, and this leg asserts it does"
            say "NEGATIVE: the plain build knows $EMPTY"
        fi
        got=$(reply "give @s $EMPTY 1")
        case "$got" in
            *Unknown*|*unknown*|*"not exist"*) say "  CONTROL: $EMPTY is unknown on the plain build: $got" ;;
            *) fail "CONTROL: the plain build knows $EMPTY: $got" ;;
        esac
        [ "$(count $EMPTY)" = 0 ] || fail "CONTROL: the plain build gave an empty cover"
        placed=$(ok_of "execute in minecraft:the_end run setblock $C_X $C_Y $C_Z $CABLE")
        [ "$(ctl block $C_X $C_Y $C_Z | jq -r '.block')" != "$CABLE" ] \
            || fail "CONTROL: the plain build placed the parent's cable"
        data=$(data_all $C_X $C_Y $C_Z)
        case "$data" in
            *mekanismcovers*) fail "CONTROL: the plain build carries a cover key: $data" ;;
            *) say "  CONTROL: no cable and no cover key without the packages" ;;
        esac
        stop_game
    fi
fi

say "PASS: every phase"
if [ "$KEEP" = 0 ]; then rm -rf "$SCRATCH"; else say "log kept at $LOG"; fi
