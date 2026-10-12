#!/bin/sh

set -e

local_repo="debian_local_repo"

mkdir -p "$local_repo"

for i18n_dir in xlocales-source/i18n.* ; do
    echo $i18n_dir
    origin="$(cat "$i18n_dir/.xlocales.origin")"
    libc_version="$(cat "$i18n_dir/.xlocales.libc_version")"
    package_version="$(cat "$i18n_dir/.xlocales.source_version")"
    package_url="$(cat "$i18n_dir/.xlocales.source_url")"

    sanitized_revision="$(echo "$package_version" | sed 's/^[0-9]*\.[0-9]*-//;s/\.[a-z]*/./;s/[-_]/./g')"
    package_version="$libc_version-$sanitized_revision"
    
    dst_package="$local_repo/xlocales-$origin-data.$package_version.all.deb"

    if [ -e "$dst_package" ] ; then
        continue
    fi
    
    stage="stage/xlocales-$origin-data"
    rm -fr "$stage"
    mkdir -p "$stage/usr/lib"
    cp -r "$i18n_dir" "$stage/usr/lib/"
    mkdir "$stage/DEBIAN"
    sed -e "s|@package_version@|$package_version|" \
        -e "s|@package_url@|$package_url|" \
        -e "s|@libc_version@|$libc_version|" \
        -e "s|@origin@|$origin|" \
        -e "s|@maintainer@|$maintainer|" \
        -e "s|@homepage@|https://github.com/macdice/xlocales|" \
        < "debian/xlocales-data/control.in" \
        > "$stage/DEBIAN/control"
    dpkg-deb --root-owner-group -b "$stage" "$local_repo/xlocales-$origin-data.$package_version.all.deb"
done
