#!/usr/bin/sh
#
# Compile historical glibc locale data, with any patches that origins
# might have applied.

set -e

verbose="0"
newer_than_host="0"
builddir="build"
srcdir="srcdir"
prefixdir="/usr/locale"
create_origin_modifier="1"
create_version_modifier="1"
version_prefix="glibc"

localedef_version="$(localedef --version | head -1 | sed 's/.* //')"

fetch_file()
{
	origin="$1"
	url="$2"
	destdir="$3"

	printf "$origin/
}

fetch_locales_deb()
{
    origin="$1"
    url="$2"
    package="$(basename $url)"

    mkdir -p "$srcdir/$origin/charmaps"

    # pull down the package if we haven't already
    package_path="$srcdir/$origin/$package"
    if [ ! -f "$package_path" ] ; then
        echo "Fetching $origin package $package from $url"
        curl -f -s -S "$url" > "$package_path.tmp"
        mv "$package_path.tmp" "$package_path"
    fi

    # unpack the interesting contents into fakeroot if we haven't already
    fakeroot_path="$srcdir/$origin/fakeroot"
    if [ ! -e "$fakeroot_path" ] ; then
        rm -fr "$fakeroot_path.tmp"
        mkdir -p "$fakeroot_path.tmp"
        echo "Extracting $origin package $package..."
        (
            cd "$fakeroot_path.tmp"
            ar x "../../../$package_path"
            tar xf data.tar.*
            rm -f data.tar.* debian-binary control.tar.*
        )
        mv "$fakeroot_path.tmp" "$fakeroot_path"
    fi

    # unpack the charsets if we haven't already
    charmaps_path="$srcdir/$origin/charmaps"
    for charmap_gz in $(ls "$fakeroot_path/usr/share/i18n/charmaps") ; do
        charmaps_gz_path="$fakeroot_path/usr/share/i18n/charmaps"
        charmap="$(basename "$charmap_gz" .gz)"
        charmap_path="$charmaps_path/$charmap"
        if [ ! -e "$charmap_path" ] ; then
            echo "Extracting $origin charmap $charmap..."
            gzip -d < "$charmaps_gz_path/$charmap_gz" > "$charmap_path.tmp"
            mv "$charmap_path.tmp" "$charmap_path"
        fi
    done
}

compile_locales()
{
    origin="$1"
    version="$2"

    fakeroot_path="$srcdir/$origin/fakeroot"
    supported_path="$srcdir/$origin/SUPPORTED"

    if [ -e "$fakeroot_path/usr/share/i18n/SUPPORTED" ] ; then
        # debian includes a SUPPORTED file in a convenient format
        cp "$fakeroot_path/usr/share/i18n/SUPPORTED" "$supported_path"
    else
        # otherwise we have to fish it out of glibc sources, which
        # we download and unpack if we haven't already (we don't use
        # localedata from there though, as distros might have patched it)
        glibc_path="$srcdir/glibc-$version"
        if [ ! -e "$glibc_path" ] ; then
            rm -fr "$srcdir/glibc.tmp"
            mkdir -p "$srcdir/glibc.tmp"
            (
                cd "$srcdir/glibc.tmp"
                gnu_glibc_url="https://ftp.gnu.org/gnu/glibc/glibc-$version.tar.xz"
                echo "Fetching $gnu_glibc_url..."
                curl -f -s -S "$gnu_glibc_url" | tar xvJ
            )
            mv "$srcdir/glibc.tmp/glibc-$version" "$glibc_path"
            rm -fr "$srcdir/glibc.tmp"
        fi
        if [ ! -e "$glibc_path" ] ; then
            echo "need $glibc_path"
            exit 1
        fi
        # convert it to debian's easy-to-read format
        grep -v '^#' < "$glibc_path/localedata/SUPPORTED" | grep -v '^SUPPORTED' | sed 's|/| |;s/ \\$//' > "$supported_path.tmp"
        mv "$supported_path.tmp" "$supported_path"
    fi

    mkdir -p "$builddir/$origin/plain"
    mkdir -p "$builddir/$origin/veresion-mod"
    mkdir -p "$builddir/$origin/origin-mod"

    # compile all locales if we haven't already
    while read -r name charmap ; do
      name_base="$(echo "$name" | sed 's/\..*//')"
      name_charmap="$(echo "$name" | sed 's/^[^.]*//')"
      name_charmap_munged="$(echo "$name_charmap" | sed 's/[^.a-zA-Z0-9]//g' | tr '[:upper:]' '[:lower:]')"

      locale_path="$builddir/$origin/plain/$name_base$name_charmap_munged"
      version_mod_path="$builddir/$origin/veresion-mod/$name_base$name_charmap_munged@$version"
      system_mod_path="$builddir/$origin/origin-mod/$name_base$name_charmap_munged@$origin"

      locale_input="$srcdir/$origin/fakeroot/usr/share/i18n/locales/$name_base"
      charmap_input="$srcdir/$origin/charmaps/$charmap"

      if [ ! -e "$locale_path" ] ; then
         echo "Compiling $locale_path..."
         rm -fr "$locale_path.tmp"

         # Append version information to LC_IDENTIFICATION revision using
         # a made-up syntax.  This is useful for code that wants to confirm
         # that glibc hasn't silently truncated a modifier used when opening
         # the locale, which is otherwise undetectable via POSIX APIs.
         locale_input_rev="$locale_input.rev"
         sed "s/^\(revision *\".*\)\"$/\1; origin=$origin; localedef=$localedef_version; localedata=$version\"/" < $locale_input > $locale_input_rev

         I18NPATH="$srcdir/$origin/fakeroot/usr/share/i18n" localedef -f "$charmap_input" -i "$locale_input_rev" "$locale_path.tmp"
         mv "$locale_path.tmp" "$locale_path"
         rm -fr "$version_mod_path" "$system_mod_path"
         ln -s "../plain/$name_base$name_charmap_munged" "$version_mod_path"
         ln -s "../plain/$name_base$name_charmap_munged" "$system_mod_path"
      fi
    done < "$supported_path"
}

