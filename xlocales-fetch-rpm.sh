#!/bin/sh
#
# Fetch locale data from an RPM repository.

set -e

. "./xlocales-utils.sh"
. "./xlocales-utils-glibc.sh"

xlocales_get_rpm_url()
{
    repo_url="$1"
    version="$2"
    suffix="$3"

    if [ -n "$suffix" ] ; then
        suffix="/$suffix"
    fi

    echo "$(echo "$repo_url" | sed "s|@VERSION@|$version|")$suffix"
}

xxxcat()
{
    case "$1" in
        *.gz) zcat "$1";;
        *.zst) zstdcat "$1";;
        *.bz2) bzcat "$1";;
        *.xz) xzcat "$1";;
        *) xlocate_error "I don't know how to decompress $1";;
    esac
}
xlocales_get_rpm_probe_repo()
{
    version="$1"

    origin="$XLOCALES_SOURCE$version"

    mkdir -p "cache/$origin"

    if [ -n "$XLOCALES_RPM_REPO_META_URL" ] ; then
        metalink_file="cache/$origin/metalink.xml"
        xlocales_fetch "$origin" \
                       "$(xlocales_get_rpm_url "$XLOCALES_RPM_REPO_META_URL" \
                                               "$version" \
                                               "")" \
                       "$metalink_file"
        XLOCALES_RPM_REPO_URL1="$(sed -n 's|^.*>\(https:[^>]*\)/repodata/repomd\.xml</url.*$|\1|p' < "$metalink_file" | head -1)"
        XLOCALES_RPM_REPO_URL2="$(sed -n 's|^.*>\(https:[^>]*\)/repodata/repomd\.xml</url.*$|\1|p' < "$metalink_file" | head -2 | tail -1)"
        XLOCALES_RPM_REPO_URL3="$(sed -n 's|^.*>\(https:[^>]*\)/repodata/repomd\.xml</url.*$|\1|p' < "$metalink_file" | head -3 | tail -1)"
    fi

    #primary_file="cache/$origin/primary.xml.gz"
    repomd_file="cache/$origin/repomd.xml"

    if [ -e "cache/$origin/package.file" ] ; then
        return
    elif [ -e "$repomd_file.neg" ] ; then
        false
        return
    fi

    # We take /usr/share/i18n/{locales,charmaps} from a binary package
    # so that we now that all patches were already applied and we
    # don't have to redo any of that.
    for repo_url in "$XLOCALES_RPM_REPO_URL1" \
                    "$XLOCALES_RPM_REPO_URL2" \
                    "$XLOCALES_RPM_REPO_URL3" \
                    "" ; do

        if [ -z "$repo_url" ] ; then
            # Reached end of URL list and saw only 404
            touch "$repomd_file.neg"
            false
            return
        fi

        repomd_url="$(xlocales_get_rpm_url "$repo_url" \
                                           "$version" \
                                           "repodata/repomd.xml")"

        xlocales_begin_status "$origin: fetching $repomd_url"
        echo "$repomd_url" > "$repomd_file.log"
        curl -f -s -S -o "$repomd_file" "$repomd_url" 2>> "$repomd_file.log" || true
        xlocales_end_status

        if [ -e "$repomd_file" ] ; then
            break
        elif grep -q "error: 404" "$repomd_file.log" ; then
            continue
        fi

        xlocales_error "Fetching $repomd_url failed: $(cat "$repomd_file.log")"
    done

    primary_location="$(sed -n 's|^.*<location href="\([^"]*\.xml\.[^"]*\)".*|\1|p' \
                            "$repomd_file" | \
                            head -1)"
    if [ -z "$primary_location" ] ; then
        xlocales_error "could not find primary location in $repomd_file, fetched from $repomd_url"
    fi
        
    primary_url="$(xlocales_get_rpm_url "$repo_url" "$version" "$primary_location")"
    primary_file="cache/$origin/$(echo "$primary_location" | sed 's|^.*\.|primary.xml.|')"
    xlocales_fetch "$origin" "$primary_url" "$primary_file"

    package_location="$(xxxcat "$primary_file" | sed -n "s|^.* href=\"\(.*/${XLOCALES_RPM_PACKAGE}-[^\"]*\)\".*$|\1|p" | sort -rV | head -1)"
    if [ -z "$package_location" ] ; then
        xlocales_error "could not find $XLOCALES_RPM_PACKAGE in $primary_file, from $primary_url"
    fi
    
    package_url="$(xlocales_get_rpm_url "$repo_url" "$version" "$package_location")"
    package_file="$(basename "$package_location")"
    package_version="$(echo "$package_file" | sed "s|^${XLOCALES_RPM_PACKAGE}-||;s|\.[_0-9a-z]*\.rpm$||")"
    echo "$package_url" > "cache/$origin/package.url"
    echo "$package_file" > "cache/$origin/package.file"
    echo "$package_version" > "cache/$origin/package.version"
}

