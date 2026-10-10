xlocales_deb_origin()
{
    origin="$1"
    
    stage="$xlocales_stage/$origin"

    if [ ! -e "$stage/done" ] ; then
        xlocales_stage_origin "$origin"
    fi

    src="$xlocales_src/$origin"
    libc_version="$(cat "$src/libc.version")"
    package_version="$(cat "$src/package.version")"
    package_url="$(cat "$src/package.url")"

    mkdir -p "$xlocales_packages"
    
    for suffix in "data" "compile" ; do
        rm -fr "$stage/xlocales-$suffix.deb"
        mkdir -p "$stage/xlocales-$suffix.deb/DEBIAN"
        if [ -e "$stage/xlocales-$suffix/$xlocales_prefix" ] ; then
            cp -r "$stage/xlocales-$suffix/$xlocales_prefix" \
               "$stage/xlocales-$suffix.deb/$xlocales_prefix"
        fi
        for file in $(ls "xlocales-$suffix/DEBIAN") ; do
            sed -e "s|@homepage@|$xlocales_homepage|" \
                -e "s|@maintainer@|$xlocales_maintainer|" \
                -e "s|@package_name@|xlocales-$origin|" \
                -e "s|@package_url@|$package_url|" \
                -e "s|@package_version@|$package_version|" \
                -e "s|@libc_version@|$libc_version|" \
                -e "s|@prefix@|$xlocales_prefix|" \
                -e "s|@origin@|$origin|" \
                < "xlocales-$suffix/DEBIAN/$file.in" \
                > "$stage/xlocales-$suffix.deb/DEBIAN/file"
        done    
        dpkg-deb --root-owner-group -b "$stage/xlocales-$suffix.deb" \
                 "$xlocales_packages/xlocales-${origin}-$suffix_${package_version}_all.deb"
    done
}
