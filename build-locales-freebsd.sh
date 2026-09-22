#!/bin/sh

set -e

work="work"
output="xlocales"

maps="tools/tools/locale/etc/final-maps"

fetch_src()
{
	system="$1"
	src_path="$2"

	rel="$(echo "$system" | sed 's/^freebsd//')"
	src_url="https://raw.githubusercontent.com/freebsd/freebsd-src/system/$rel.0/$src_path"
	src_dir="$(dirname "$src_path")"

	work_path="$work/freebsd$system"
	dst_dir="$work/freebsd$os_version/$src_dir"
	dst_path="$work/freebsd$os_version/$src_path"

	if [ ! -e "$dst_path" ] ; then
		mkdir -p "$dst_dir"
		printf "$system: fetching $src_path..."
		if [ "$verbose" = "1" ] ; then echo ; fi
		curl -f -s -S "$src_url" > "$dst_path.tmp"
		mv "$dst_path.tmp" "$dst_path"
		if [ "$verbose" != "1" ] ; then printf '\r\033[K' ; fi
	fi
}

symlink_modifiers()
{
	system="$1"
	cldr_version="$2"
	locale="$3"

	locale_smod="$locale@$system"
	locale_vmod="$locale@$cldr_version"
	smod_base_path="$output/$system/system-modifier"
	vmod_base_path="$output/$system/version-modifier"
	smod_path="$smod_base_path/$locale_smod"
	vmod_path="$vmod_base_path/$locale_vmod"

	mkdir -p "$smod_base_path"
	mkdir -p "$vmod_base_path"
	
	if [ ! -L "$smod_path" ] ; then
		ln -w -s "../bare/$locale" "$smod_path"
	fi

	# only the LC_COLLATE category is available with a CLDR modifier
	# (perhaps all categories should be?)
	if [ -e "$output/$system/bare/$locale/LC_COLLATE" ] ; then
	       if [ ! -L "$vmod_path/LC_COLLATE" ] ; then
			mkdir -p "$vmod_path"
			ln -w -s "../../bare/$locale/LC_COLLATE" "$vmod_path/LC_COLLATE"
		fi
	fi
}

symlink_locale_category()
{
	system="$1"
	locale="$2"
	category="$3"
	cldr_version="$4"
	from="$5"

	locale_dir="$output/$system/bare/$locale"

	if [ ! -e "$locale_dir/$category" ] ; then
		#echo "$system: $locale/$category -> $from/$category"
		mkdir -p "$locale_dir"
		symlink_modifiers $system $cldr_version $locale
		ln -w -s "../$from/$category" "$locale_dir/$category"
	fi
}

build_locale_category()
{
	system="$1"
	locale="$2"
	category="$3"
	cldr_version="$4"
	source="$5"
	
	work_dir="$work/$system"
	locale_dir="$output/$system/bare/$locale"

	if [ ! -e "$locale_dir/$category" ] ; then
		#echo "$system: $locale/$category $cldr_version"
		mkdir -p "$locale_dir"
		symlink_modifiers "$system" "$cldr_version" "$locale"
		rel="$(echo "$system" | sed 's/^freebsd//')"
		codeset="$(echo "$locale" | sed 's/.*\.//;s/@.*//')"
		fetch_src $system "$source"
		fetch_src $system "$maps/map.$codeset"
		fetch_src $system "$maps/widths.txt"
		if [ -n "$cldr_version" ] ; then
			cldr_version_info=" (CLDR=$cldr_version)"
		else
			cldr_version_info=""
		fi
		printf "$system: compiling $locale/$category$cldr_version_info..."
		if [ "$verbose" = "1" ] ; then echo ; fi
		case "$category" in
			LC_COLLATE) 
				localedef -U \
					-i "$work_dir/$source" \
					-V "$cldr_version" \
					-f "$work_dir/$maps/map.$codeset" \
					"$locale_dir"
				symlink_modifiers "$system" "$cldr_version" "$locale"
				;;
			LC_CTYPE)
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
		if [ "$verbose" != "1" ] ; then printf '\r\033[K' ; fi
	fi
}