xlocales_get_rpm_next_version()
{
    version="$1"

    case "$version" in
        *.*) 
            major_version="$(echo "$version" | cut -d. -f1)" 
            minor_version="$(echo "$version" | cut -d. -f2)"
            echo "$major_version.$((minor_version + 1))"
            ;;
        *)
            echo "$((version + 1))"
            ;;
    esac
}

xlocales_get_rpm_maybe_next_major_version()
{
    version="$1"

    case "$version" in
        *.0)
            echo ""
            ;;
        *.*)
            major_version="$(echo "$version" | cut -d. -f1)"
            echo "$((major_version + 1)).0"
            ;;
        *)
            echo ""
            ;;
    esac
}

xlocales_get_rpm_list()
{
    mkdir -p "cache/$XLOCALES_SOURCE"

    if [ -n "$XLOCALES_RPM_REPO_MIRROR_FILE" ] ; then
        # XXX This was intended to support xlocales-get-amzn.sh but
        # doesn't actually work from the public internet...
        while read -r version repo_mirror_url ; do
            repo_url_file="cache/$XLOCALES_SOURCE/repo_url.$version"
            xlocales_fetch "$XLOCALES_SOURCE" "$repo_mirror_url" "$repo_url_file"
            XLOCALES_RPM_REPO_URL1="$(cat "$repo_url_file")"
            if xlocales_get_rpm_probe_repo "$version" ; then
                origin="$XLOCALES_SOURCE$version"
                package_version="$(cat "cache/$origin/package.version")"
	            if xlocales_version_le "$XLOCALES_GLIBC_MIN_VERSION" \
                     "$package_version" ; then
                    echo "$origin ($XLOCALES_RPM_PACKAGE $package_version)"
                fi
            fi
        done < "$XLOCALES_RPM_REPO_MIRROR_FILE"
    elif [ -z "$XLOCALES_RPM_REPO_DIR_URL1" ] ; then
        # Cycle through sequential major.minor or major (depending on
        # whether XLOCALES_RPM_REPO_MIRROR_FILE has a dot in it),
        # using 404 to discover the end.  This works for RHEL-style
        # version numbers.
        version="$XLOCALES_RPM_MIN_VERSION"
        while [ -n "$version" ] ; do
            if xlocales_get_rpm_probe_repo "$version" ; then
                origin="$XLOCALES_SOURCE$version"
                package_version="$(cat "cache/$origin/package.version")"
	            if xlocales_version_le "$XLOCALES_GLIBC_MIN_VERSION" \
                     "$package_version" ; then
                    echo "$origin ($XLOCALES_RPM_PACKAGE $package_version)"
                fi
                version="$(xlocales_get_rpm_next_version "$version")"
            else
                version="$(xlocales_get_rpm_maybe_next_major_version "$version")"
            fi
        done
    else
        # XXX Not used yet, just an idea...
        #
        # Some repos are on a webserver with directory listing
        # enabled, or there is a web page somewhere else that lists
        # them, so we have to schlep the valid versions out of HTML.
        # XLOCALES_RPM_REPO_DIR_REGEX must be set to an expression
        # with a single capture, that discards everything else on a
        # line.  For example: '^.*<a href="\([^"]*\)/".*$'
        #
        # The variables XLOCALES_RPM_REPO_URL1..3 are then used to try
        # to find to find the repomd.xml file, with @VERSION@
        # replaced.
        dir_number=1
        for repo_dir_url in "$XLOCALES_RPM_REPO_DIR_URL1" \
                            "$XLOCALES_RPM_REPO_DIR_URL2" \
                            "$XLOCALES_RPM_REPO_DIR_URL3" ; do
            if [ -z "$repo_dir_url" ] ; then
                break
            fi
            repo_dir_file="cache/$XLOCALES_SOURCE/repo_dir$dir_number.html"
            xlocale_fetch "$XLOCALES_SOURCE" "$repo_dir_url" "$repo_dir_file"
            for version in $(sed -n "s|$XLOCALES_RPM_REPO_DIR_REGEX|\1|p" \
                                 "$repo_dir_file") ; do
                if xlocales_get_rpm_probe_repo "$version" ; then
                    origin="$XLOCALES_SOURCE$version"
                    package_version="$(cat "cache/$origin/package.version")"
	                if xlocales_version_le "$XLOCALES_GLIBC_MIN_VERSION" \
                         "$package_version" ; then
                        echo "$origin ($XLOCALES_RPM_PACKAGE $package_version)"
	                fi
                fi
            done
        done
    fi
}

