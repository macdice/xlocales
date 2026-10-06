#!/bin/sh
#
# An experimental tool for making old versions of locales available,
# cross-compiled for the host libc, using various naming schemes to
# identify them.
#
# To maximumize the number of systems (distributions x versions x
# architectures) that can use the same packages without needing a lot
# of packaging building hosts for different OSes, the packages (.tgz,
# .deb, .rpm, FreeBSD .pkg) it produces only contain locale source
# files and shell scripts.  They are compiled with the host's
# localedef on installation, or in the case of simple tarballs, by
# running compile-locales.sh manually.  That's a bit wasteful of CPU.

set -e

xlocales_cache="cache"
xlocales_src="src"
xlocales_stage="stage"
xlocales_packages="packages"
xlocales_jobs="1"
xlocales_homepage="https://github.com/macdice/xlocales"
xlocales_maintainer="Thomas Munro <thomas.munro@gmail.com>"
xlocales_unicode="auto"

xlocales_log()
{
    if [ -z "$xlocales_quiet" ] ; then
        echo "$1" >&2
    fi
}

xlocales_error()
{
    xlocales_log "$1"
    exit 1
}

if [ -e "/etc/os-release" ] ; then
    . /etc/os-release
    if [ -z "$ID" -o -z "$VERSION_ID" ] ; then
        xlocales_error "Could not identify host OS using /etc/os-release"
    fi
    xlocales_host_os="$ID"
    xlocales_host_os_version="$VERSION_ID"
    xlocales_host_origin="$xlocales_host_os$xlocales_host_os_version"
else
    xlocales_error "Could not identify host OS without /etc/os-release"
fi

xlocales_script_basename="$(echo "$0" | sed 's/\.sh$//')"

. "$xlocales_script_basename.tar.sh"

case "$ID" in
    freebsd)
        xlocales_max_libc_version="$xlocales_host_os_version"
        xlocales_min_libc_version="11.0"
        xlocales_default_source="freebsd"
        xlocales_sources="freebsd"
        xlocales_prefix="/usr/local"
        xlocales_system_locales="/usr/share/locale"
        xlocales_package="pkg"
        . "$xlocales_script_basename.freebsd.sh"
        ;;

    *)
        # Any glibc-based distribution should work as a target, though we only
        # support compiling locales from a distributions for which we have an
        # xlocales.glibc.ID.sh file.
        xlocales_max_libc_version="$(getconf GNU_LIBC_VERSION | \
            sed 's/.* \([0-9]\.[0-9][0-9]*\)$/\1/')"
        if [ "$?" != "0" -o -z "$xlocales_max_libc_version" ] ; then
            xlocales_error "Host libc/localedef not supported."
        fi
        xlocales_min_libc_version="2.28"
        xlocales_default_source="gnu"
        xlocales_prefix="/usr"
        xlocales_system_locales="/usr/lib/locale"

        # Guess default type of package without hardcoding distribution names.
        if [ -e "/var/lib/dpkg" ] ; then
            xlocales_package="deb"
        elif [ -e "/var/lib/rpm" ] ; then
            xlocales_package="rpm";
        else
            xlocales_package="tar";
        fi

        for module in $(ls $xlocales_script_basename.glibc.*.sh) ; do
            module_os="$(echo "$module" | sed 's/.*\.glibc\.\(.*\)\.sh/\1/')"
            . "$xlocales_script_basename.glibc.${module_os}.sh"
            xlocales_sources="$xlocales_sources $module_os"
            if [ "$module_os" = "$xlocales_host_os" ] ; then
                xlocales_default_source="$module_os"
            fi
        done

        . "$xlocales_script_basename.glibc.sh"
        . "$xlocales_script_basename.deb.sh"
        ;;
esac

# Test if x <= y using version string semantics.
xlocales_version_le()
{
    printf '%s\n%s\n' "$1" "$2" | sort -V --check=silent
}

# Test if a libc version is in the supported range.
xlocales_libc_version_in_range()
{
    libc_version="$1"

    if ! xlocales_version_le "$xlocales_min_libc_version" "$libc_version" ; then
	return 1
    fi
    if ! xlocales_version_le "$libc_version" "$xlocales_max_libc_version" ; then
	return 1
    fi
    return 0
}

