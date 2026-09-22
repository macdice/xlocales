#!/bin/sh

set -e

work="work"
output="xlocales"

maps="tools/tools/locale/etc/final-maps"

fetch_src()
{
	os_version="$1"
	src_path="$2"

	src_url="https://raw.githubusercontent.com/freebsd/freebsd-src/stable/$os_version/$src_path"
	src_dir="$(dirname "$src_path")"

	work_path="$work/freebsd$os_version"
	dst_dir="$work/freebsd$os_version/$src_dir"
	dst_path="$work/freebsd$os_version/$src_path"

	if [ ! -e "$dst_path" ] ; then
		mkdir -p "$dst_dir"
		printf "$distribution: fetching $src_path...\r"
		curl -f -s -S "$src_url" > "$dst_path.tmp"
		mv "$dst_path.tmp" "$dst_path"
		printf '\033[K'
	fi
}

symlink_modifiers()
{
	distribution="$1"
	cldr_version="$2"
	locale="$3"

	locale_smod="$locale@$distribution"
	locale_vmod="$locale@$cldr_version"
	smod_base_path="$output/$distribution/system-modifier"
	vmod_base_path="$output/$distribution/version-modifier"
	smod_path="$smod_base_path/$locale_smod"
	vmod_path="$vmod_base_path/$locale_vmod"

	mkdir -p "$smod_base_path"
	mkdir -p "$vmod_base_path"
	
	if [ ! -L "$smod_path" ] ; then
		ln -w -s "../bare/$locale" "$smod_path"
	fi

	# only the LC_COLLATE category is available with a CLDR modifier
	# (perhaps all categories should be?)
	if [ -e "$output/$distribution/bare/$locale/LC_COLLATE" ] ; then
	       if [ ! -L "$vmod_path/LC_COLLATE" ] ; then
			mkdir -p "$vmod_path"
			ln -w -s "../../bare/$locale/LC_COLLATE" "$vmod_path/LC_COLLATE"
		fi
	fi
}

symlink_locale_category()
{
	distribution="$1"
	locale="$2"
	category="$3"
	cldr_version="$4"
	from="$5"

	locale_dir="$output/$distribution/bare/$locale"

	if [ ! -e "$locale_dir/$category" ] ; then
		echo "$distribution: $locale/$category -> $from/$category"
		mkdir -p "$locale_dir"
		symlink_modifiers $distribution $cldr_version $locale
		ln -w -s "../$from/$category" "$locale_dir/$category"
	fi
}

build_locale_category()
{
	distribution="$1"
	locale="$2"
	category="$3"
	cldr_version="$4"
	source="$5"
	
	work_dir="$work/$distribution"
	locale_dir="$output/$distribution/bare/$locale"

	if [ ! -e "$locale_dir/$category" ] ; then
		echo "$distribution: $locale/$category $cldr_version"
		mkdir -p "$locale_dir"
		symlink_modifiers "$distribution" "$cldr_version" "$locale"
		os_version="$(echo "$distribution" | sed 's/^freebsd//')"
		codeset="$(echo "$locale" | sed 's/.*\.//;s/@.*//')"
		fetch_src $os_version "$source"
		case "$category" in
			LC_COLLATE) 
				fetch_src $os_version "$maps/map.$codeset"
				localedef -U \
					-i "$work_dir/$source" \
					-V "$cldr_version" \
					-f "$work_dir/$maps/map.$codeset" \
					"$locale_dir"
				symlink_modifiers "$distribution" "$cldr_version" "$locale"
				;;
			LC_CTYPE)
				fetch_src $os_version "$maps/map.$codeset"
				fetch_src $os_version "$maps/widths.txt"
				localedef -U -c \
					-w "$work_dir/$maps/widths.txt" \
					-i "$work_dir/$source" \
					-f "$work_dir/$maps/map.$codeset" \
					"$locale_dir"
			       ;;
			*) 
				grep -v -E '^(#$$|#[ ])' \
					< "$work_dir/$source" \
					> "$locale_dir/$category"
				;;
		esac
	fi
}

build_locales_category()
{
	distribution="$1"
	categorydir="$2"
	category="$3"

	os_version="$(echo "$distribution" | sed 's/^freebsd//')"
	work_path="$work/$distribution"
	makefile="$categorydir/Makefile"

	fetch_src $os_version "$makefile"
	if [ "$category" = "LC_COLLATE" ] ; then
		cldr_version="$(grep '^CLDR_VERSION=' "$work_path/$makefile" | head -1 | sed 's/[^"]*"//;s/"$//')"
	else
		cldr_version=""
	fi

	mkdir -p "$output/$distribution/bare"

	(grep '^SYMPAIRS+=' "$work_path/$makefile" | sed 's/.*=//;s/#.*//') | while read -r symlink_from symlink_to ; do
		if [ ! -L "$work_path/$categorydir/$symlink_to" ] ; then
			fetch_src $os_version "$categorydir/$symlink_from"
			ln -w -s "$symlink_from" "$work_path/$categorydir/$symlink_to"
		fi
	done
	(grep '^LOCALES_MAPPED+=' "$work_path/$makefile" | sed 's/.*=//;s/#.*//') | while read -r map_from locale ; do
		build_locale_category \
			"$distribution" \
			"$locale" \
			"$category" \
			"$cldr_version" \
			"$categorydir/$map_from.src"
	done
	(grep '^SAME+=' "$work_path/$makefile" | sed 's/.*=//;s/#.*//') | while read -r symlink_from symlink_to ; do
		build_locale_category \
			"$distribution" \
			"$symlink_from" \
			"$category" \
			"$cldr_version" \
			"$categorydir/$symlink_from.src"
		symlink_locale_category \
			"$distribution" \
			"$symlink_to" \
			"$category" \
			"$cldr_version" \
			"$symlink_from"
	done
	for locale in $(grep '^LOCALES+=' "$work_path/$makefile" | sed 's/.*=//') ; do
		build_locale_category \
			"$distribution" \
			"$locale" \
			"$category" \
			"$cldr_version" \
			"$categorydir/$locale.src"
	done
}

build_locales()
{
	distribution="$1"

	os_version="$(echo "$distribution" | sed 's/^freebsd//')"

	build_locales_category $1 "share/colldef" "LC_COLLATE"
	build_locales_category $1 "share/ctypedef" "LC_CTYPE"
	build_locales_category $1 "share/monetdef" "LC_MONETARY"
	build_locales_category $1 "share/msgdef" "LC_MESSAGE"
	build_locales_category $1 "share/numericdef" "LC_NUMERIC"
	build_locales_category $1 "share/timedef" "LC_TIME"

	if [ "$os_version" -ge "14" ] ; then
		build_locales_category $1 "share/colldef_unicode" "LC_COLLATE"
		build_locales_category $1 "share/monetdef_unicode" "LC_MONETARY"
		build_locales_category $1 "share/msgdef_unicode" "LC_MESSAGE"
		build_locales_category $1 "share/numericdef_unicode" "LC_NUMERIC"
	fi
}

case $1 in
	freebsd*)
		build_locales "$1"
		;;
	*)
		echo "Usage: $0 freebsd13 (or higher...)"
		exit 1
		;;
esac
