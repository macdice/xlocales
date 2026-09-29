xlocales_debian_min="10"

xlocales_debian_desc()
{
    echo "Debian glibc locales packages"
}

# == begin shared debian/ubuntu routines ==

debian_distro_info_data_for_source()
{
    source="$1"

    url="https://debian.pages.debian.net/distro-info-data/$source.csv"
    file="$xlocales_cache/$source/$source.csv"

    fetch_src "$url" "$file"
    # filter out title line and lines with no release date...
    grep -E '^[0-9][^,]*,[^,]*,[^,]*,[^,]*,[0-9]' "$file"
}

debian_codename_for_origin()
{
    origin="$1"

    source="$(origin_get_source "$origin")"
    version="$(origin_get_version "$origin")"
    codename="$(debian_distro_info_data_for_source "$source" | \
    	      grep "^$version[, ]" | \
              cut -d, -f3)"    
    if [ -z "$codename" ] ; then
	echo "debian_codename_for_origin: could not find codename for source=$source, version=$version" >&2
	exit 1
    fi

    echo "$codename"
}

debian_cat_packages_file()
{
    repo_base_url="$1"
    codename="$2"

    fetch_src "https://old-releases.ubuntu.com/ubuntu/dists/" \
	      "$xlocales_cache/ubuntu/old-releases.html"
    
    if curl -f -s -S "$repo_base_url/dists/$codename/main" | grep "binary-all" > /dev/null ; then
	# modern Debian has locales in "binary-all"
        arch="all"
    else
        # older Debian and all Ubuntu have a copy for each
        # architecture, so just pick one
        arch="amd64"
    fi

    url="$repo_base_url/dists/$codename/main/binary-$arch/Packages.gz"
    curl -f -s -S "$url" | gzip -d
}

debian_get_package_field()
{
    origin="$1"
    package_name="$2"
    package_field="$3"

    packages_file="$xlocales_cache/$origin/Packages"
    cache_file="$xlocales_cache/$origin/$package_name.$package_field"

    if [ ! -e "$cache_file" ] ; then
        awk "BEGIN { in_package = 0; }
             /^Package: $package_name\$/ { in_package = 1; }
             /^$package_field: / { if (in_package) { gsub(/^[^ ]* /, \"\"); print; } }
             /^ *\$/ { in_package = 0; }" < "$packages_file" > "$cache_file.tmp"
	mv "$cache_file.tmp" "$cache_file"
    fi

    cat "$cache_file"
}

debian_get_package_url()
{
    origin="$1"
    package_name="$2"

    base_url="$(cat "$xlocales_cache/$origin/Packages.base_url")"
    filename="$(debian_get_package_field "$origin" "locales" "Filename")"

    echo "$base_url/$filename"
}

# == end shared debian/ubuntu routines ==

debian_fetch_packages_file()
{
    origin="$1"

    packages_file="$xlocales_cache/$origin/Packages"

    if [ ! -e "$packages_file" ] ; then
	mkdir -p "$xlocales_cache/$origin"
	codename="$(debian_codename_for_origin "$origin")"
	if curl -f -s -S "https://archive.debian.org/debian/dists/" | grep ">$codename/" > /dev/null ; then
	    # it's in archive repo
            repo_base_url="https://archive.debian.org/debian"
	else
	    # it's in main repo
            repo_base_url="http://ftp.debian.org/debian"
	fi
	echo "$repo_base_url" > "$xlocales_cache/$origin/Packages.base_url"
	debian_cat_packages_file "$repo_base_url" "$codename" > "$packages_file.tmp"
	mv "$packages_file.tmp" "$packages_file"
    fi
}

xlocales_debian_list()
{
    for v in $(debian_distro_info_data_for_source "debian" | cut -d, -f1 | sort -Vr) ; do
	if ! xlocales_version_le "$xlocales_debian_min" "$v" ; then
	    continue
	fi
	origin="debian$v"
	debian_fetch_packages_file "$origin"
	package_version="$(debian_get_package_field "$origin" "locales" "Version")"
	package_version="$(echo "$package_version" | sed 's/\+.*$//')"
	locale_version="$(echo "$package_version" | sed 's/^\([0-9]*\.[0-9]*\).*/\1/')"
	if ! xlocales_version_le "$xlocales_min_libc_version" "$locale_version" ; then
	    continue
	fi
	if ! xlocales_version_le "$locale_version" "$xlocales_max_libc_version" ; then
	    continue
	fi
	echo "$origin" "$package_version"
    done
}

xlocales_debian_fetch()
{
    origin="$1"

    src="$xlocales_src/$origin"    

    if [ -e "$src/xlocales.configured" ] ; then return ; fi

    package_url="$(debian_get_package_url "$origin" "locales")"
    file="$xlocales_cache/$origin/$(basename "$package_url")"
    fetch_src "$package_url" "$file"
    locale_version="$(basename "$package_url" | sed 's/^[^0-9]*\([0-9]*\.[0-9]*\).*$/\1/')"
    package_version="$(debian_get_package_field "$origin" "locales" "Version")"

    mkdir -p "$src"
    ar --output "$src" x "$file"
    ( cd "$src" ; tar xf data.tar.* )
    cp "$src/usr/share/i18n/SUPPORTED" "$src/supported"

    mkdir -p "$src/charmaps"
    for charmap_gz in $(ls "$src/usr/share/i18n/charmaps") ; do
        charmaps_gz_path="$fakeroot_path/usr/share/i18n/charmaps"
        charmap="$(basename "$charmap_gz" .gz)"
        gzip -d < "$charmaps_gz_path/$charmap_gz" > "$src/charmaps/$charmap"
    done
        
    xlocales_gnu_configure "$origin" \
			   "usr/share/i18n/locales" \
			   "charmaps" \
			   "$package_url" \
			   "$locale_version" \
			   "$package_version"
}

