#!/bin/sh
#
# Unpack a .deb binary package (ie "locales").

file="$1"

for member in $(ar xv "$file" | sed 's|^x[ -]*||') ; do
    case "$member" in
        *data.tar.*) tarball="$member";;
    esac
done
if [ -z "$tarball" ] ; then
    echo "could not find data.tar.* in $file" >&2
    exit 1
fi
tar xf "$tarball"

ln -s "usr/share/i18n" "localedata"