xlocales_get_rpm()
{
    origin="$1"
    output_dir="$2"

    if [ -z "$output_dir" ] ; then
        output_dir="share"
    fi
    
    version="$(xlocales_origin_get_version "$origin")"
    
    xlocales_get_rpm_probe_repo "$version"
    package_url="$(cat "cache/$origin/package.url")"
    package_file="cache/$origin/$(cat "cache/$origin/package.file")"
    package_version="$(cat "cache/$origin/package.version")"
    xlocales_fetch "$origin" "$package_url" "$package_file"

    src="src/$origin"
    rm -fr "$src"
    mkdir -p "$src"

    xlocales_begin_status "$origin: extracting $package_file"
    ( cd "$src" && rpm2cpio "../../$package_file" | cpio -idm --quiet )
    xlocales_end_status

    xlocales_begin_status "$origin: extracting charmaps"
    for charmap_gz in $(ls "$src/usr/share/i18n/charmaps") ; do
        gzip -d "$src/usr/share/i18n/charmaps/$charmap_gz"
    done
    xlocales_end_status

    # RHEL-ish systems don't ship the list of locale/charmap
    # combinations they generate, so fish it out of upstream glibc.
    # Try to share download cache with the actual glibc script, but
    # don't build/install anything...
    libc_version="$(echo "$package_version" | sed 's|^\([0-9]*\.[0-9]*\).*$|\1|')"
    tarball="glibc-$libc_version.tar.xz"
    xlocales_fetch "$origin" \
                   "https://ftp.gnu.org/gnu/glibc/$tarball" \
                   "cache/glibc$libc_version/$tarball"
    tar xf \
        "cache/glibc$libc_version/$tarball" \
        --strip-components=2 \
        -C "$src/usr/share/i18n" \
        "glibc-$libc_version/localedata/SUPPORTED"
    
    xlocales_stage_glibc "$origin" \
                         "$src/usr/share/i18n" \
                         "$output_dir/i18n.$origin" \
                         "$package_version" \
                         "$package_url"
}

xlocales_get_rpm_set_source()
{
    source="$1"

    if [ ! -e "./rpm_sources/$source" ] ; then
        xlocales_error "Unknown RPM source: $source"
    fi
    . "./rpm_sources/$source"
}

case "$1" in
    ''|help|-h|--help)
        cat <<EOF >&2
Usage:
  $0 --list                list available sources (ie OSes)
  $0 --list SOURCE         list available origins (ie versions) from SOURCE
  $0 SOURCE [output_dir]   fetch locale data for all versions of SOURCE
  $0 ORIGIN [output_dir]   fetch locale data for one version
EOF
        exit 1
        ;;
    -l|--list)
        source="$2"
        if [ -z "$source" ] ; then
            ls "./rpm_sources"
        else
            xlocales_get_rpm_set_source "$source"        
            xlocales_get_rpm_list
        fi
        ;;
    *[0-9]*)
        origin="$1"
        source="$(xlocales_origin_get_source "$origin")"
        xlocales_get_rpm_set_source "$source"
        xlocales_get_rpm "$origin" "$2"
        ;;
    *)
        source="$1"
        output_dir="$2"
        xlocales_get_rpm_set_source "$source"        
        for origin in $(xlocales_get_rpm_list | cut -d' ' -f1) ; do
            xlocales_get_rpm "$origin" "$output_dir"
        done
        ;;
esac
