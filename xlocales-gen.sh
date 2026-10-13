#!/bin/sh

set -e

usage()
{
    cat <<EOF >&2

Usage: $0 origin [input_dir output_dir]

If not provided, input_dir and output_dir default to share and lib 
respectively.

On entry, input_dir must contain a subdirectory i18n.ORIGIN.  On
success, output_dir will contain two subdirectories:

output_dir/locale.ORIGIN -- unmodified locale names that hide the system
                            locales of the same name if LOCPATH points here

output_dir/locale@ORIGIN -- symlinks with @ORIGIN and @glibcX.Y
                            modifiers appended, which can be used in
                            addition to the system locales if LOCPATH
                            points where

EOF
    exit 1
}

case "$#" in
	1)
		origin="$1"
		input_dir="share"
		output_dir="lib"
		;;
	3)
		origin="$1"
		input_dir="$2"
		output_dir="$3"
		;;
	*)
		usage
		;;
esac

src_dir="$input_dir/i18n.$origin"
dst_dir="$output_dir/locale.$origin"
dst_mod_dir="$output_dir/locale@$origin"

if [ ! -e "$src_dir/xlocales.supported" ] ; then
    echo "Input directory does not contain i18n.$origin/xlocales.supported" >&2
    exit 1
fi

mkdir -p "$dst_dir"
mkdir -p "$dst_mod_dir"

processes="$(nproc)"
while read -r locale locale_src charmap modifiers ; do
    echo "printf '\r%-79s' '$dst_dir/$locale' ; I18NPATH=$src_dir localedef -f $charmap -i $locale_src $dst_dir/$locale"
done < "$src_dir/xlocales.supported" | xargs -P $processes -I {} sh -c '{}'
printf '\r%-79s\r' ''
while read -r locale locale_src charmap modifiers ; do
    for mod in $modifiers ; do
        rm -f "$dst_mod_dir/$locale@$mod"
        ln -s "../locale.$origin/$locale" "$dst_mod_dir/$locale@$mod"
    done
done < "$src_dir/xlocales.supported"
