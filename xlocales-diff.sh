#!/bin/sh

origin1="$1"
origin2="$2"

tmp="tmp.$$"
trap "rm -fr $tmp" EXIT

if [ ! -e "share/i18n.$origin1/.xlocales.libc_version" ] ; then
	cat <<EOF >&2
Usage:

    $0 ORIGIN
    $0 ORIGIN1 ORIGIN2

Compares the contents of share/i18n.ORIGIN1 and share/i18n.ORIGIN2.
If only one ORIGIN is given, it is compared against share/i18n.glibcX.Y,
being the upstream glibc version so that patches applied by distributions
can be seen.

The origins must already have been fetched with xlocale-fetch-XXX.sh,
except that glibcX.Y is automatically fetched if necessary with the single
argument variant.
EOF
    exit 1
fi

# Default to diffing against the upstream glibc version if only one origin is
# provided.  Make sure we actually have it.
if [ -z "$origin2" ] ; then
    libc_version="$(cat "share/i18n.$origin1/.xlocales.libc_version")"
    origin2="$origin1"
    origin1="glibc$libc_version"
    if [ ! -e "share/i18n.$origin1/.xlocales.libc_version" ] ; then
        ./xlocales-fetch-glibc.sh "$origin1"
    fi
fi

mkdir -p "$tmp/$origin1/charmaps"
mkdir -p "$tmp/$origin1/locales"
mkdir -p "$tmp/$origin2/charmaps"
mkdir -p "$tmp/$origin2/locales"

i18n1="share/i18n.$origin1"
i18n2="share/i18n.$origin2"

diff -u "$i18n1/.xlocales.libc_version" "$i18n2/.xlocales.libc_version"
diff -u "$i18n1/.xlocales.unicode_version" "$i18n2/.xlocales.unicode_version"

# Strip the modifier columns and ignore reorderings in xlocales.supported
cut -d' ' -f1-3 < "$i18n1/xlocales.supported" | sort > "$tmp/$origin1/xlocales.supported"
cut -d' ' -f1-3 < "$i18n2/xlocales.supported" | sort > "$tmp/$origin2/xlocales.supported"
diff -u "$tmp/$origin1/xlocales.supported" "$tmp/$origin2/xlocales.supported"

ls "$i18n1/charmaps" | sort > "$tmp/$origin1/charmaps/list"
ls "$i18n2/charmaps" | sort > "$tmp/$origin2/charmaps/list"
diff -u "$tmp/$origin1/charmaps/list" "$tmp/$origin2/charmaps/list"
ls "$i18n1/locales" | sort > "$tmp/$origin1/locales/list"
ls "$i18n2/locales" | sort > "$tmp/$origin2/locales/list"
diff -u "$tmp/$origin1/locales/list" "$tmp/$origin2/locales/list"

for charmap in $(ls "$i18n1/charmaps") ; do
    if [ -e "$i18n2/charmaps" ] ; then
        diff -u "$i18n1/charmaps/$charmap" "$i18n2/charmaps/$charmap"
    fi
done

for locale in $(ls "$i18n1/locales") ; do
    if [ -e "$i18n2/locales" ] ; then
        # Remove the "revision" patch applies while fetching,
        # because that always differs.
        sed 's|^revision *"\([^;]*\);[^"]*".*$|revision "\1"|' \
            < "$i18n1/locales/$locale" \
            > "$tmp/$origin1/locales/$locale"
        sed 's|^revision *"\([^;]*\);[^"]*".*$|revision "\1"|' \
            < "$i18n2/locales/$locale" \
            > "$tmp/$origin2/locales/$locale"
        diff -u "$tmp/$origin1/locales/$locale" "$tmp/$origin2/locales/$locale"
    fi
done