build_locales_category()
{
	system="$1"
	categorydir="$2"
	category="$3"

	rel="$(echo "$system" | sed 's/^freebsd//')"
	work_path="$work/$system"
	makefile="$categorydir/Makefile"

	fetch_src $system "$makefile"
	if [ "$category" = "LC_COLLATE" ] ; then
		cldr_version="$(grep '^CLDR_VERSION=' "$work_path/$makefile" | head -1 | sed 's/[^"]*"//;s/"$//')"
	else
		cldr_version=""
	fi

	mkdir -p "$output/$system/bare"

	(grep '^SYMPAIRS+=' "$work_path/$makefile" | sed 's/.*=//;s/#.*//') | while read -r symlink_from symlink_to ; do
		if [ ! -L "$work_path/$categorydir/$symlink_to" ] ; then
			fetch_src $system "$categorydir/$symlink_from"
			ln -w -s "$symlink_from" "$work_path/$categorydir/$symlink_to"
		fi
	done
	(grep '^LOCALES_MAPPED+=' "$work_path/$makefile" | sed 's/.*=//;s/#.*//') | while read -r map_from locale ; do
		build_locale_category \
			"$system" \
			"$locale" \
			"$category" \
			"$cldr_version" \
			"$categorydir/$map_from.src"
	done
	(grep '^SAME+=' "$work_path/$makefile" | sed 's/.*=//;s/#.*//') | while read -r symlink_from symlink_to ; do
		build_locale_category \
			"$system" \
			"$symlink_from" \
			"$category" \
			"$cldr_version" \
			"$categorydir/$symlink_from.src"
		symlink_locale_category \
			"$system" \
			"$symlink_to" \
			"$category" \
			"$cldr_version" \
			"$symlink_from"
	done
	for locale in $(grep '^LOCALES+=' "$work_path/$makefile" | sed 's/.*=//') ; do
		build_locale_category \
			"$system" \
			"$locale" \
			"$category" \
			"$cldr_version" \
			"$categorydir/$locale.src"
	done
}

build_locales()
{
	system="$1"

	rel="$(echo "$system" | sed 's/^freebsd//')"

	build_locales_category $1 "share/colldef" "LC_COLLATE"
	build_locales_category $1 "share/ctypedef" "LC_CTYPE"
	build_locales_category $1 "share/monetdef" "LC_MONETARY"
	build_locales_category $1 "share/msgdef" "LC_MESSAGE"
	build_locales_category $1 "share/numericdef" "LC_NUMERIC"
	build_locales_category $1 "share/timedef" "LC_TIME"

	rel_major="$(echo $rel | sed 's/\..*//')"
	if [ "$rel_major" -ge "14" ] ; then
		build_locales_category $1 "share/colldef_unicode" "LC_COLLATE"
		build_locales_category $1 "share/monetdef_unicode" "LC_MONETARY"
		build_locales_category $1 "share/msgdef_unicode" "LC_MESSAGE"
		build_locales_category $1 "share/numericdef_unicode" "LC_NUMERIC"
	fi

	echo "$output/$system"
}

verbose=0
if [ "$1" = "--verbose" ] ; then
	verbose=1
	shift
fi

case "$1" in
	--all|--list)
		my_rel="$(uname -v | sed 's|^[^0-9]*||;s|-.*$||')"
		my_rel_major="$(echo $my_rel | sed 's|\..*||')"
		my_rel_minor="$(echo $my_rel | sed 's|^[^.]*\.||')"

		echo XXX $my_rel_major $my_rel_minor
		for tag in $(git ls-remote \
				--tags "https://github.com/freebsd/freebsd-src" | \
				awk '{print $2}' | \
				sed 's|refs/tags/||' | \
				grep -v '\^{}' | \
				grep -v '_cvs$' | \
				grep '^release/[0-9][0-9]*\.[0-9][0-9]*\.' | \
				sort -Vr) ; do
			rel="$(echo $tag | sed 's|^release/\([0-9]*\)\.\([0-9]*\)\..*$|\1.\2|')"
			rel_major="$(echo $rel | sed 's|\..*||')"
			rel_minor="$(echo $rel | sed 's|^[^.]*\.||')"

			# We want the highest patch number for each major
			# release (the list is reverse-version-sorted, so skip
			# the rest for the same rel)
			if [ "$rel" = "$last_rel" ] ; then
				continue
			fi
			last_rel="$rel"

			# Don't look at anything older than 13, older releases
			# didn't carry CLDR versions.
			if [ "$rel_major" -lt 13 ] ; then
				continue
			fi
			# Don't look at anything newer than the host localedef.
			if [ "$rel_major" -gt "$my_rel_major" ] ; then
				continue
			elif [ "$rel_major" -eq "$my_rel_major" -a \
				"$rel_minor" -gt "$my_rel_minor" ] ; then
				continue
			fi

			if [ "$1" = "--list" ] ; then
				echo "freebsd$rel $tag"
			else
				build_locales "freebsd$rel" "$tag"
			fi
		done
		;;
	--tag)
		build_locales "$2" "$3"
		;;
	*)
		echo "Usage: $0 [--verbose] --tag release/13.0.0 freebsd13.0"
		echo "Usage: $0 [--verbose] --all"
		echo "Usage: $0 [--verbose] --list"
		exit 1
		;;
esac
