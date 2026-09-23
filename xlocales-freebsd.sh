#!/bin/sh
#
# Compile historical FreeBSD locale data with the host localedef.

set -e

verbose=0
outdated=0
newer_than_host=0
builddir="build"
srcdir="src"
prefixdir="/usr/local"
create_version_modifier="1"
create_origin_modifier="1"
origin_prefix="fbsd"
version_prefix="cldr"
custom_tag=""
github_user="freebsd"
github_repo="freebsd-src"
git_local_path=""

maps="tools/tools/locale/etc/final-maps"

fetch_src()
{
    origin="$1"
    tag="$2"
    src_path="$3"

    src_url="https://raw.githubusercontent.com/freebsd/freebsd-src/$tag/$src_path"
    src_dir="$(dirname "$src_path")"

    srcdir_path="$srcdir/$origin"
    dst_dir="$srcdir/$origin/$src_dir"
    dst_path="$srcdir/$origin/$src_path"

    if [ ! -e "$dst_path" ] ; then
        mkdir -p "$dst_dir"
        if [ "$verbose" = "1" ] ; then
            echo "$builddir/$origin: fetching $src_url..."
        else
            printf "$builddir/$origin: fetching $src_path..."
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

    if [ "$create_origin_modifier" = "1" ] ; then
        locale_origin="$locale@$origin"
        locale_origin_symlink="$builddir/$origin/origin-mod/$locale_origin"
        if [ ! -L "$locale_origin_symlink" ] ; then
            mkdir -p "$(dirname "$locale_origin_symlink")"
            ln -w -s "../plain/$locale" "$locale_origin_symlink"
	fi
    fi

    if [ "$create_version_modifier" = "1" -a -n "$cldr_version" ] ; then 
        locale_version="$locale@$version_prefix$cldr_version"
        locale_version_symlink="$builddir/$origin/version-mod/$locale_version"
        if [ ! -L "$locale_version_symlink" ] ; then
            mkdir -p "$(dirname "$locale_version_symlink")"
            ln -w -s "../plain/$locale" "$locale_version_symlink"
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

    locale_dir="$builddir/$origin/plain/$locale"

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
    
    srcdir_dir="$srcdir/$origin"
    locale_dir="$builddir/$origin/plain/$locale"

    # The tag will be needed to build a package.
    if [ ! -e "$srcdir_dir/tag" ] ; then
        echo "$tag" > "$srcdir_dir/tag"
    elif ! grep "^$tag\$" "$srcdir_dir/tag" > /dev/null ; then
    fi

    if [ ! -e "$locale_dir/$category" ] ; then
        #echo "$origin: $locale/$category $cldr_version"
        mkdir -p "$locale_dir"
        symlink_modifiers "$origin" "$cldr_version" "$locale"
        codeset="$(echo "$locale" | sed 's/.*\.//;s/@.*//')"
        fetch_src $origin "$tag" "$source"
        fetch_src $origin "$tag" "$maps/map.$codeset"
        fetch_src $origin "$tag" "$maps/widths.txt"
        if [ -n "$cldr_version" ] ; then
            cldr_version_info=" (CLDR=$cldr_version)"
        else
            cldr_version_info=""
        fi
        printf "$builddir/$origin: compiling $locale/$category$cldr_version_info..."
        if [ "$verbose" = "1" ] ; then echo ; fi
        case "$category" in
            LC_COLLATE) 
                localedef -U \
                    -i "$srcdir_dir/$source" \
                    -V "$cldr_version" \
                    -f "$srcdir_dir/$maps/map.$codeset" \
                    "$locale_dir"
                symlink_modifiers "$origin" "$cldr_version" "$locale"
                ;;
            LC_CTYPE)
                localedef -U -c \
                    -w "$srcdir_dir/$maps/widths.txt" \
                    -i "$srcdir_dir/$source" \
                    -f "$srcdir_dir/$maps/map.$codeset" \
                    "$locale_dir"
                   ;;
            *) 
                grep -v -E '^(#$$|#[ ])' \
                    < "$srcdir_dir/$source" \
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

    srcdir_path="$srcdir/$origin"
    makefile="$categorydir/Makefile"

    fetch_src "$origin" "$tag" "$makefile"
    if [ "$category" = "LC_COLLATE" ] ; then
        # FreeBSD 13+ stamps CLDR_VERSION here, and injects it into the
        # locales that ship in the base system for retrieval with
        # querylocale(), where PostgreSQL looks.  We will do exactly
        # the same here to make PostgreSQL happy.
        #
        # If you explicitly ask for 11 or 12, you'll get an empty
        # string here, and no "version-mod" directory.  Before that,
        # the ancient locale code was used and none of this is likely
        # to srcdir...
        cldr_version="$(grep '^CLDR_VERSION=' "$srcdir_path/$makefile" |
            head -1 | sed 's/[^"]*"//;s/"$//')"
    else
        # For other categories you just get "plain" and "origin-mod",
        # no "version-mod".
        #
        # (Would it even make sense to use CLDR versions to locate
        # other categories?  LC_CTYPE, maybe, but I guess it really
        # wants a Unicode version... that's surely implied by CLDR
        # though...)
        cldr_version=""
    fi

    mkdir -p "$builddir/$origin/plain"

    (grep '^SYMPAIRS+=' "$srcdir_path/$makefile" | sed 's/.*=//;s/#.*//') | while read -r symlink_from symlink_to ; do
        if [ ! -L "$srcdir_path/$categorydir/$symlink_to" ] ; then
            fetch_src $origin "$tag" "$categorydir/$symlink_from"
            ln -w -s "$symlink_from" "$srcdir_path/$categorydir/$symlink_to"
        fi
    done
    (grep '^LOCALES_MAPPED+=' "$srcdir_path/$makefile" | sed 's/.*=//;s/#.*//') | while read -r map_from locale ; do
        build_locale_category \
            "$origin" \
            "$tag" \
            "$locale" \
            "$category" \
            "$cldr_version" \
            "$categorydir/$map_from.src"
    done
    (grep '^SAME+=' "$srcdir_path/$makefile" | sed 's/.*=//;s/#.*//') | while read -r symlink_from symlink_to ; do
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
    for locale in $(grep '^LOCALES+=' "$srcdir_path/$makefile" | sed 's/.*=//') ; do
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

    build_locales_category "$origin" "$tag" "share/colldef" "LC_COLLATE"
    build_locales_category "$origin" "$tag" "share/ctypedef" "LC_CTYPE"
    build_locales_category "$origin" "$tag" "share/monetdef" "LC_MONETARY"
    build_locales_category "$origin" "$tag" "share/msgdef" "LC_MESSAGE"
    build_locales_category "$origin" "$tag" "share/numericdef" "LC_NUMERIC"
    build_locales_category "$origin" "$tag" "share/timedef" "LC_TIME"

    if [ "$rel_major" -ge "14" ] ; then
        build_locales_category "$origin" "$tag" "share/colldef_unicode" "LC_COLLATE"
        build_locales_category "$origin" "$tag" "share/monetdef_unicode" "LC_MONETARY"
        build_locales_category "$origin" "$tag" "share/msgdef_unicode" "LC_MESSAGE"
        build_locales_category "$origin" "$tag" "share/numericdef_unicode" "LC_NUMERIC"
    fi

    echo "$builddir/$origin"
}

