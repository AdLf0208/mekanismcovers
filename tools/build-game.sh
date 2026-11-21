#!/usr/bin/env bash
# Build one game that carries both this package and its parent (`mekanism`), and print the
# exports `tools/e2e.sh` reads.
#
# Why this exists: `ports/tools/launcher-game.sh build <mod>` builds **one** package (it passes a
# single port folder to `horizon-launcher native-build`, whose contract is "a mod folder, or a
# folder of them"). A cover is worn by a transmitter, and the transmitter's block entity is
# declared by the parent port's code, so the leg needs both packages compiled into the same game;
# `--dev-mod` cannot supply it because it loads content only, and the cable's block entity is code.
# The pinned launcher already supports a folder of mods, so this script stages the two packages in
# one folder, builds them together (the log says `Compiling mekanism (1 of 2)` /
# `Compiling mekanismcovers (2 of 2)`), and exports the version exactly as `launcher-game.sh`
# does. The **control** game stays `launcher-game.sh`'s, which is the same Nightly with neither
# package.
#
# Run inside a build slot, from the campaign root:
#   BUILD_LOCAL=1 ports/tools/build-slot.sh run --job W1-mekanismcovers --port ports/mekanismcovers \
#       --step build -- bash ports/mekanismcovers/tools/build-game.sh
#
# `--env` prints only what an existing build exports (no compile).
set -uo pipefail

CAMPAIGN=$(cd "$(dirname "$0")/../../.." && pwd)
PORT=$CAMPAIGN/ports/mekanismcovers
PARENT=$CAMPAIGN/ports/mekanism
TOOLS=$CAMPAIGN/ports/tools
ROOT=$CAMPAIGN/ports
LAUNCHER_DIR=$ROOT/_shared/bin/launcher-0.2.92
SDK_PIN=0a875da91dbb0fdcb7ba8c42c11341aa229af51a
MIXINS_PIN=e59da9094f0c2fdda6c627fe9eff22dec6a906f0
PIN=${SDK_PIN:0:7}
E2E_ROOT=${HORIZON_E2E_ROOT:-$HOME/.cache/horizon-e2e}
DATA=$E2E_ROOT/root/data
CONFIG=$E2E_ROOT/root/config
HOME_DIR=$E2E_ROOT/root/home
VERSIONS=$DATA/horizon-launcher/versions
INSTANCE=${HORIZON_E2E_INSTANCE:-e2e}
SET=$E2E_ROOT/$PIN/mekanismcovers-set
OUT=$E2E_ROOT/$PIN/mekanismcovers
RES_VERSION=26.3

say() { printf '%s: %s\n' "${0##*/}" "$*" >&2; }
die() { printf '%s: %s\n' "${0##*/}" "$*" >&2; exit "${2:-1}"; }

launcher() {
    env XDG_DATA_HOME="$DATA" XDG_CONFIG_HOME="$CONFIG" HOME="$HOME_DIR" \
        "$LAUNCHER_DIR/horizon-launcher" "$@"
}

export_version() { # tag outdir
    local tag=$1 out=$2 f
    rm -rf "$out"
    mkdir -p "$out" || die "cannot create $out" 3
    for f in "$VERSIONS/$tag"/horizon-client "$VERSIONS/$tag"/horizon-ctl \
             "$VERSIONS/$tag"/lib*.so "$VERSIONS/$tag"/horizon-wasm-std.wasm \
             "$VERSIONS/$tag"/research-lock.json "$VERSIONS/$tag"/PLAY.txt; do
        [ -e "$f" ] || continue
        ln -f "$f" "$out/" 2>/dev/null || cp -a "$f" "$out/"
    done
    [ -d "$VERSIONS/$tag/horizon-native-mods" ] && cp -a "$VERSIONS/$tag/horizon-native-mods" "$out/"
    [ -f "$VERSIONS/$tag/native-mods.json" ] && cp -a "$VERSIONS/$tag/native-mods.json" "$out/"
    if ldd "$out/horizon-client" 2>/dev/null | grep -q 'not found'; then
        die "the exported game in $out misses a library" 9
    fi
}

