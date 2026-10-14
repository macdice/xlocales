#!/bin/sh

set -e

case "$#" in
	1)
		origin="$1"
		input_dir="."
		output_dir="."
		;;
	3)
		origin="$1"
		input_dir="$2"
		output_dir="$3"
		;;
	*)
		echo "Usage: $0 ORIGIN [input_dir output_dir]" >&2
		exit 1
		;;
esac

src_dir="$input_dir/i18n.$origin"
dst_dir="$output_dir/locale.$origin"
dst_mod_dir="$output_dir/locale@$origin"

mkdir -p "$dst_dir"
mkdir -p "$dst_mod_dir"

count="$(wc -l < "$src_dir/locales.list")"
n=1
while read -r locale locale_src charmap modifiers ; do
    if [ ! -d "$dst_dir/$locale" ] ; then
        printf "%s\0%s\0%s\0%s\0%s\0" "[$n/$count] $locale@$origin" "$src_dir" "$charmap" "$locale_src" "$dst_dir/$locale"
    fi
    n=$((n + 1))
done < "$src_dir/locales.list" | xargs -0 -n 5 -P $(nproc) sh -c 'printf "\r%-79s" "$1" ; I18NPATH="$2" localedef -f "$3" -i "$4" "$5"' _
while read -r locale locale_src charmap modifiers ; do
    for mod in $modifiers ; do
        if [ ! -L "$dst_mod_dir/$locale@$mod" ] ; then
            ln -s "../locale.$origin/$locale" "$dst_mod_dir/$locale@$mod"
        fi
    done
done < "$src_dir/locales.list"
printf '\r%-79s\r' ''