scan_tags()
{
    list_only="$1"
    origin_filter="$2"

    my_rel="$(uname -v | sed 's|^[^0-9]*||;s|-.*$||')"
    my_rel_major="$(echo $my_rel | sed 's|\..*||')"
    my_rel_minor="$(echo $my_rel | sed 's|^[^.]*\.||')"
    last_rel=""

    if [ -n "$git_local_path" ] ; then
	git_command="-C $git_local_path tag"
    else
        github_url="https://github.com/$github_user/$github_repo"
	git_command="git ls-remote --tags $github_url | cut -f2 | sed 's|refs/tags/||' | grep -v '\^{}' | grep -v '_cvs'"
    fi

    for tag in $(sh -c "$git_command" | grep -v '_cvs$' | grep '^release/[0-9][0-9]*\.[0-9][0-9]*\.' | sort -Vr) ; do
        rel="$(echo $tag | sed 's|^release/\([0-9]*\)\.\([0-9]*\)\..*$|\1.\2|')"
        rel_major="$(echo $rel | sed 's|\..*||')"
        rel_minor="$(echo $rel | sed 's|^[^.]*\.||')"

        if [ "$rel" = "$last_rel" ] ; then
            # skip non-latest unless --outdated
            if [ "$outdated" = "0" ] ; then continue ; fi
            # no friendly origin name for non-lastest tags
            origin=""
        else
            last_rel="$rel"
            origin="$origin_prefix$rel"
        fi

        # "build <origin>" non-match?
        if [ -n "$origin_filter" -a "$origin_filter" != "$origin" ] ; then
            continue
	fi

        if [ "$outdated" = "1" ] ; then
            # FreeBSD 11.0 is when the modern localedef toolchain replaced
	    # ancient pre-Unicode locales.
            if [ "$rel_major" -lt 11 ] ; then continue ; fi
	else
	    # FreeBSD 13.0 is where CLDR version stamps that PostgreSQL cares
	    # about began.
	    if [ "$rel_major" -lt 13 ] ; then continue ; fi
	fi

	# Skip newer than the host's localedef, unless --newer-than-host
	# specified, since that seems like it might lead to problems.
	if [ "$newer_than_host" = "0" ] ; then
            if [ "$rel_major" -gt "$my_rel_major" ] ; then
                continue
            elif [ "$rel_major" -eq "$my_rel_major" -a \
                "$rel_minor" -gt "$my_rel_minor" ] ; then
                continue
	    fi
        fi

        if [ "$list_only" != "0" ] ; then
            printf "%-12s %s\n" "$origin" "$tag"
        else
            build_locales "$origin" "$tag"
        fi
    done
}