env_block() { # mod game ctl control-game resources
    printf 'export GAME=%q\n' "$2"
    printf 'export CTL=%q\n' "$3"
    printf 'export CONTROL_GAME=%q\n' "$4"
    printf 'export RES=%q\n' "$5"
    printf 'export HORIZON_RES=%q\n' "$5"
}

# The newest installed version whose `horizon-native-mods/` carries both packages.
pair_tag() {
    local tag newest="" newest_t=0 t
    for tag in "$VERSIONS"/native-*; do
        [ -d "$tag/horizon-native-mods/mekanism" ] || continue
        [ -d "$tag/horizon-native-mods/mekanismcovers" ] || continue
        t=$(stat -c %Y "$tag")
        if [ "$t" -gt "$newest_t" ]; then newest=${tag##*/}; newest_t=$t; fi
    done
    [ -n "$newest" ] && { echo "$newest"; return 0; }
    return 1
}

check_pins() { # dir
    local out game horizon mixins
    out=$(python3 - "$1/horizon-mod.toml" <<'PY'
import sys, tomllib
manifest = tomllib.load(open(sys.argv[1], "rb"))
native = manifest.get("native", {})
print(native.get("game", ""), native.get("horizon", ""), native.get("mixins", ""))
PY
) || die "cannot read $1/horizon-mod.toml" 2
    read -r game horizon mixins <<<"$out"
    [ "$game" = "$RES_VERSION" ] || die "$1 targets game $game" 5
    [ "$horizon" = "$SDK_PIN" ] || die "$1 pins horizon $horizon, the launcher's Nightly is $SDK_PIN" 5
    [ "$mixins" = "$MIXINS_PIN" ] || die "$1 pins mixins $mixins, expected $MIXINS_PIN" 5
}

print_env() { # tag
    local tag=$1
    [ -x "$OUT/horizon-client" ] || export_version "$tag" "$OUT"
    local control_res=$VERSIONS/$tag/.local/horizon-client/$RES_VERSION
    [ -d "$control_res" ] || die "no prepared resources at $control_res" 6
    env_block mekanismcovers "$OUT/horizon-client" "$OUT/horizon-ctl" \
        "$E2E_ROOT/$PIN/control/horizon-client" "$control_res"
}

if [ "${1:-}" = "--env" ]; then
    tag=$(pair_tag) || die "no paired game installed; run this script without --env first" 7
    print_env "$tag"
    exit 0
fi

check_pins "$PORT"
check_pins "$PARENT"
[ -d "$E2E_ROOT/root/data/horizon-launcher/versions" ] \
    || die "the launcher has no versions yet; run ports/tools/launcher-game.sh ensure" 4

# One folder per package, sources only: the launcher fetches each package's SDK itself.
mkdir -p "$SET" || die "cannot create $SET" 3
for pair in "mekanismcovers:$PORT" "mekanism:$PARENT"; do
    name=${pair%%:*}
    dir=${pair#*:}
    rsync -a --delete --exclude target --exclude .horizon --exclude '*.hmod' "$dir/" "$SET/$name/" \
        || die "cannot stage $name" 3
done

say "building mekanism + mekanismcovers into one game"
launcher native-build "$SET" --instance "$INSTANCE" --trust-native-code --json >&2 \
    || die "native-build failed for the pair" 10
tag=$(pair_tag) || die "native-build reported success but no version carries both packages" 10
say "built $tag"
export_version "$tag" "$OUT"
# The control game: the same Nightly with neither package, as launcher-game.sh exports it.
[ -x "$E2E_ROOT/$PIN/control/horizon-client" ] \
    || say "no control game at $E2E_ROOT/$PIN/control; CONTROL=1 will skip the control leg"
print_env "$tag"
