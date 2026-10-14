#!/bin/sh
#
# Fetch locale data from Debian repository.

set -e

. "./xlocales-utils.sh"
. "./xlocales-utils-glibc.sh"

# Print the contents of the directory of releases, filtering out
# unreleased versions (ie sid is not included).
xlocales_fetch_deb_distro_info()
{
    file="cache/$XLOCALES_SOURCE/$XLOCALES_SOURCE.csv"

    xlocales_fetch "$XLOCALES_SOURCE" "$XLOCALES_DEB_INFO_URL" "$file"
    # filter out title line and lines with no release date...
    grep -E '^[0-9][^,]*,[^,]*,[^,]*,[^,]*,[0-9]' "$file"
}

# Convert a version like "13" to a codename like "trixie" as required
# to access package repositories.
xlocales_fetch_deb_codename()
{
    version="$1"

    codename="$(xlocales_fetch_deb_distro_info | \
	            grep "^$version[, ]" | \
	            cut -d, -f3)"

    if [ -z "$codename" ] ; then
	    xlocales_error "could not find codename for $XLOCALES_SOURCE version $version in $XLOCALES_DEB_INFO_URL"
    fi

    echo "$codename"
}

# Extract the value of a given field for a given package from a given package file,
# or an empty string if not found.
xlocales_fetch_deb_package_field()
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
xlocales_fetch_deb_locales_package_info()
{
    version="$1"

    origin="$XLOCALES_SOURCE$version"
    if [ -e "cache/$origin/package.info" ] ; then
        return
    fi
    
    # Figure out if the requested version is in the current or archive
    # repository by scanning "/dists/" (an HTML directory listing).
	codename="$(xlocales_fetch_deb_codename "$version")"    
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
    locales_filename="$(xlocales_fetch_deb_package_field "$packages_file" \
                                                       "locales" \
                                                       "Filename")"
    locales_version="$(xlocales_fetch_deb_package_field "$packages_file" \
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

# Print out a list of version and latest package version according to
# the package repository.
xlocales_fetch_deb_list()
{
    for v in $(xlocales_fetch_deb_distro_info | \
                   sed 's/ LTS,/,/' | \
                   cut -d, -f1 | \
                   sort -Vr) ; do

        # Stop when we get to very old Debian/Ubuntu versions.
	    if ! xlocales_version_le "$XLOCALES_DEB_MIN_VERSION" "$v" ; then
            break
	    fi
        
        xlocales_fetch_deb_locales_package_info "$v"
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

xlocales_fetch_deb()
{
    origin="$1"

    version="$(xlocales_origin_get_version "$origin")"
    
    xlocales_fetch_deb_locales_package_info "$version"
    package_url="$(cat "cache/$origin/package.url")"
    package_file="$(cat "cache/$origin/package.file")"
    package_version="$(cat "cache/$origin/package.version")"
    libc_version="$(echo "$package_version" | sed -n 's|\([0-9]*\.[0-9]*\).*|\1|p')"
    xlocales_fetch "$origin" "$package_url" "cache/$origin/$package_file"

    src="src/$origin"
    rm -fr "$src"
    mkdir -p "$src"

    echo "$package_url" > "$src/package.url"
    echo "$package_file" > "$src/package.file"
    echo "$package_version" > "$src/package.version"
    echo "$libc_version" > "$src/package.libc_version"

    sed -e "s|@prefix@|/usr|g" \
        -e "s|@origin@|$origin|g" \
        -e "s|@package_url@|$package_url|g" \
        -e "s|@package_file@|$package_file|g" \
        -e "s|@package_version@|$package_version|g" \
        -e "s|@libc_version@|$libc_version|g" \
        -e "s|@localedata@|usr/share/i18n|g" \
        < "Makefile.glibc.in" \
        > "$src/Makefile"
    cp xlocales-extract-deb.sh "$src/xlocales-extract.sh"
    cp xlocales-gen.sh "$src/"
    chmod +x "$src"/*.sh
    
    echo "$src"
}

xlocales_fetch_deb_set_source()
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
            ls -1 "./deb_sources"
        else
            xlocales_fetch_deb_set_source "$source"        
            xlocales_fetch_deb_list
        fi
        ;;
    *[0-9]*)
        origin="$1"
        source="$(xlocales_origin_get_source "$origin")"
        xlocales_fetch_deb_set_source "$source"
        xlocales_fetch_deb "$origin" "$2"
        ;;
    *)
        source="$1"
        output_dir="$2"
        xlocales_fetch_deb_set_source "$source"        
        for origin in $(xlocales_fetch_deb_list | cut -d' ' -f1) ; do
            xlocales_fetch_deb "$origin"
        done
        ;;
esac
