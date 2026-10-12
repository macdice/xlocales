#!/bin/sh
#
# Fetch upstream GNU glibc sources (ie without any modifications made
# by GNU/Linux distributions).

XLOCALES_SOURCE="glibc"
XLOCALES_GLIBC_URL="https://ftp.gnu.org/gnu/glibc"

. "./xlocales-utils.sh"
. "./xlocales-utils-glibc.sh"

xlocales_get_glibc_list()
{
    index_file="cache/$XLOCALES_SOURCE/index.html"

    xlocales_fetch "glibc" "$XLOCALES_GLIBC_URL/" "$index_file"
    for libc_version in $(sed -n 's/^.*a href="glibc-\([0-9]\.[0-9][0-9]*\)\.tar\.xz".*$/\1/p' < "$index_file" | sort -r -V) ; do
	    if ! xlocales_version_le "$XLOCALES_GLIBC_MIN_VERSION" \
             "$libc_version" ; then
            break
	    fi
        echo "glibc$libc_version" "$libc_version"
    done
}

xlocales_get_glibc()
{
    origin="$1"
    output_dir="$2"

    if [ -z "$output_dir" ] ; then
        output_dir="xlocales-source"
    fi
    
    src="src/$origin"

    version="$(xlocales_origin_get_version "$origin")"
    url="$XLOCALES_GLIBC_URL/glibc-$version.tar.xz"
    tarball="cache/$origin/glibc-$version.tar.xz"

    mkdir -p "$src/build"

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
    list)
        xlocales_get_glibc_list
        ;;
    all)
        for origin in $(xlocales_get_glibc_list | cut -d' ' -f1) ; do
		    xlocales_get_glibc "$origin" "$2"
        done
        ;;
    "$XLOCALES_SOURCE"*)
        xlocales_get_glibc "$1" "$2"
        ;;
    *)
        xlocales_get_usage
        ;;
esac

