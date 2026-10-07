# After running "fetch", $xlocales_src/$origin should contain:
#
# charmaps
# locales
# SUPPORTED (glibc format) or supported (Debian format)
#
# libc.version
# package.url
# package.version
#
# On exist, $xlocales_stage/$origin contains staged packages.
xlocales_glibc_stage()
{
    origin="$1"

    src="$xlocales_src/$origin"
    package_url="$(cat "$src/package.url")"
    package_version="$(cat "$src/package.version")"
    libc_version="$(cat "$src/libc.version")"

    source="$(xlocales_origin_get_source "$origin")"
    unicode_version="$(sed -n 's/^revision *\"\(.*\)\"$/\1/p' \
                       < "$src/locales/i18n_ctype" | \
                       head -1)"    
    stage="$xlocales_stage/$origin"
    xlocales_i18n="xlocales/$xlocales_prefix/share/i18n@$origin"
        
    xlocales_begin_status "$origin: staging $xlocales_i18n/charmaps"
    mkdir -p "$stage/$xlocales_i18n/charmaps"
    for charmap in $(ls "$src/charmaps") ; do
        ln -f "$src/charmaps/$charmap" "$stage/$xlocales_i18n/charmaps/$charmap"
    done
    xlocales_end_status
    
    xlocales_begin_status "$origin: installing $xlocales_i18n/locales"
    mkdir -p "$stage/$xlocales_i18n/locales"
    for locale_src in $(ls "$src/locales") ; do
        sed "s/^\(revision *\".*\)\"$/\1; origin=$origin; unicode=$unicode_version; localedata=$libc_version\"/" \
        < "$src/locales/$locale_src" \
        > "$stage/$xlocales_i18n/locales/$locale_src"
    done
    xlocales_end_status

    xlocales_begin_status "$origin: generating $src/supported"
    if [ ! -e "$src/supported" ] ; then
        # Convert upstream SUPPORTED file to Debian format, unless
        # we got this from a distro that already ships it that way.
        grep '/' "$src/SUPPORTED" | \
        sed 's/ .*$//;s|/| |' > "$src/supported"
    fi
    xlocales_end_status

    xlocales_begin_status "$origin: generating $xlocales_i18n/xlocales.supported"
    while read -r locale charmap ; do
        # Now convert to "locale_normalized locale_src charmap".
        #
        # XXX This is far too slow
        locale_src="$(echo "$locale" | cut -d. -f1)"
        locale_codeset_normalized="$(echo "$locale" | \
                                     sed -e 's/^[^.]*//' \
                                         -e 's/[^.a-zA-Z0-9]//g' \
                                         -e 's/.*/\L&/')"
        locale_normalized="$locale_src$locale_codeset_normalized"
        echo "$locale_normalized $locale_src $charmap"
    done \
        < "$src/supported" \
        > "$stage/$xlocales_i18n/xlocales.supported"
    xlocales_end_status

    xlocales_begin_status "$origin: staging $xlocales_i18n scripts"
    for file in "README" \
                "compile-locales.sh" \
                "remove-locales.sh" \
                "select-modifier.sh" ; do
        dst="$(echo "$file" | sed 's/(locales|modifier)/$origin/')"
        sed -e "s|@source@|$source|g" \
            -e "s|@origin@|$origin|g" \
            -e "s|@libc_version@|$libc_version|g" \
            -e "s|@unicode_version@|$unicode_version|g" \
            -e "s|@package_version@|$package_version|g" \
            -e "s|@package_url@|$package_url|g" \
            -e "s|@prefix@|$xlocales_prefix|g" \
            -e "s|@system_locale_path@|$xlocales_system_locales|g" \
             < "glibc/$file.in" \
             > "$stage/$xlocales_i18n/$file"
        case "$file" in
            *.sh) chmod +x "$stage/$xlocales_i18n/$dst";;
        esac
    done
    xlocales_end_status
    
    touch "$src/xlocales.configured"
}
