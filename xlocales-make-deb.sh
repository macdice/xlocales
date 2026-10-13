#!/bin/sh
#
# Build xlocales-ORIGIN{,-gen,-data} packages for every
# share/i18n.ORIGIN, if it doesn't exist already.
#
# XXX It would be better to use proper Debian tools and make a source
# package!

set -e

. /etc/os-release

host_origin="$ID$VERSION_ID"
local_repo="deb_packages"
debian_arch="$(dpkg --print-architecture)"

case "$1" in
    --precompiled) precompiled_enabled=1 ;;
    '') ;;
    *) echo "Bad argument" >&2 ; exit 1 ;;
esac

mkdir -p "$local_repo"

write_template_file()
{
    sed -e "s|@package_version@|$package_version|g" \
        -e "s|@package_url@|$package_url|g" \
        -e "s|@arch@|$debian_arch|g" \
        -e "s|@libc_version@|$libc_version|g" \
        -e "s|@localedef_version@|$localedef_version|g" \
        -e "s|@origin@|$origin|g" \
        -e "s|@host_origin@|$host_origin|g" \
        -e "s|@maintainer@|$maintainer|g" \
        -e "s|@prefix@|/usr|g" \
        -e "s|@homepage@|https://github.com/macdice/xlocales|g" \
        < "$1" > "$2"
}

for i18n in $(ls share/) ; do
    i18n_dir="share/$i18n"
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
    precomp_package="$local_repo/xlocales-$origin.$package_version.$debian_arch.deb"

    if [ ! -e "$data_package" ] ; then
        data_stage="stage/xlocales-$origin-data"
        rm -fr "$data_stage"
        mkdir -p "$data_stage/usr/share"
        cp -r "$i18n_dir" "$data_stage/usr/share/"
        mkdir "$data_stage/DEBIAN"
        write_template_file "deb/xlocales-data/control.in" \
                            "$data_stage/DEBIAN/control"
        dpkg-deb --root-owner-group -b "$data_stage" "$data_package"
    fi

    if [ ! -e "$gen_package" ] ; then
        gen_stage="stage/xlocales-$origin-gen"
        rm -fr "$gen_stage"
        mkdir -p "$gen_stage/DEBIAN"
        for file in control postinst postrm ; do
            write_template_file "deb/xlocales-gen/$file.in" \
                                "$gen_stage/DEBIAN/$file"
            case "$file" in
                postinst|postrm) chmod +x "$gen_stage/DEBIAN/$file";;
            esac
        done
        dpkg-deb --root-owner-group -b "$gen_stage" "$gen_package"
    fi

    if [ "$precompiled_enabled" = "1" -a ! -e "$precomp_package" ] ; then
        precomp_stage="stage/xlocales-$origin"
        localedef_version="$(localedef --version | head -1 | sed 's/^.* //')"

        src_dir="share/i18n.$origin"
        dst_dir="$precomp_stage/usr/lib/locale.$origin"
        dst_mod_dir="$precomp_stage/usr/lib/locale@$origin"

        #rm -fr "$precomp_stage"
        mkdir -p "$precomp_stage/DEBIAN"
        ./xlocales-gen.sh "$origin" "share" "$precomp_stage/usr/lib"
        write_template_file "deb/xlocales/control.in" \
                            "$precomp_stage/DEBIAN/control"

        dpkg-deb --root-owner-group -b "$precomp_stage" "$precomp_package"
    fi
done
