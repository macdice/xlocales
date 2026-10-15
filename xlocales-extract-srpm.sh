#!/bin/sh
#
# Unpack a glibc source RPM, apply all maintainer patches in case they
# tweaked either locales or SUPPORTED, and run configure to generate
# the locale data files.
#
# It would be nice to get them ready-made from a binary package like
# glibc-locale-source (sometimes known as glibc-i18n[-data] etc), as
# we can for Debian's "locales", but unfortunately the RHEL-ish
# distros don't include the SUPPORTED file so we have to jump through
# this extra hoop.
#
# XXX Would it be better to use glibc-locale-source for the locale
# data, and just get SUPPORTED from the (patched) glibc source RPM?

set -e

file="$1"

top="$(pwd)"
tmp="$top/rpmbuild_tmp"
spec="$tmp/SPECS/glibc.spec"

rm -fr "$tmp"

for dir in SOURCES BUILD SPECS ; do
    mkdir -p "$tmp/$dir"
done

rpm --quiet -iv --define "_topdir $tmp" --dbpath "$tmp" "$file"

# A chance for some light per-source editing of the spec file...
if [ -e "spec.sed" ] ; then
    sed "$(cat "spec_sed")" < "$spec" > "$spec.tmp"
    mv "$spec.tmp" "$spec"
fi

rpmbuild --quiet -bp --nodeps --quiet \
         --define "_topdir $tmp" \
         "$spec"

src_dir="$(dirname $(find "$tmp" -name "configure" | head -1))"
build="$(dirname "$src_dir")"

echo "Source directory: $src_dir"
echo "Build directory: $build"

mkdir "$build/tmp"
cd "$build/tmp"
"$src_dir"/configure --quiet --prefix=/tmp/dummy --srcdir="$src_dir" --disable-sanity-checks MAKEINFO="$top/xlocales-texinfo.sh"

ln -s "$src_dir/localedata" "$top/localedata"
