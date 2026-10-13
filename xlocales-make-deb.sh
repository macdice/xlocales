#!/bin/sh

set -e

local_repo="debian_local_repo"

mkdir -p "$local_repo"

for i18n in $(ls xlocales-source/) ; do
    i18n_dir="xlocales-source/$i18n"
    origin="$(cat "$i18n_dir/.xlocales.origin")"
    libc_version="$(cat "$i18n_dir/.xlocales.libc_version")"
    package_version="$(cat "$i18n_dir/.xlocales.source_version")"
    package_url="$(cat "$i18n_dir/.xlocales.source_url")"

    # can't use RPM version strings without squishing some characters...
    sanitized_revision="$(echo "$package_version" | sed 's/^[0-9]*\.[0-9]*-//;s/\.[a-z]*/./;s/[-_]/./g')"
    if [ -z "$sanitized_revision" ] ; then
        package_version="$libc_version"
    else
        package_version="$libc_version-$sanitized_revision"
    fi
    
    data_package="$local_repo/xlocales-$origin-data.$package_version.all.deb"
    gen_package="$local_repo/xlocales-$origin-gen.$package_version.all.deb"

    if [ ! -e "$data_package" ] ; then
        data_stage="stage/xlocales-$origin-data"
        rm -fr "$data_stage"
        mkdir -p "$data_stage/usr/share"
        cp -r "$i18n_dir" "$data_stage/usr/share/"
        mkdir "$data_stage/DEBIAN"
        sed -e "s|@package_version@|$package_version|" \
            -e "s|@package_url@|$package_url|" \
            -e "s|@libc_version@|$libc_version|" \
            -e "s|@origin@|$origin|" \
            -e "s|@maintainer@|$maintainer|" \
            -e "s|@homepage@|https://github.com/macdice/xlocales|" \
            < "debian/xlocales-data/control.in" \
            > "$data_stage/DEBIAN/control"
        dpkg-deb --root-owner-group -b "$data_stage" "$local_repo/xlocales-$origin-data.$package_version.all.deb"
    fi

    if [ ! -e "$gen_package" ] ; then
	    gen_stage="stage/xlocales-$origin-gen"
        rm -fr "$gen_stage"
        mkdir -p "$gen_stage/DEBIAN"
        for file in control postinst postrm ; do
            sed -e "s|@package_version@|$package_version|" \
                -e "s|@package_url@|$package_url|" \
                -e "s|@libc_version@|$libc_version|" \
                -e "s|@origin@|$origin|" \
                -e "s|@maintainer@|$maintainer|" \
                -e "s|@prefix@|/usr|" \
                -e "s|@homepage@|https://github.com/macdice/xlocales|" \
                < "debian/xlocales-gen/$file.in" \
                > "$gen_stage/DEBIAN/$file"
            case "$file" in
                postinst|postrm) chmod +x "$gen_stage/DEBIAN/$file";;
            esac
        done
        dpkg-deb --root-owner-group -b "$gen_stage" "$local_repo/xlocales-$origin-gen.$package_version.all.deb"
    fi
done
