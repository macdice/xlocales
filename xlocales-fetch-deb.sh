#!/bin/sh
#
# Fetch locale data from an Debian repository.

. "./xlocales-utils.sh"
. "./xlocales-utils-glibc.sh"

# Print the contents of the directory of releases, filtering out
# unreleased versions (ie sid is not included).
xlocales_get_deb_distro_info()
{
    file="cache/$XLOCALES_SOURCE/$XLOCALES_SOURCE.csv"

    xlocales_fetch "$XLOCALES_SOURCE" "$XLOCALES_DEB_INFO_URL" "$file"
    # filter out title line and lines with no release date...
    grep -E '^[0-9][^,]*,[^,]*,[^,]*,[^,]*,[0-9]' "$file"
}

# Convert a version like "13" to a codename like "trixie" as required
# to access package repositories.
xlocales_get_deb_codename()
{
    version="$1"

    codename="$(xlocales_get_deb_distro_info | \
	            grep "^$version[, ]" | \
	            cut -d, -f3)"

    if [ -z "$codename" ] ; then
	    xlocales_error "could not find codename for $XLOCALES_SOURCE version $version in $XLOCALES_DEB_INFO_URL"
    fi

    echo "$codename"
}

# Extract the value of a given field for a given package from a given package file,
# or an empty string if not found.
xlocales_get_deb_package_field()
{
    packages_file="$1"
    package_name="$2"
    package_field="$3"

	awk "BEGIN { in_package = 0; }
	     /^Package: $package_name\$/ { in_package = 1; }
	     /^$package_field: / { if (in_package) { gsub(/^[^ ]* /, \"\"); print; } }
	     /^ *\$/ { in_package = 0; }" < "$packages_file"
}

# Populate the following files describing the current "locales"
# package, by finding and probing the package repository for the given
# version of Debian (or similar):
#
# cache/ORIGIN/package.url
# cache/ORIGIN/package.version
# cache/ORIGIN/package.file
xlocales_get_deb_locales_package_info()
{
    version="$1"

    origin="$XLOCALES_SOURCE$version"
    if [ -e "cache/$origin/package.info" ] ; then
        return
    fi
    
    # Figure out if the requested version is in the current or archive
    # repository by scanning "/dists/" (an HTML directory listing).
	codename="$(xlocales_get_deb_codename "$version")"    
    repo_dists1_file="cache/$XLOCALES_SOURCE/repo1.html"
    repo_dists2_file="cache/$XLOCALES_SOURCE/repo2.html"
    xlocales_fetch "$origin" "$XLOCALES_DEB_REPO_URL1/dists/" "$repo_dists1_file"
    xlocales_fetch "$origin" "$XLOCALES_DEB_REPO_URL2/dists/" "$repo_dists2_file"
    if grep -q ">$codename" "$repo_dists1_file" ; then
        repo_url="$XLOCALES_DEB_REPO_URL1"
    elif grep -q ">$codename" "$repo_dists2_file" ; then
        repo_url="$XLOCALES_DEB_REPO_URL2"
    else
        xlocales_error "can't find package repository for $XLOCALES_SOURCE $version ($codename); tried $XLOCALES_DEB_REPO_URL1 and $XLOCALES_DEB_REPO_URL2"
    fi

    # Figure out if it's in "binary-all" (missing on Ubuntu and older
    # Debian) or "binary-ARCH".  The locale data files we want are not
    # architecture-specific, so the architecture used here is
    # arbitrary.
    repo_main_file="cache/$origin/repo.main.html"
    xlocales_fetch "$origin" "$repo_url/dists/$codename/main" "$repo_main_file"
    if grep -q 'href="binary-all/"' "$repo_main_file" ; then
        arch="all"
    else
        arch="amd64"
    fi

    # Fetch and decompress file.
    packages_file="cache/$origin/Packages"
    packagesgz_file="$packages_file.gz"
    packagesgz_url="$repo_url/dists/$codename/main/binary-$arch/Packages.gz"
    xlocales_fetch "$origin" "$packagesgz_url" "$packagesgz_file"
    
    xlocales_begin_status "$origin: extracting $packagesgz_file"
    gzip -d < "$packagesgz_file" > "$packages_file.tmp"
    mv "$packages_file.tmp" "$packages_file"
    xlocales_end_status

    # Extract the fields we need.
    xlocales_begin_status "$origin: analysing $packages_file"
    locales_filename="$(xlocales_get_deb_package_field "$packages_file" \
                                                       "locales" \
                                                       "Filename")"
    locales_version="$(xlocales_get_deb_package_field "$packages_file" \
                                                      "locales" \
                                                      "Version")"
    xlocales_end_status

    if [ -z "$locales_filename" -o -z "$locales_version" ] ; then
        xlocales_error "could not find locales package in $packagegz_url"
    fi

    echo "$repo_url/$locales_filename" > "cache/$origin/package.url"
    echo "$locales_version" > "cache/$origin/package.version"
    echo "$(basename "$locales_filename")" > "cache/$origin/package.file"
    touch "cache/$origin/locales.info"
}

# Print out a list of version and latest package URLs according to the
# standard package repository.
xlocales_get_deb_list()
{
    for v in $(xlocales_get_deb_distro_info | \
                   sed 's/ LTS,/,/' | \
                   cut -d, -f1 | \
                   sort -Vr) ; do

        # Stop when we get to very old Debian/Ubuntu versions.
	    if ! xlocales_version_le "$XLOCALES_DEB_MIN_VERSION" "$v" ; then
            break
	    fi
        
        xlocales_get_deb_locales_package_info "$v"
        package_version="$(cat "cache/$origin/package.version")"

        # Also filter out old glibc versions (the package version is
        # assumed to be a glibc version + patch level stuff from the
        # distro maintainers).        
	    if ! xlocales_version_le "$XLOCALES_GLIBC_MIN_VERSION" "$package_version" ; then
	        break
	    fi
        
        echo "$XLOCALES_SOURCE$v (locales $package_version)"
    done   
}

xlocales_get_deb()
{
    origin="$1"

    if [ -z "$output_dir" ] ; then
        output_dir="share"
    fi
    
    version="$(xlocales_origin_get_version "$origin")"
    
    xlocales_get_deb_locales_package_info "$version"
    package_url="$(cat "cache/$origin/package.url")"
    package_file="cache/$origin/$(cat "cache/$origin/package.file")"
    package_version="$(cat "cache/$origin/package.version")"
    xlocales_fetch "$origin" "$package_url" "$package_file"

    src="src/$origin"
    rm -fr "$src"
    mkdir -p "$src"

    xlocales_begin_status "$origin: extracting $package_file"
    ar --output "$src" x "$package_file"
    ( cd "$src" ; tar xf data.tar.* )
    mv "$src/usr/share/i18n/SUPPORTED" "$src/usr/share/i18n/supported"
    xlocales_end_status

    xlocales_begin_status "$origin: extracting charmaps"
    for charmap_gz in $(ls "$src/usr/share/i18n/charmaps") ; do
        gzip -d "$src/usr/share/i18n/charmaps/$charmap_gz"
    done
    xlocales_end_status

    xlocales_stage_glibc "$origin" \
                         "$src/usr/share/i18n" \
                         "$output_dir/i18n.$origin" \
                         "$package_version" \
                         "$package_url"
}
    
xlocales_get_deb_set_source()
{
    source="$1"

    if [ ! -e "./deb_sources/$source" ] ; then
        xlocales_error "Unknown source: $source"
    fi
    . "./deb_sources/$source"
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
            ls "./deb_sources"
        else
            xlocales_get_deb_set_source "$source"        
            xlocales_get_deb_list
        fi
        ;;
    *[0-9]*)
        origin="$1"
        source="$(xlocales_origin_get_source "$origin")"
        xlocales_get_deb_set_source "$source"
        xlocales_get_deb "$origin" "$2"
        ;;
    *)
        source="$1"
        output_dir="$2"
        xlocales_get_deb_set_source "$source"        
        for origin in $(xlocales_get_deb_list | cut -d' ' -f1) ; do
            xlocales_get_deb "$origin" "$output_dir"
        done
        ;;
esac
