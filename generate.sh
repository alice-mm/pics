#! /usr/bin/env bash

# Get pictures from
#   <PICS_SRC_DIR>/*.{jpg,jpeg,JPG,JPEG}
# and descriptions from anotehr directory to generate
# a build directory with a slideshow.

set -e

# Set to an empty string to avoid displaying location information.
declare -r SHOULD_USE_GPS_INFO=1
#declare -r SHOULD_USE_GPS_INFO=''

declare -r PICS_SRC_DIR='pics'
declare -r BUILD_DIR='build'
declare -r PICS_DIR_IN_BUILD="$PICS_SRC_DIR"
declare -r OUT_PICS_DIR="$BUILD_DIR"/pics
declare -r DESCR_DIR='descriptions'
# First “%s”: Latitude. Second: Longitude. Both are in decimal degrees.
declare -r GPS_URL_PATTERN='http://www.openstreetmap.org/?mlat=%s&mlon=%s&zoom=18'

cd "$(readlink -f "$0" | xargs dirname)"


# === Functions ===

function clean_build_dir {
    rm -fr -- "$BUILD_DIR"
    mkdir -p -- "$OUT_PICS_DIR"
}

# $1    Picture. Only its basename will ultimately be used.
# stdout → The description of the picture, if one was provided in DESCR_DIR.
function get_pic_description {
    local file
    
    file="$DESCR_DIR"/"$(basename "$1")".html
    if [ -r "$file" ] && [ -f "$file" ]
    then
        cat -- "$file"
    fi
}

# $1    A JPG picture.
#
# Set gps_url to:   A URL allowing to see where the picture was taken,
#                   or nothing if no valid GPS data can be found.
# Set location to:  A text describing the location,
#                   or nothing if no valid data can be found.
function get_gps_url {
    gps_url=''
    location=''
    
    : "${1:?No picture.}"
    
    local metadata_file
    
    metadata_file=${PICS_SRC_DIR}/$(
        basename "$1" | sed '
            s/\.[^.]*$//
        '
    ).metadata
    
    if [ ! -r "$metadata_file" ]
    then
        printf '%s: Warning: Could not find metadata file: %q\n' \
                "$(basename "$0")" "$metadata_file" >&2
        return 0
    fi
    
    local lat_type
    local lat_raw
    local lon_type
    local lon_raw
    local gps_status
    
    local tag_id
    local x
    local value
    
    # Example:
    #   Exif.Photo.WhiteBalance   Short   1   Auto
    # We ignore two fields via the “x”.
    while read tag_id x x value
    do
        case "$tag_id" in
            Exif.GPSInfo.GPSLatitudeRef)
                lat_type=$value
                ;;
            
            Exif.GPSInfo.GPSLatitude)
                lat_raw=$value
                ;;
            
            Exif.GPSInfo.GPSLongitudeRef)
                lon_type=$value
                ;;
            
            Exif.GPSInfo.GPSLongitude)
                lon_raw=$value
                ;;
            
            Exif.GPSInfo.GPSStatus)
                gps_status=$value
                ;;
            
            Exif.Panasonic.Location|Exif.Panasonic.Country|Exif.Panasonic.State|Exif.Panasonic.City|Exif.Panasonic.Landmark)
                if [ "$value" ] && [ "$value" != '---' ]
                then
                    if [ "$location" ]
                    then
                        location="$value, $location"
                    else
                        location=$value
                    fi
                fi
                ;;
            
            *)
                # Ignored.
                ;;
        esac
    done < "$metadata_file"
    
    # Give up if no useful data.
    if [ -z "$lat_type" ] || [ -z "$lat_raw" ] ||
        [ -z "$lon_type" ] || [ -z "$lon_raw" ] ||
        [ "$gps_status" != 'Measurement in progress' ]
    then
        return 0
    fi
    
    local factor
    
    local d
    local m
    local s
    
    local lat_dd
    local lon_dd
    
    if [ "$lat_type" = 'North' ]
    then
        factor=1
    else
        factor=-1
    fi
    
    # “34deg 59' 55.530"” → “34 59 55.530”
    read d m s < <(
        tr -cd '0-9. ' <<< "$lat_raw"
    )
    lat_dd=$(
        bc -l <<< "$factor * ($d + $m / 60 + $s / 3600)"
    )
    
    if [ "$lon_type" = 'East' ]
    then
        factor=1
    else
        factor=-1
    fi
    
    read d m s < <(
        tr -cd '0-9. ' <<< "$lon_raw"
    )
    lon_dd=$(
        bc -l <<< "$factor * ($d + $m / 60 + $s / 3600)"
    )
    
    if [ "$lat_dd" ] && [ "$lon_dd" ]
    then
        gps_url=$(
            printf "${GPS_URL_PATTERN}" "$lat_dd" "$lon_dd"
        )
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
    
    local gps_url
    local location
    
    if [ "$SHOULD_USE_GPS_INFO" ]
    then
        get_gps_url "$1"
    fi
    
    local res
    
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
    if [ "$gps_url" ]
    then
        test "$res" && res+='  '
        res+="<a class=\"gps-link\" target=\"_blank\" href=\"${gps_url}\">&#x1F310</a>"
    fi+="ISO $isos"
    fi
    if [ "$location" ]
    then
        test "$res" && res+='<br>'
        res+=$location
    fi
    
    printf '%s\n' "$res"
}

# $1    A picture. Note that the LQ equivalent from OUT_PICS_DIR
#       will be used instead: “path/to/foo” → “$OUT_PICS_DIR/foo”.
# stdout → HTML code for a slide for the provided picture.
function gen_slide_html {
    local bname
    local file
    local path_from_index_to_pic
    local text
    
    bname=$(basename "${1:?}")
    file="$OUT_PICS_DIR"/"$bname"
    path_from_index_to_pic="$(basename "$OUT_PICS_DIR")"/"$bname"
    text=$(get_pic_description "$file")
    if [ -z "$text" ]
    then
        printf '%s: Warning: Description empty or missing for: %s\n' \
                "$(basename "$0")" "$file" >&2
    fi
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