import_locales_deb()
{
    origin="$1"
    url="$2"
    version="$3"

    echo "Importing locales from $origin..."

    fetch_locales_deb "$origin" "$url"
    compile_locales "$origin" "$version"
}

# Handles Debian and Ubuntu
import_locales_debianlike_latest()
{
    origin="$1"
    codename="$2"
    repo_base_url="$3"

    package_list="$srcdir/$origin/Packages"

    # In older Debian and all Ubuntu there is no "binary-all" so we have to
    # look in "binary-amd64"
    if curl -f -s -S "$repo_base_url/dists/$codename/main" | grep "binary-all" > /dev/null ; then
        arch="all"
    else
        arch="amd64"
    fi

    mkdir -p "$(dirname $package_list)"
    if [ ! -e "$package_list" ] ; then
        url="$repo_base_url/dists/$codename/main/binary-$arch/Packages.gz"
        echo "Fetching $url"
        curl -f -s -S "$url" | gzip -d > "$package_list.tmp"
        mv "$package_list.tmp" "$package_list"
    fi

    package_info="$srcdir/$origin/locales.package"
    if [ ! -e "$package_info" ] ; then
        awk 'BEGIN { in_zone = 0; } /^Package: locales$/ { in_zone = 1; print; } /^ *$/ { in_zone = 0; } in_zone { print; }' "$package_list" > "$package_info.tmp"
        mv "$package_info.tmp" "$package_info"
    fi

    package_version="$( grep "Version: " "$package_info" | sed 's/^[^:]*: //')"
    package_filename="$( grep "Filename: " "$package_info" | sed 's/^[^:]*: //')"
    package_url="$repo_base_url/$package_filename"

    # Have glibc major.minor-distro-suffixes, want glibc major.minor
    # because that is what PostgreSQL captures.  Of course those patch level
    # changes could be material changes...
    version="$( echo $package_version | sed 's/-.*$//' )"

    import_locales_deb "$origin" "$package_url" "$version"
}

import_locales_debian_latest()
{
    origin="$1"
    codename="$2"

    # figure out if it's in current or archive repos
    if curl -f -s -S "https://archive.debian.org/debian/dists/" | grep ">$codename/" > /dev/null ; then
        repo_base_url="https://archive.debian.org/debian"
    else
        repo_base_url="http://ftp.debian.org/debian"
    fi

    import_locales_debianlike_latest "$origin" "$codename" "$repo_base_url"
}

import_locales_ubuntu_latest()
{
    origin="$1"
    codename="$2"

    repo_base_url="https://archive.ubuntu.com/ubuntu"

    import_locales_debianlike_latest "$origin" "$codename" "$repo_base_url"
}

