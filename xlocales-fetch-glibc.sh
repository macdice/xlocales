#!/bin/sh
#
# Fetch upstream GNU glibc sources (ie without any modifications made
# by GNU/Linux distributions).

set -e

XLOCALES_SOURCE="glibc"
XLOCALES_GLIBC_URL="https://ftp.gnu.org/gnu/glibc"

. "./xlocales-utils.sh"
. "./xlocales-utils-glibc.sh"

xlocales_fetch_glibc_list()
{
    index_file="cache/$XLOCALES_SOURCE/index.html"

    xlocales_fetch "glibc" "$XLOCALES_GLIBC_URL/" "$index_file"
    for libc_version in $(sed -n 's/^.*a href="glibc-\([0-9]\.[0-9][0-9]*\)\.tar\.xz".*$/\1/p' < "$index_file" | sort -r -V) ; do
	    if ! xlocales_version_le "$XLOCALES_GLIBC_MIN_VERSION" \
             "$libc_version" ; then
            break
	    fi
        echo "glibc$libc_version"
    done
}

xlocales_fetch_glibc()
{
    origin="$1"

    version="$(xlocales_origin_get_version "$origin")"

    package_url="$XLOCALES_GLIBC_URL/glibc-$version.tar.xz"
    package_file="glibc-$version.tar.xz"

    src="src/$origin"
    rm -fr "$src"
    mkdir -p "$src"

    echo "$package_url" > "$src/package.url"
    echo "$package_file" > "$src/package.file"
    echo "$version" > "$src/package.version"
    xlocales_fetch "$origin" "$url" "cache/$origin/$tarball"
    
    sed -e "s|@prefix@|/usr|g" \
        -e "s|@origin@|$origin|g" \
        -e "s|@package_url@|$package_url|g" \
        -e "s|@package_file@|$package_file|g" \
        -e "s|@package_version@|$version|g" \
        -e "s|@libc_version@|$version|g" \
        < "Makefile.glibc.in" \
        > "$src/Makefile"
    cp xlocales-extract-glibc.sh "$src/xlocales-extract.sh"
    cp xlocales-gen.sh "$src/"
    cp xlocales-texinfo.sh "$src/"
    chmod +x "$src"/*.sh

    echo "$src"
    return

    xlocales_fetch "$origin" "$url" "$tarball"

    xlocales_begin_status "$origin: extracting $src"
    tar xf "$tarball" -C "$src"
    xlocales_end_status

    (
        # Unlike downstream distributions, which ship the locale
        # definitions ready-made, here we need to configure and
        # compile a couple of things first.
        cd "$src/build"
        # We don't really need texinfo, so keep configure quiet if
        # it's not installed.
        cat > dummy_makeinfo <<EOF
#!/bin/sh
echo "GNU texinfo.dummy 7.3"
EOF
        chmod +x dummy_makeinfo

        xlocales_begin_status "$origin: configuring glibc"
        ../glibc-$version/configure --quiet --prefix=/tmp/dummy --srcdir "../glibc-$version" --disable-sanity-checks MAKEINFO="$(pwd)/dummy_makeinfo"
        xlocales_end_status

        xlocales_begin_status "$origin: building localedata/subdir_lib"
        make -s localedata/subdir_lib > "make.log"
        xlocales_end_status           
    )

    xlocales_stage_glibc "$origin" \
                         "$src/glibc-$version/localedata" \
                         "$output_dir/i18n.$origin" \
                         "$version" \
                         "$url"
}    
    
case "$1" in
    ''|help|-h|--help)
        cat <<EOF >&2
Usage:
  $0 --list                list available versions of glibc
  $0 glibc [output_dir]    fetch locale data for all versions of glibc
  $0 glibcX.Y [output_dir] fetch locale data for one version of glibc
EOF
        exit 1
        ;;
    --list)
        xlocales_fetch_glibc_list
        ;;
    glibc)
        for origin in $(xlocales_fetch_glibc_list | cut -d' ' -f1) ; do
		    xlocales_fetch_glibc "$origin" "$2"
        done
        ;;
    glibc*)
        xlocales_fetch_glibc "$1" "$2"
        ;;
    *)
        xlocales_get_usage
        ;;
esac

