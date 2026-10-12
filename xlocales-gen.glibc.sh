#!/bin/sh
#
# Compile locales created by xlocales-get-SOURCE.sh.

set -e

usage()
{
    cat <<EOF >&2

Usage: $0 origin input_dir output_dir

On entry, input_dir must contain a subdirectory i18n.ORIGIN.  On
success, output_dir will contain two subdirectories:

output_dir/locale.ORIGIN -- unadorned locale names that hide the system
                            locales of the same name if LOCPATH points here

output_dir/locale@ORIGIN -- has symlinks with @ORIGIN and @glibcX.Y
                            modifiers appened, which can be used in
                            addition to the system locales if LOCPATH
                            points where

EOF
    exit 1
}

if [ $# != 3 ] ; then
    usage
fi

origin="$1"
input_dir="$2"
output_dir="$3"

src_dir="$input_dir/i18n.$origin"
dst_dir="$output_dir/locale.$origin"
dst_mod_dir="$output_dir/locale@$origin"

if [ ! -e "$src_dir/xlocales.supported" ] ; then
    echo "Input directory does not contain i18n.$origin/xlocales.supported" >&2
    exit 1
fi
if [ ! -d "$output_dir" ] ; then
    echo "Output directory $output_dir does not exist" >&2
    exit 1
fi

mkdir -p "$dst_dir"
mkdir -p "$dst_mod_dir"

if which xargs > /dev/null ; then
    processes="$(nproc)"
    while read -r locale locale_src charmap modifiers ; do
        echo "echo \"Compiling $dst_dir/$locale\" ; I18NPATH=$src_dir localedef -f $charmap -i $locale_src $dst_dir/$locale"
    done < "$src_dir/xlocales.supported" | xargs -P $processes -I {} sh -c '{}'
else
    while read -r locale locale_src charmap modifiers ; do
        echo "Compiling $dst_dir/$locale"
        I18NPATH=$src_dir localedef -f $charmap -i $locale_src $dst_dir/$locale
    done < "$src_dir/xlocales.supported"
fi

while read -r locale locale_src charmap modifiers ; do
    for mod in $modifiers ; do
        echo "Creating symlink $dst_mod_dir/$locale@$mod"
        rm -f "$dst_mod_dir/$locale@$mod"
        ln -s "../locale.$origin/$locale" "$dst_mod_dir/$locale@$mod"
    done
done < "$src_dir/xlocales.supported"
