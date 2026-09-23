#!/bin/sh
#
# Compile historical FreeBSD locale data with the host localedef.

set -e


maps="tools/tools/locale/etc/final-maps"

fetch_src()
{
    origin="$1"
    tag="$2"
    src_path="$3"

    rel="$(echo "$origin" | sed 's/^freebsd//')"
    src_url="https://raw.githubusercontent.com/freebsd/freebsd-src/$tag/$src_path"
    src_dir="$(dirname "$src_path")"

    work_path="$work/$origin"
    dst_dir="$work/$origin/$src_dir"
    dst_path="$work/$origin/$src_path"

    if [ ! -e "$dst_path" ] ; then
        mkdir -p "$dst_dir"
        if [ "$verbose" = "1" ] ; then
            echo "$output/$origin: fetching $src_url..."
        else
            printf "$output/$origin: fetching $src_path..."
        fi
        curl -f -s -S "$src_url" > "$dst_path.tmp"
        mv "$dst_path.tmp" "$dst_path"
        if [ "$verbose" != "1" ] ; then printf '\r\033[K' ; fi
    fi
}

symlink_modifiers()
{
    origin="$1"
    cldr_version="$2"
    locale="$3"

    locale_origin="$locale@$origin"
    locale_version="$locale@$cldr_version"
    locale_origin_symlink="$output/$origin/origin-mod/$locale_origin"
    locale_version_dir="$output/$origin/version-mod/$locale_version"

    if [ ! -L "$locale_origin_symlink" ] ; then
        mkdir -p "$(dirname "$locale_origin_symlink")"
        ln -w -s "../plain/$locale" "$locale_origin_symlink"
    fi

    if [ -n "$cldr_version" ] ; then 
        if [ -e "$output/$origin/plain/$locale/LC_COLLATE" ] ; then
               if [ ! -L "$locale_version_dir/LC_COLLATE" ] ; then
                mkdir -p "$locale_version_dir"
                ln -w -s "../../plain/$locale/LC_COLLATE" "$locale_version_dir/LC_COLLATE"
            fi
        fi
    fi
}

symlink_locale_category()
{
    origin="$1"
    locale="$2"
    category="$3"
    cldr_version="$4"
    from="$5"

    locale_dir="$output/$origin/plain/$locale"

    if [ ! -e "$locale_dir/$category" ] ; then
        #echo "$origin: $locale/$category -> $from/$category"
        mkdir -p "$locale_dir"
        symlink_modifiers $origin $cldr_version $locale
        ln -w -s "../$from/$category" "$locale_dir/$category"
    fi
}

build_locale_category()
{
    origin="$1"
    tag="$2"
    locale="$3"
    category="$4"
    cldr_version="$5"
    source="$6"
    
    work_dir="$work/$origin"
    locale_dir="$output/$origin/plain/$locale"

    if [ ! -e "$locale_dir/$category" ] ; then
        #echo "$origin: $locale/$category $cldr_version"
        mkdir -p "$locale_dir"
        symlink_modifiers "$origin" "$cldr_version" "$locale"
        rel="$(echo "$origin" | sed 's/^freebsd//')"
        codeset="$(echo "$locale" | sed 's/.*\.//;s/@.*//')"
        fetch_src $origin "$tag" "$source"
        fetch_src $origin "$tag" "$maps/map.$codeset"
        fetch_src $origin "$tag" "$maps/widths.txt"
        if [ -n "$cldr_version" ] ; then
            cldr_version_info=" (CLDR=$cldr_version)"
        else
            cldr_version_info=""
        fi
        printf "$output/$origin: compiling $locale/$category$cldr_version_info..."
        if [ "$verbose" = "1" ] ; then echo ; fi
        case "$category" in
            LC_COLLATE) 
                localedef -U \
                    -i "$work_dir/$source" \
                    -V "$cldr_version" \
                    -f "$work_dir/$maps/map.$codeset" \
                    "$locale_dir"
                symlink_modifiers "$origin" "$cldr_version" "$locale"
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
    origin="$1"
    tag="$2"
    categorydir="$3"
    category="$4"

    rel="$(echo "$origin" | sed 's/^freebsd//')"
    work_path="$work/$origin"
    makefile="$categorydir/Makefile"

    fetch_src $origin "$tag" "$makefile"
    if [ "$category" = "LC_COLLATE" ] ; then
        # FreeBSD 13+ stamps CLDR_VERSION here, and injects it into the
        # locales that ship in the base system for retrieval with
        # querylocale(), where PostgreSQL looks.  We will do exactly
        # the same here to make PostgreSQL happy.
        #
        # If you explicitly ask for 11 or 12, you'll get an empty
        # string here, and no "version-mod" directory.  Before that,
        # the ancient locale code was used and none of this is likely
        # to work...
        cldr_version="$(grep '^CLDR_VERSION=' "$work_path/$makefile" |
            head -1 | sed 's/[^"]*"//;s/"$//')"
    else
        # For other categories you just get "plain" and "origin-mod",
        # no "version-mod".
        #
        # (Would it even make sense to use CLDR versions to locate
        # other categories?  LC_CTYPE, maybe, but I guess it really
        # wants a Unicode version... that's surely implied by CLDR
        # though...)
    fi

    mkdir -p "$output/$origin/plain"

    (grep '^SYMPAIRS+=' "$work_path/$makefile" | sed 's/.*=//;s/#.*//') | while read -r symlink_from symlink_to ; do
        if [ ! -L "$work_path/$categorydir/$symlink_to" ] ; then
            fetch_src $origin "$tag" "$categorydir/$symlink_from"
            ln -w -s "$symlink_from" "$work_path/$categorydir/$symlink_to"
        fi
    done
    (grep '^LOCALES_MAPPED+=' "$work_path/$makefile" | sed 's/.*=//;s/#.*//') | while read -r map_from locale ; do
        build_locale_category \
            "$origin" \
            "$tag" \
            "$locale" \
            "$category" \
            "$cldr_version" \
            "$categorydir/$map_from.src"
    done
    (grep '^SAME+=' "$work_path/$makefile" | sed 's/.*=//;s/#.*//') | while read -r symlink_from symlink_to ; do
        build_locale_category \
            "$origin" \
            "$tag" \
            "$symlink_from" \
            "$category" \
            "$cldr_version" \
            "$categorydir/$symlink_from.src"
        symlink_locale_category \
            "$origin" \
            "$symlink_to" \
            "$category" \
            "$cldr_version" \
            "$symlink_from"
    done
    for locale in $(grep '^LOCALES+=' "$work_path/$makefile" | sed 's/.*=//') ; do
        build_locale_category \
            "$origin" \
            "$tag" \
            "$locale" \
            "$category" \
            "$cldr_version" \
            "$categorydir/$locale.src"
    done
}

