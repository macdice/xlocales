xlocales_gnu_url="https://ftp.gnu.org/gnu/glibc"

xlocales_gnu_desc()
{
    echo "Upstream glibc tarballs from gnu.org"
}

xlocales_gnu_list()
{
    index_file="$xlocales_cache/gnu/index.html"

    xlocales_fetch "gnu" "$xlocales_gnu_url/" "$index_file"
    for locale_version in $(sed -n 's/^.*a href="glibc-\([0-9]\.[0-9][0-9]*\)\.tar\.xz".*$/\1/p' < "$index_file" | sort -r -V) ; do
	    if ! xlocales_version_le "$xlocales_min_libc_version" \
             "$locale_version" ; then
	        continue
	    fi
        echo "gnu$locale_version" "$locale_version"
    done
}

xlocales_gnu_fetch()
{
    origin="$1"

    src="$xlocales_src/$origin"

    if [ -e "$src/fetch.done" ] ; then return ; fi
    
    version="$(xlocales_origin_get_version "$origin")"
    url="$xlocales_gnu_url/glibc-$version.tar.xz"
    tarball="$xlocales_cache/$origin/glibc-$version.tar.xz"

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
        # We don't really need texinfo, so keep configure quiet
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

    ln -f "glibc-$version/localedata/SUPPORTED" "$src/SUPPORTED"
    ln -f "glibc-$version/localedata/locales" "$src/locales"
    ln -f "glibc-$version/localedata/charmaps" "$src/charmaps"
    echo "$url" > "$src/package.url"
    echo "$version" > "$src/package.version"
    echo "$version" > "$src/libc.version"
    touch "$src/fetch.done"
    
    #xlocales_glibc_fetch_common "$origin" \
    #                            "glibc-$version/localedata/locales" \
    #                            "glibc-$version/localedata/charmaps" \
    #                            "$url" \
    #                            "$version" \
    #                            "$version"
}

xlocales_gnu_stage()
{
    xlocales_glibc_stage "$1"
}