# Fail if a libc version is outside the supported range.
xlocales_check_libc_version_supported()
{
    libc_version="$1"

    if ! xlocales_version_le "$xlocales_min_libc_version" "$libc_version" ; then
	xlocales_error "Locale data from $libc_version is older than the minimum supported version ($xlocales_min_libc_version)"
    fi
    if ! xlocales_version_le "$libc_version" "$xlocales_max_libc_version" ; then
	xlocales_error "Locale data from $libc_version is newer than the host localedef ($xlocales_max_libc_version)"
    fi
}

# Extract source part of an origin string.
xlocales_origin_get_source()
{
    echo "$1" | sed 's/[0-9].*$//'
}

# Extract version part of an origin string.
xlocales_origin_get_version()
{
    echo "$1" | sed 's/^[^0-9]*//'
}

# Show help and exit.
xlocales_help()
{
    cat >&2 <<EOF
Usage: $0 [options...] command

 Options:
   -s|--src path              where to put sources (default: $xlocales_src)
   -b|--build path            where to put packages (default: $xlocales_build)
   -c|--cache path            where to cache temporary files (default: $xlocales_cache)
   -p|--prefix path           installation prefix (default: $xlocales_prefix)
   -j|--jobs N                how many CPUs to use (default: $xlocales_jobs)
   -u|--unicode               enable optional @unicodeX.Y modifiers (default: off)
      --clear-cache           wipe cached meta-data files when listing/fetching

   -H|--homepage "https..."   Maintainer URL included in packages
   -M|--maintainer "..."      Maintainer "name <email>" included in packages

 Commands:
   list [source]              lists origins from source (default: $xlocales_default_source)
   fetch [source|origin]...   fetches, unpacks source
   build [source|origin]...   builds standard layout in --build

   deb [source|origin]...     builds Debian binary package(s) for glibc
   deb-src [source|origin]... builds Debian source package(s) for glibc
   rpm [source|origin]...     builds RPM binary package(s) for glibc
   srpm [source|origin]...    builds RPM binary package(s) for glibc
   pkg [source|origin]...     builds pkg-ng package(s) for FreeBSD
   tar [source|origin]...     builds tarball(s)

   clean [source|origin]...   wipe all temporary files

 Host information:
   OS:                        $xlocales_host_os
   OS version:                $xlocales_host_os_version
   libc version:              $xlocales_max_libc_version

 Available sources:
$(for x in $xlocales_sources ; do
      printf "   %-25s %s\n" "$x" "$(xlocales_${x}_desc)"
  done)

EOF
    exit 1
}