build_locales()
{
    origin="$1"
    tag="$2"

    rel="$(echo "$origin" | sed 's/^freebsd//')"

    build_locales_category "$origin" "$tag" "share/colldef" "LC_COLLATE"
    build_locales_category "$origin" "$tag" "share/ctypedef" "LC_CTYPE"
    build_locales_category "$origin" "$tag" "share/monetdef" "LC_MONETARY"
    build_locales_category "$origin" "$tag" "share/msgdef" "LC_MESSAGE"
    build_locales_category "$origin" "$tag" "share/numericdef" "LC_NUMERIC"
    build_locales_category "$origin" "$tag" "share/timedef" "LC_TIME"

    rel_major="$(echo $rel | sed 's/\..*//')"
    if [ "$rel_major" -ge "14" ] ; then
        build_locales_category "$origin" "$tag" "share/colldef_unicode" "LC_COLLATE"
        build_locales_category "$origin" "$tag" "share/monetdef_unicode" "LC_MONETARY"
        build_locales_category "$origin" "$tag" "share/msgdef_unicode" "LC_MESSAGE"
        build_locales_category "$origin" "$tag" "share/numericdef_unicode" "LC_NUMERIC"
    fi

    echo "$output/$origin"
}

scan_tags()
{
    list_only="$1"
    origin_filter="$2"

    my_rel="$(uname -v | sed 's|^[^0-9]*||;s|-.*$||')"
    my_rel_major="$(echo $my_rel | sed 's|\..*||')"
    my_rel_minor="$(echo $my_rel | sed 's|^[^.]*\.||')"
    last_rel=""

    if [ "$list_only" != "0" ] ; then
        printf "%-12s %s\n" "NAME" "TAG"
    fi

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

        if [ "$rel" = "$last_rel" ] ; then
            # skip non-latest unless --list-more
            if [ "$list_only" -lt "2" ] ; then continue ; fi
            # no friendly origin name for non-lastest
            origin=""
        else
            last_rel="$rel"
            origin="freebsd$rel"
        fi

        # --release name match?
        if [ "$origin_filter" = "$origin" ] ; then
            if [ "$list_only" = "0" ] ; then
                build_locales "$origin" "$tag"
                break
	    fi
        fi

        if [ "$list_only" == "2" ] ; then
              # oldest version using modern localedef pipeline
	      if [ "$rel_major" -lt 11 ] ; then continue ; fi
        else
              # oldest version stamped with CLDR versions
	      if [ "$rel_major" -lt 13 ] ; then continue ; fi
	fi

        # Skip if newer than the host's localedef.
        if [ "$rel_major" -gt "$my_rel_major" ] ; then
            continue
        elif [ "$rel_major" -eq "$my_rel_major" -a \
            "$rel_minor" -gt "$my_rel_minor" ] ; then
            continue
        fi

        if [ "$list_only" != "0" ] ; then
            printf "%-12s %s\n" "$origin" "$tag"
        else
            build_locales "$origin" "$tag"
        fi
    done
}

show_help()
{
    cat >&2 <<EOF

Usage: $0 [-v|--verbose] [-b|--builddir <path>] command

 where command is:

  -l|--list                  list available releases
  -r|--release name          cross-compile locales of named release
  -a|--all                   cross-compile locales of lastest releases
  -i|--install [prefix]      install cross-compiled locales
  -p|--package [destdir]     package cross-compiled locales

 Options and commands for finer control:

  -L|--list-outdated         list non-latest-patch levels too
  -t|--tag tag name          variant with free-form git tag and name

 To query a different Github repo instead of the offical FreeBSD
 mirror, or a local repo:

  --github-user user         alternative Github user
  --github-repo repo         alternative Github repo
  --git-local local_path     use a local mirror

EOF
}
 
verbose=0
output="build"
work="work"

while : ; do
    case "$1" in
        -v|--verbose)        verbose=1; shift;;
        -b|--builddir)       output="$1"; shift;;
        -l|--list)           scan_tags 1; break;;
        -L|--list-outdated)  scan_tags 2; break;;
        -a|--all)            scan_tags 0; break;;
        -r|--release)        scan_tags 0 "$2"; break;;
        -t|--tag)            build_locales "$3" "$2"; break;;
        *)                   show_help; exit 1;;
    esac
done
