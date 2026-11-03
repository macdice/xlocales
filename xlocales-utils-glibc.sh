# Common code for dealing with glibc distributions.

XLOCALES_GLIBC_MIN_VERSION="2.27"

xlocales_glibc_x_dot_y()
{
    echo "$1" | sed 's|^\([0-9]*\.[0-9]*\).*$|\1|'
}

# Append LC_IDENDIFICATION revision information while copying locales
# and charmaps, and generate the xlocales.supported file.
xlocales_stage_glibc()
{
    origin="$1"
    src_i18n="$2"
    dst_i18n="$3"
    src_version="$4"
    src_url="$5"

    libc_version="$(xlocales_glibc_x_dot_y "$src_version")"
    unicode_version="$(sed -n 's/^revision *\"\(.*\)\"$/\1/p' \
                       < "$src_i18n/locales/i18n_ctype" | \
                       head -1)"

    xlocales_begin_status "$origin: writing $dst_i18n/charmaps"
    mkdir -p "$dst_i18n/charmaps"
    for charmap in $(ls "$src_i18n/charmaps") ; do
        cp "$src_i18n/charmaps/$charmap" "$dst_i18n/charmaps/$charmap"
    done
    xlocales_end_status
    
    xlocales_begin_status "$origin: writing $dst_i18n/locales"
    mkdir -p "$dst_i18n/locales"
    for locale_src in $(ls "$src_i18n/locales") ; do
        sed "s/^\(revision *\".*\)\"$/\1; origin=$origin; unicode=$unicode_version; localedata=$libc_version\"/" \
        < "$src_i18n/locales/$locale_src" \
        > "$dst_i18n/locales/$locale_src"
    done
    xlocales_end_status

    if [ ! -e "$src_i18n/supported" ] ; then
        xlocales_begin_status "$origin: generating $src_i18n/supported"
        # Convert upstream SUPPORTED file to Debian format, unless
        # we got this from a distro that already ships it that way.
        grep '/' "$src_i18n/SUPPORTED" | \
        sed 's/ .*$//;s|/| |' > "$src_i18n/supported"
        xlocales_end_status
    fi

    xlocales_begin_status "$origin: generating $dst_i18n/xlocales.supported"
    while read -r locale charmap ; do
        # Now convert to "locale_normalized locale_src charmap modifiers...".
        locale_src="$(echo "$locale" | cut -d. -f1)"
        locale_codeset_normalized="$(echo "$locale" | \
                                     sed -e 's/^[^.]*//' \
                                         -e 's/[^.a-zA-Z0-9]//g' \
                                         -e 's/.*/\L&/')"
        locale_normalized="$locale_src$locale_codeset_normalized"
        echo "$locale_normalized $locale_src $charmap $origin libc$libc_version"
    done \
        < "$src_i18n/supported" \
        > "$dst_i18n/xlocales.supported"
    xlocales_end_status

    echo "$unicode_version" > "$dst_i18n/.xlocales.unicode_version"
    echo "$libc_version" > "$dst_i18n/.xlocales.libc_version"
    echo "$src_version" > "$dst_i18n/.xlocales.source_version"
    echo "$src_url" > "$dst_i18n/.xlocales.source_url"
    echo "$origin" > "$dst_i18n/.xlocales.origin"

    echo "$dst_i18n"
}