fetch_locales_rpm()
{
    origin="$1"
    glibc_url="$2"
    glibc_package="$(basename $glibc_url)"
    locale_url="$3"
    locale_package="$(basename $locale_url)"
    version="$4"

    mkdir -p "$srcdir/$origin/charmaps"

    # pull down the packages if we haven't already
    glibc_package_path="$srcdir/$origin/$glibc_package"
    if [ ! -f "$glibc_package_path" ] ; then
        echo "Fetching $origin package $glibc_package from $glibc_url"
        curl -f -s -S "$glibc_url" > "$glibc_package_path.tmp"
        mv "$glibc_package_path.tmp" "$glibc_package_path"
    fi
    locale_package_path="$srcdir/$origin/$locale_package"
    if [ ! -f "$locale_package_path" ] ; then
        echo "Fetching $origin package $locale_package from $locale_url"
        curl -f -s -S "$locale_url" > "$locale_package_path.tmp"
        mv "$locale_package_path.tmp" "$locale_package_path"
    fi

    # unpack the interesting contents into fakeroot if we haven't already
    fakeroot_path="$srcdir/$origin/fakeroot"
    if [ ! -e "$fakeroot_path" ] ; then
        rm -fr "$fakeroot_path.tmp"
        mkdir -p "$fakeroot_path.tmp"
        echo "Extracting $origin package..."
        (
            cd "$fakeroot_path.tmp"
            rpm2cpio "../../../$locale_package_path" | cpio -idmv
            mkdir "glibc-source" && cd "glibc-source"
            rpm2cpio "../../../../$glibc_package_path" | cpio -idmv
            # up to rocky8 they had SUPPORTED in the source package, so
            # use that just in case it differs from upstream... make it
            # look like Debian
            if [ -e SUPPORTED ] ; then
                grep -v '^#' < SUPPORTED | grep -v '^SUPPORTED' | sed 's|/| |;s/ \\$//' > ../usr/share/i18n/SUPPORTED
            fi
        )
        mv "$fakeroot_path.tmp" "$fakeroot_path"
    fi

    # unpack the charsets if we haven't already
    charmaps_path="$srcdir/$origin/charmaps"
    for charmap_gz in $(ls "$fakeroot_path/usr/share/i18n/charmaps") ; do
        charmaps_gz_path="$fakeroot_path/usr/share/i18n/charmaps"
        charmap="$(basename "$charmap_gz" .gz)"
        charmap_path="$charmaps_path/$charmap"
        if [ ! -e "$charmap_path" ] ; then
            echo "Extracting $origin charmap $charmap..."
            gzip -d < "$charmaps_gz_path/$charmap_gz" > "$charmap_path.tmp"
            mv "$charmap_path.tmp" "$charmap_path"
        fi
    done
}

import_locales_rpm()
{
    origin="$1"
    glibc_url="$2"
    locale_url="$3"
    locale_version="$4"

    echo "Importing locales from $origin..."

    fetch_locales_rpm "$origin" "$glibc_url" "$locale_url" "$locale_version"
    compile_locales "$origin" "$locale_version"
}

import_locales_rocky_latest()
{
    origin="$1"

    major_version="$(echo "$origin" | sed 's/^[^0-9]*//')"
    case "$major_version" in
      "8") locale_base_url="https://download.rockylinux.org/pub/rocky/$major_version/BaseOS/x86_64/kickstart/Packages/g/";;
      *) # gotta find the latest minor version first
         major_minor_version="$(curl -f -s -S "https://dl.rockylinux.org/vault/rocky/" | grep "href=\"$major_version." | sed 's/.*href="//;s/".*//' | tail -1)"
         locale_base_url="https://dl.rockylinux.org/vault/rocky/$major_minor_version/AppStream/aarch64/os/Packages/g/";;
    esac

    locale_filename="$(curl -f -s -S "$locale_base_url" | grep '"glibc-locale-source' | sed 's/.*href="//;s/".*//' | tail -1)"
    locale_url="$locale_base_url/$locale_filename"
    locale_version="$( echo $locale_filename | sed 's/^glibc-locale-source-//;s/-.*$//' )"

    # also need glibc source package, because that is where they ship SUPPORTED
    # in versions < 9
    glibc_base_url="https://dl.rockylinux.org/pub/rocky/$major_version/BaseOS/source/tree/Packages/g/"
    glibc_filename="$(curl -f -s -S "$glibc_base_url" | grep '"glibc-' | sed 's/.*href="//;s/".*//' | tail -1)"
    glibc_url="$glibc_base_url/$glibc_filename"

    import_locales_rpm "$origin" "$glibc_url" "$locale_url" "$locale_version"
}

case $1 in
  rocky10) import_locales_rocky_latest "$1";;
  rocky9) import_locales_rocky_latest "$1";;
  rocky8) import_locales_rocky_latest "$1";;

  debian14) import_locales_debian_latest "$1" "forky";;
  debian13) import_locales_debian_latest "$1" "trixie";;
  debian12) import_locales_debian_latest "$1" "bookworm";;
  debian11) import_locales_debian_latest "$1" "bullseye";;
  debian10) import_locales_debian_latest "$1" "buster";;
  # Debian 9's fail with recent localedef:
  # .../iso14651_t1_common:7468: [error] symbol `(null)' not defined

  ubuntu26) import_locales_ubuntu_latest "$1" "resolute";;
  ubuntu24) import_locales_ubuntu_latest "$1" "noble";;
  ubuntu22) import_locales_ubuntu_latest "$1" "jammy";;
  ubuntu20) import_locales_ubuntu_latest "$1" "focal";;
  ubuntu18) import_locales_ubuntu_latest "$1" "bionic";;
  # Ubuntu 16's fail with recent localedef:
  # [error] LC_IDENTIFICATION: unknown standard `i18n:2000' for category `LC_CTYPE'
  # This seems to be knowledge baked into localedef, not the data files, so I
  # guess you'd need to patch it to go back further...

  *) echo "Usage: $0 <origin>, where origin is in:
  debian10..14, ubuntu18..26, rocky8..10"; exit 1;;
esac
