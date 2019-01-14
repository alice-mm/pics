#! /usr/bin/env bash

# Get pictures from
#   <PICS_HQ_SRC_DIR>/*.{jpg,jpeg,JPG,JPEG,RW2}
# and generate a directory with lighter versions,
# applying RawTherapee profiles on the fly.

set -e

declare -r PICS_HQ_SRC_DIR='pics_hq'
declare -r PICS_LQ_OUT_DIR='pics'

# 1 = Best compression: 2x2, 1x1, 1x1 (4:2:0)
# 2 = Balanced:         2x1, 1x1, 1x1 (4:2:2)
# 3 = Best quality:     1x1, 1x1, 1x1 (4:4:4)
declare -r JPG_SUBSAMPLING=2
# 1–100
declare -r JPG_QUALITY=88

# Processing profile file applied after the main ones in order to apply
# resizing and optional other things.
declare -r RESIZING_PROFILE=exporting.pp3

declare -ra RAWCLI=(rawtherapee-cli)

cd "$(readlink -f "$0" | xargs dirname)"


# === Functions ===

# foo/bar.jpg → foo/bar_edit.JPG.out.pp3
#
# $1        Path to a picture.
# stdout →  Path to a corresponding “.out.pp3” RawTherapee file with
#           “_edit” before the original extension and JPG
#           as a new extension.
function get_pic_out_profile {
    local path
    
    path=${1:?No file given.}
    printf '%s_edit.JPG.out.pp3' "${path%.*}"
}


# === Tests ===

function assert {
    if ! "$@"
    then
        printf 'Test failure:%s\n' "$(
            printf ' %q' "$@"
        )" >&2
        exit 1
    fi
}

function test_main {
    local funcs
    local one_func
    
    funcs=(
        test_config
        test_get_pic_out_profile
    )
    
    for one_func in "${funcs[@]}"
    do
        "$one_func"
    done
}

function test_config {
    assert test "$PICS_HQ_SRC_DIR"
    assert test "$PICS_LQ_OUT_DIR"
    assert test "$JPG_SUBSAMPLING"
    assert test "$JPG_QUALITY"
    assert test "$RESIZING_PROFILE"
    assert test "$RAWCLI"
}

function test_get_pic_out_profile {
    assert test "$(get_pic_out_profile foo/bar.jpg)"    = foo/bar_edit.JPG.out.pp3
    assert test "$(get_pic_out_profile foo/bar.jpeg)"   = foo/bar_edit.JPG.out.pp3
    assert test "$(get_pic_out_profile foo/bar.JPG)"    = foo/bar_edit.JPG.out.pp3
    assert test "$(get_pic_out_profile foo/bar.JPEG)"   = foo/bar_edit.JPG.out.pp3
    assert test "$(get_pic_out_profile foo/bar.RW2)"    = foo/bar_edit.JPG.out.pp3
    assert test "$(get_pic_out_profile bar.RW2)"        = bar_edit.JPG.out.pp3
    assert test "$(get_pic_out_profile bar_edit.RW2)"   = bar_edit_edit.JPG.out.pp3
}


# === Main code ===

test_main

mkdir -pv -- "$PICS_LQ_OUT_DIR"/
rm -frv -- "$PICS_LQ_OUT_DIR"/*

for pic in "$PICS_HQ_SRC_DIR"/*.{jpg,jpeg,JPG,JPEG,RW2}
do
    if [ ! -r "$pic" ] || [ ! -f "$pic" ]
    then
        continue
    fi
    
    profile=$(get_pic_out_profile "$pic")
    
    if [ ! -r "$profile" ] || [ ! -f "$profile" ]
    then
        printf 'Missing or unreadable profile “%q” for “%q”.\n' \
                "$profile" "$pic" >&2
        continue
    fi
    
    params=(
        -o "$PICS_LQ_OUT_DIR"/
        
        -p "$profile"
        -p "$RESIZING_PROFILE"
        
        -j"$JPG_QUALITY"
        -js"$JPG_SUBSAMPLING"
        
        -c "$pic"
    )
    
    status=0
    "${RAWCLI[@]}" "${params[@]}" || status=$?
    if [ "$status" -ne 0 ]
    then
        printf 'Conversion failed with status %d.\n' "$status"
        exit "$status"
    fi
done

echo "$(basename "$0"): All done."
