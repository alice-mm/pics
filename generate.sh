#! /usr/bin/env bash

# Get pictures from
#   <PICS_SRC_DIR>/*.{jpg,jpeg,JPG,JPEG}
# and descriptions from anotehr directory to generate
# a build directory with a slideshow.

set -e

declare -r PICS_SRC_DIR='pics'
declare -r BUILD_DIR='build'
declare -r PICS_DIR_IN_BUILD="$PICS_SRC_DIR"
declare -r OUT_PICS_DIR="$BUILD_DIR"/pics
declare -r DESCR_DIR='descriptions'

cd "$(readlink -f "$0" | xargs dirname)"


# === Functions ===

function clean_build_dir {
    rm -fr "$BUILD_DIR"
    mkdir -p "$OUT_PICS_DIR"
}

# $1    Picture. Only its basename will ultimately be used.
# stdout → The description of the picture, if one was provided in DESCR_DIR.
function get_pic_description {
    local file
    
    file="$DESCR_DIR"/"$(basename "$1")".html
    if [ -r "$file" ] && [ -f "$file" ]
    then
        cat "$file"
    fi
}

# $1    A JPG picture.
# stdout → A string containing some EXIF metadata, if available.
function get_metadata_string {
    : ${1:?}
    local date=$( exif -mt 'Date and Time (Original)' "$1" )
    local fnum=$( exif -mt 'F-Number' "$1" )
    local expt=$( exif -mt 'Exposure Time' "$1" )
    local isos=$( exif -mt 'ISO Speed Ratings' "$1" )
    
    local res=''
    
    test "$date" && res+="$date"
    if [ "$fnum" ]
    then
        test "$res" && res+='  '
        res+="$fnum"
    fi
    if [ "$expt" ]
    then
        test "$res" && res+='  '
        res+="$expt"
    fi
    if [ "$isos" ]
    then
        test "$res" && res+='  '
        res+="ISO $isos"
    fi
    
    printf '%s\n' "$res"
}

# $1    A picture. Note that the LQ equivalent from OUT_PICS_DIR
#       will be used instead.
# stdout → HTML code for a slide for the provided picture.
function gen_slide_html {
    local bname
    local file
    local path_from_index_to_pic
    local text
    
    bname="$(basename "${1:?}")"
    file="$OUT_PICS_DIR"/"$bname"
    path_from_index_to_pic="$(basename "$OUT_PICS_DIR")"/"$bname"
    text=$( get_pic_description "$file" )
    meta=$( get_metadata_string "$file" )
    
    if [ "$meta" ]
    then
        # Add metadata before description.
        text='<div class="pic-meta">'"$meta"'</div>'"$text"
    fi
    
    echo '<div class="mySlides fade">'
    printf '    <div class="img-wrapper"><a href="%s"><img src="%s" /></a></div>\n' \
            "$path_from_index_to_pic" "$path_from_index_to_pic"
    if [ "$text" ]
    then
        printf '    <div class="text">%s</div>\n' "$text"
    fi
    echo '</div>'
}

# $1    Number of slides, and hence number of dots.
# stdout → HTML code for the navigation dots.
function gen_dots_html {
    local i
    
    # +1 because we assume there's an introductory slide.
    for ((i = 1;  i <= ${1:?} + 1;  i++))
    do
        printf '<span class="dot" onclick="currentSlide(%d)"></span>\n' "$i"
    done
}


# === Main code ===

nb_pics=0
all_slides_html=''
indent=$(
    yes | head -12 | xargs printf '%.0s '
)

mkdir -pv -- "$BUILD_DIR"/
rm -frv -- "$BUILD_DIR"/*
mkdir -pv -- "$BUILD_DIR"/"$PICS_DIR_IN_BUILD"/

for file in "$PICS_SRC_DIR"/*.{jpg,jpeg,JPG,JPEG}
do
    if [ ! -r "$file" ] || [ ! -f "$file" ]
    then
        continue
    fi
    
    cp -v -- "$file" "$BUILD_DIR"/"$PICS_DIR_IN_BUILD"/
    
    if [ "$all_slides_html" ]
    then
        all_slides_html+=$'\n'
    fi
    
    all_slides_html+=$(
        gen_slide_html "$file" | sed "s/^/${indent}/"
    )
    
    ((nb_pics++)) || true
done

dots_html=$( gen_dots_html "$nb_pics" | sed "s/^/${indent}/" )

awk -v slides="$all_slides_html" -v dots="$dots_html" '
    {
        if(/^[ \t]*<!-- === INSERT SLIDES HERE === -->[ \t]*/) {
            print slides
        } else if(/^[ \t]*<!-- === INSERT DOTS HERE === -->[ \t]*/) {
            print dots
        } else {
            print
        }
    }
' index.html > "$BUILD_DIR"/index.html

echo "$(basename "$0"): All done."
