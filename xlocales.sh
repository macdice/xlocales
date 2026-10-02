#!/bin/sh
#
# An experimental tool for making old versions of locales available,
# cross-compiled for the host libc, using various naming schemes to
# identify them.

set -e

xlocales_version="1"

xlocales_build="build"
xlocales_cache="cache"
xlocales_src="src"
xlocales_jobs="1"
xlocales_silent=""
xlocales_homepage="https://github.com/macdice/xlocales"
xlocales_maintainer="Thomas Munro <thomas.munro@gmail.com>"
xlocales_unicode="auto"

xlocales_log()
{
    echo "$1" >&2
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

case "$ID" in
    freebsd)
        xlocales_max_libc_version="$xlocales_host_os_version"
        xlocales_min_libc_version="11.0"
        xlocales_version_mod_prefix="cldr"
        xlocales_default_source="freebsd"
        xlocales_sources="freebsd"
        xlocales_jobs="$(sysctl -n hw.ncpu)"
        xlocales_prefix="/usr/local"
        xlocales_infix="share"
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
        xlocales_version_mod_prefix="glibc"
        xlocales_default_source="gnu"
        xlocales_jobs="$(nproc)"
        xlocales_prefix="/usr"
        xlocales_infix="lib"
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
        ;;
esac

# Test if x <= y using version string semantics.
xlocales_version_le()
{
    printf '%s\n%s\n' "$1" "$2" | sort -V --check=silent
}

# Extract source part of an origin string.
origin_get_source()
{
    echo "$1" | sed 's/[0-9].*$//'
}

# Extract version part of an origin string.
origin_get_version()
{
    echo "$1" | sed 's/^[^0-9]*//'
}

# Show help and exit.
show_help()
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
   -P|--package format        one of deb|rpm|pkg|tar|none (default: $xlocales_package)

 Commands:
   list [source]              lists (default: $xlocales_default_source)
   fetch [source|origin]...   fetches, unpacks, creates makefiles
   build [source|origin]...   builds and packages, fetching first if required
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
begin_status()
{
    if [ -z "$COLUMNS" ] ; then
        printf "$1" >&2
    else
        printf "%.*s" $((COLUMNS - 2)) "$1" >&2
    fi
}

# Clear temporary activity message (ANSI control codes).
end_status()
{
    printf "\r\033[K" >&2
}

clear_output()
{
    printf "\r\033[K" >&2
}

# Fetch from URL and store it at $2, unless it is already present.
fetch_src()
{
    url="$1"
    dst="$2"

    if [ ! -e "$dst" ] ; then
        mkdir -p "$(dirname "$dst")"
        begin_status "Fetching $url"
        curl -L -f -s -S "$url" > "$dst.tmp"
        mv "$dst.tmp" "$dst"
        end_status
    fi
}

# Fetch all origins listed by $1.
fetch_source()
{
    source="$1"

    xlocales_log "Fetching locale data from source: $source"
    if [ -n "$xlocales_clear_cache" ] ; then
        rm -fr "$xlocales_cache/$source"
        rm -fr "$xlocales_cache/$source"*
    fi

    for origin in $(xlocales_${source}_list | cut -d' ' -f1) ; do
        fetch_origin "$origin"
    done
}

# Fetch and unpack sources from an origin under $xlocales_src/$origin.
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
fetch_origin()
{
    origin="$1"
    source="$(origin_get_source "$origin")"

    if [ -n "$xlocales_clear_cache" ] ; then
        rm -fr "$xlocales_cache/$origin"
    fi

    xlocales_log "Fetching locale data from origin: $origin"
    xlocales_${source}_fetch "$origin"
}

build_source()
{
    source="$1"

    xlocales_log "Building all origins for source: $source"
    for origin in $(xlocales_${source}_list | cut -d' ' -f1) ; do
        build_origin "$origin"
    done
}

build_origin()
{
    origin="$1"
    source="$(origin_get_source "$origin")"

    fetch_origin "$origin"
    xlocales_log "Building origin: $origin"
    make -C "$xlocales_src/$origin" $xlocales_silent -j "$xlocales_jobs"
}

deb_origin()
{
    origin="$1"

    xlocales_log "Building origin: $origin"
    make -C "$xlocales_src/$origin" $xlocales_silent -j "$xlocales_jobs"
}

diff_origin()
{
    origin1="$1"
    origin2="$2"
    source="$(origin_get_source "$origin")"

    if [ -z "$origin2" ] ; then
        xlocales_log "Diffing $origin1 against upstream GNU sources"
    else
        xlocales_log "Diffing $origin1 against $origin2"
    fi
    xlocales_${source}_diff "$origin"
}

while : ; do
    case "$1" in
        -b|--build)  xlocales_build="$2";  shift; shift;;
        -c|--cache)  xlocales_cache="$2";  shift; shift;;
        -s|--src)    xlocales_src="$2";    shift; shift;;
        -p|--prefix) xlocales_prefix="$2"; shift; shift;;
        -j|--jobs)   xlocales_jobs="$2";   shift; shift;;
        -s|--silent) xlocales_silent="-s"; shift;;
        -H|--homepage) xlocales_homepage="$2"; shift; shift;;
        -M|--maintainer) xlocales_maintainer="$2"; shift; shift;;
        -T|--tar)    xlocales_package="tar"; shift;;
        -R|--rpm)    xlocales_package="rpm"; shift;;
        -D|--deb)    xlocales_package="deb"; shift;;
        -P|--pkg)    xlocales_package="$2"; shift; shift;;
        -u|--unicode) xlocales_unicode="1"; shift;;
        --clear-cache) xlocales_clear_cache="1"; shift;;
        --clean)     xlocales_clean="1"; shift;;
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
            diff_origin "$1" "$2"
            ;;
        fetch|build)
            verb="$1"
            shift
            if [ -z "$1" ] ; then
                ${verb}_source "$xlocales_default_source"
            else
                for source_or_origin in $@ ; do
                      case "$source_or_origin" in
                        *[0-9]*) ${verb}_origin "$source_or_origin";;
                        *)       ${verb}_source "$source_or_origin";;
                    esac
                done
            fi
            break
            ;;
        *) show_help;;
    esac
done