# Show temporary activity message.
xlocales_begin_status()
{
    string="$1"

    if [ -z "$COLUMNS" ] ; then
	COLUMNS="$(tput cols)"
	if [ -z "$COLUMNS" ] ; then
	    COLUMNS=80
	fi
    fi
    
    if [ ${#string} -gt $(($COLUMNS - 3)) ] ; then	
        printf "%.*s... " $((COLUMNS - 6)) "$string" >&2
    else
        printf "%s " "$string" >&2
    fi
}

# Clear temporary activity message (ANSI control codes).
xlocales_end_status()
{
    printf "\r\033[K" >&2
}

# Fetch file from URL and store it at $2, unless it is already present.
xlocales_fetch()
{
    origin_or_source="$1"
    url="$2"
    dst="$3"

    if [ ! -e "$dst" ] ; then
        xlocales_begin_status "$origin_or_source: fetching $url"
        mkdir -p "$(dirname "$dst")"
        curl -L -f -s -S "$url" > "$dst.tmp"
        mv "$dst.tmp" "$dst"
        xlocales_end_status
    fi
}

# Fetch all origins listed by $1.
xlocales_fetch_source()
{
    source="$1"

    if [ -n "$xlocales_clear_cache" ] ; then
        rm -fr "$xlocales_cache/$source"
        rm -fr "$xlocales_cache/$source"*
    fi

    for origin in $(xlocales_${source}_list | cut -d' ' -f1) ; do
        xlocales_fetch_origin "$origin"
    done
}

# Fetch and unpack sources under $xlocales_src/$origin.
#
# Since glibc systems all have slightly different layout, the fetch
# routines use symlinks to create a standardised layout like this:
#
#   charmaps/
#   locales/
#
# All systems create the following:
#
#   source_url - eg URL of source package
#   source_version - eg 2.31-7, 15.0.0-p1
#   libc_version - eg 2.31, 15.0
#   Makefile
#
# The Makefile's default target should build xlocales-ORIGIN,
# xlocales-system-ORIGIN, xlocales-system-extra-ORIGIN packages.
#
# If $xlocale_locales_pkg is not "none", the default Makefile target
# should also produce packages in
xlocales_fetch_origin()
{
    origin="$1"

    source="$(xlocales_origin_get_source "$origin")"

    rm -fr "$xlocales_src/$origin"    
    xlocales_${source}_fetch "$origin"
    touch "$xlocales_src/$origin/done"
}

xlocales_stage_source()
{
    source="$1"

    for origin in $(xlocales_${source}_list | cut -d' ' -f1) ; do
        xlocales_stage_origin "$origin"
    done
}

xlocales_stage_origin()
{
    origin="$1"

    if [ ! -e "$xlocales_src/$origin/done" ] ; then
        xlocales_fetch_origin "$origin"
    fi

    rm -fr "$xlocales_stage/$origin"
    
    source="$(xlocales_origin_get_source "$origin")"
    xlocales_${source}_stage "$origin"

    touch "$xlocales_stage/$origin/done"
}

xlocales_tar_source()
{
    source="$1"

    for origin in $(xlocales_${source}_list | cut -d' ' -f1) ; do
        xlocales_tar_origin "$origin"
    done
}

xlocales_diff_origin()
{
    origin1="$1"
    origin2="$2"
    source="$(xlocales_origin_get_source "$origin")"

    if [ -z "$origin2" ] ; then
        xlocales_log "Diffing $origin1 against upstream GNU sources"
    else
        xlocales_log "Diffing $origin1 against $origin2"
    fi
    xlocales_${source}_diff "$origin"
}

while : ; do
    case "$1" in
        -b|--build)      xlocales_build="$2";  shift; shift;;
        -c|--cache)      xlocales_cache="$2";  shift; shift;;
        -s|--src)        xlocales_src="$2";    shift; shift;;
        -p|--prefix)     xlocales_prefix="$2"; shift; shift;;
        -j|--jobs)       xlocales_jobs="$2";   shift; shift;;
        -H|--homepage)   xlocales_homepage="$2"; shift; shift;;
        -M|--maintainer) xlocales_maintainer="$2"; shift; shift;;
        -P|--package)    xlocales_package="$2"; shift; shift;;
        -u|--unicode)    xlocales_unicode="1"; shift;;
        --clear-cache)   xlocales_clear_cache="1"; shift;;
        --clean)         xlocales_clean="1"; shift;;

        list)
            shift
            if [ -n "$1" ] ; then
                source="$1"
            else
                source="$xlocales_default_source"
            fi
            if [ -n "$xlocales_clear_cache" ] ; then
                rm -fr "$xlocales_cache/$source"
                rm -fr "$xlocales_cache/$source"*
            fi
            xlocales_${source}_list | cut -f1
            break
            ;;

        diff)
            xlocales_diff_origin "$1" "$2"
            ;;

        fetch|stage|deb|tar)
            verb="$1"
            shift
            for source_or_origin in $@ ; do                
                if [ -z "$1" ] ; then
                    source_or_origin="$xlocales_default_source"
                fi
                case "$source_or_origin" in
                    *[0-9]*)
                        xlocales_${verb}_origin "$source_or_origin"
				        ;;
                    *) 
                        for origin in $(xlocales_${source_or_origin}_list | \
                                            cut -d' ' -f1) ; do
                            xlocales_${verb}_origin "$origin"
                        done
                esac
            done            
            break
            ;;

        *) xlocales_help;;
    esac
done
