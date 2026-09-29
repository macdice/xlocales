#!/bin/sh
#
# A tool for cross-compiling locales.
#
# Quick start:
#
#   ./xlocales.sh fetch [SOURCE]
#   ./xlocales.sh build [SOURCE|ORIGIN]
#   make -j4
#   make package
#
# If a SOURCE is not specified, a default is selected based on the
# host system.
#
# See "./xlocales --help" for a list of supported SOURCE.  See
# "./xlocales list SOURCE" for a list of ORIGIN values available from
# a each supported SOURCE.
#
# Once packages are installed, locales can be exposed to libc by
# setting LOCPATH (glibc) or PATH_LOCALE (FreeBSD) to include one or
# more subdirectory of PREFIX/xlocales, depending on which locale
# names you want to bring into scope:
#
#   xlocales/
#     SOURCE/
#       locales@/         @origin + @version names from SOURCE
#       locales@origin/   @origin names from SOURCE
#       locales@version/  @version names from SOURCE
#     ORIGIN/
#       locales/          unmodified names that hide system locales
#       locales@/         @origin + @version names from ORIGIN
#       locales@origin/   @origin names from ORIGIN
#       locales@version/  @version names from ORIGIN
#     locales@/           all @origin names + @version names from host OS
#     locales@origin/     all @origin names
#     locales@version/    all @version names from host OS
#
# Some examples:
#
# To run a program with an earlier release of FreeBSD's locales with
# standard names, hiding the system locales, on a FreeBSD system:
#
#   PATH_LOCALE=/usr/local/lib/xlocales/freebsd13.3/locales
#
# To make historical locales from the host OS (assuming it is one that
# is supported as a source) on a glibc system, for example locale
# names like en_US.utf8@debian12 and en_US.utf8@glibc2.31:
#
#   LOC_PATH=/usr/lib/xlocales/locales@
#
# To make historical Ubuntu locales with names available in addition
# to the system locales, using names like en_US.utf8@ubuntu22.04
# and en_US.utf8@glibc2.31 (= @version) available in addition
# to the system locales, on a Rocky system:
#
#   LOC_PATH=/usr/lib/xlocales/ubuntu/locales@

set -e

xlocales_build="build"
xlocales_cache="cache"
xlocales_src="src"
xlocales_prefix="/usr/local"

xlocales_script_basename="$(echo "$0" | sed 's/\.sh$//')"

xlocales_sources_help=""

if [ -e "/etc/os-release" ] ; then
    . /etc/os-release
    xlocales_host_os="$ID"
    xlocales_host_os_version="$VERSION_ID"
    xlocales_host_origin="$xlocales_host_os$xlocales_host_os_version"
else
    echo "Could not identify host OS." >&2
    exit 1
fi

case "$ID" in
    freebsd) xlocales_host_libc_version="$host_version"
             xlocales_version_mod_prefix="cldr"
	     xlocales_default_source="freebsd"
	     xlocales_sources="freebsd"
	     . "$xlocales_script_basename.fetch.freebsd.sh"
	     . "$xlocales_script_basename.configure.freebsd.sh"
	     ;;
    
    *)       xlocales_host_libc_version="$(getconf GNU_LIBC_VERSION | \
                                         sed 's/.* \([0-9]\.[0-9][0-9]*\)$/\1/')"
             if [ "$?" != "0" -o -z "$xlocales_host_libc_version" ] ; then
		 echo "Host libc/localedef not supported."
		 exit 1
	     fi	     
	     xlocales_version_mod_prefix="glibc"
	     xlocales_default_source="glibc"
	     for module in $(ls $xlocales_script_basename.fetch.glibc.*.sh) ; do
		 module_os="$(echo "$module" | sed 's/.*\.fetch\.glibc\.\(.*\)\.sh/\1/')"
		 . "$xlocales_script_basename.fetch.glibc.${module_os}.sh"
                 xlocales_sources="$xlocales_sources $module_os"
		 if [ "$module" = "$xlocales_host_fetch_module" ] ; then
		     # if it matches the host OS, make it the default source
		     xlocales_default_source="$module_os"
		 fi
	     done	     
	     . "$xlocales_script_basename.configure.glibc.sh"
	     ;;
esac

check_source()
{
    source="$1"
    if [ -z "$source" ] ; then
	echo "$xlocales_default_source"
	return
    fi
    for x in $xlocales_sources ; do
	if [ "$xlocales_source" = "$x" ] ; then
	    echo "$x"
	    return
	fi
    done
    echo "Source \"$1\" is unknown" >&2
    exit 1    
}

origin_get_source()
{
    echo "$1" | sed 's/[0-9].*$//'
}

origin_get_version()
{
    echo "$1" | sed 's/^[^0-9]*//'
}

show_help()
{
    cat >&2 <<EOF
Usage: $0 [options...] command

 Options:
   --help                    display this help
   --build path              where to compile locales (default: build)
   --src path                where to put sources (default: src)
   --cache path              where to cache temporary files (default: cache)
   --prefix path             package prefix (default: /usr/local)

 Commands:
   list [source]             lists all versions of 'source' (default: $xlocales_default_source)
   fetch [source]            fetches all versions of 'source' (default: $xlocales_default_source)
   fetch source/version ...  fetches specified locale data
   configure                 generates Makefiles to compile all fetched locales

 Host information:
   OS:                       $xlocales_host_os
   OS version:               $xlocales_host_os_version
   libc version:             $xlocales_host_libc_version

 Available sources:
EOF
    for x in $xlocales_sources ; do
	desc="$(xlocales_${x}_desc)"
	printf "   %-25s %s\n" "$x" "$desc"
    done
}

fetch_src()
{
    url="$1"
    dst="$2"

    if [ ! -e "$dst" ] ; then
	mkdir -p "$(dirname "$dst")"
	curl -f -s -S "$url" > "$dst.tmp"
	mv "$dst.tmp" "$dst"
    fi
}

fetch_source()
{
    source="$1"
    echo "Fetching all origins for source: $source"
    for origin in $(xlocales_${source}_list | cut -d' ' -f1) ; do
	fetch_origin "$origin"
    done
}

fetch_origin()
{
    origin="$1"
    source="$(origin_get_source "$origin")"
    echo "Fetching origin: $origin"
    xlocales_${source}_fetch "$origin"
}

while : ; do
    case "$1" in
        -b|--build)  xlocales_build="$2";  shift; shift;;
        -c|--cache)  xlocales_cache="$2";  shift; shift;;
        -s|--src)    xlocales_src="$2";    shift; shift;;
        -p|--prefix) xlocales_prefix="$2"; shift; shift;;
	list)
	    shift
	    if [ -n "$1" ] ; then
		source="$1"
	    else
		source="$xlocales_default_source"
	    fi
	    xlocales_${source}_list | cut -f1
	    break
	    ;;
	fetch)
	    shift
	    if [ -z "$1" ] ; then
		fetch_source "$xlocales_default_source"
	    else
		for source_or_origin in $@ ; do
		    case "$source_or_origin" in
			*[0-9]*) fetch_origin "$source_or_origin";;
			*)       fetch_source "$source_or_origin";;
		    esac
		done
	    fi
	    break
	    ;;	    
	*) show_help
	   exit 1
    esac
done