do_list()
{
    printf "%-12s %s\n" "ORIGIN" "TAG"
    scan_tags 1
}

do_build()
{
    origin="$1"

    if [ -n "$custom_tag" ] ; then
        if [ -z "$origin" -a "$create_origin_modifier" = "1" ] ; then
            echo "An origin must be provided when using explicit --tag,"
            echo "unless --no-origin-modifier is specified."
            exit 1
	fi
        build_locales "$origin" "$custom_tag"
    else
        scan_tags 0 "$origin"
    fi
}

show_help()
{
    cat >&2 <<EOF

Usage: $0 [options...] command

 Options:

  -V|--verbose                 log activity

  -O|--outdated                list non-latest-patch releases and < 13.0
  -N|--newer                   list releases newer than host localedef (!)

  -B|--builddir                where to compile locales (default: build)
  -S|--srcdir                  where to download/cache data (default: src)
  -P|--prefix                  package install prefix (default: /usr/local)

  -T|--tag                     specify a freeform Git tag to build
  -U|--github-user user        Github user (default: freebsd)
  -R|--github-repo repo        Github repo (default: freebsd-src)
  -G|--git-local-path path     query local repo instead of Github

     --origin-prefix           prefix for origin name (default: fbsd)
     --version-prefix          prefix for version modifiers (default: cldr)
     --no-version-modifier     don't create locale@version symlink tree
     --no-origin-modifier      don't create locale@origin symlink tree

 Commands:

  list                         list available origins (FreeBSD releases)
  build [origin]               cross-compile locales from one or all origins
  install                      install cross-compiled locales
  package                      package cross-compiled locales

EOF
}
 
while : ; do
    case "$1" in
        -V|--verbose)          verbose=1; shift;;
        -O|--outdated)         outdated=1; shift;;
        -N|--newer-than-host)  newer_than_host=1; shift;;
        -B|--builddir)         builddir="$2"; shift; shift;;
        -S|--srcdir)           srcdir="$2"; shift; shift;;
        -P|--prefix)           prefix="$2"; shift; shift;;

        -T|--tag)              custom_tag="$2"; shift; shift;;
        -U|--github-user)      github_user="$2"; shift; shift;;
        -R|--github-repo)      github_repo="$2"; shift; shift;;
        -G|--git-local-path)   git_local_path="$2"; shift; shift;;

        --origin-prefix)       origin_prefix="$2"; shift; shift;;
        --version-prefix)      version_prefix="$2"; shift; shift;;
        --no-origin-modifier)  create_origin_modifer=0; shift;;
        --no-version-modifier) create_version_modifer=0; shift;;

        list)                  do_list; break;;
        build)                 do_build "$2"; break;;
        install)               do_install; break;;
        package)               do_package; break;;

        *)                     show_help; exit 1;;
    esac
done
