xlocales_debian_min="10"

xlocales_debian_desc()
{
    echo "Debian 'locales' packages"
}

xlocales_debian_distro_info_for_source()
{
    source="$1"

    url="https://debian.pages.debian.net/distro-info-data/$source.csv"
    file="$xlocales_cache/$source/$source.csv"

    xlocales_fetch "$source" "$url" "$file"
    # filter out title line and lines with no release date...
    grep -E '^[0-9][^,]*,[^,]*,[^,]*,[^,]*,[0-9]' "$file"
}

xlocales_debian_codename_for_origin()
{
    origin="$1"

    source="$(xlocales_origin_get_source "$origin")"
    version="$(xlocales_origin_get_version "$origin")"
    codename="$(xlocales_debian_distro_info_for_source "$source" | \
	      grep "^$version[, ]" | \
	      cut -d, -f3)"

    if [ -z "$codename" ] ; then
	xlocales_error "xlocales_debian_codename_for_origin: could not find codename for source=$source, version=$version"
    fi

    echo "$codename"
}

xlocales_debian_cat_packages_file()
{
    origin="$1"
    repo_base_url="$2"
    codename="$3"

    cache_file="$xlocales_cache/$origin/$codename.main"
    xlocales_fetch "$origin" "$repo_base_url/dists/$codename/main" "$cache_file"

    if grep -q "binary-all" "$cache_file" ; then
	# modern Debian has locales in "binary-all"
	arch="all"
    else
	# older Debian and all Ubuntu have a copy for each
	# architecture, so just pick one
	arch="amd64"
    fi

    url="$repo_base_url/dists/$codename/main/binary-$arch/Packages.gz"

    xlocales_begin_status "$origin: fetching packages file $url"
    curl -f -s -S "$url" | gzip -d
    xlocales_end_status
}

xlocales_debian_get_package_field()
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

xlocales_debian_get_package_url()
{
    origin="$1"
    package_name="$2"

    base_url="$(cat "$xlocales_cache/$origin/Packages.base_url")"

    filename="$(xlocales_debian_get_package_field "$origin" \
    						  "locales" \
						  "Filename")"

    echo "$base_url/$filename"
}

xlocales_debian_fetch_packages_file()
{
    origin="$1"

    packages_file="$xlocales_cache/$origin/Packages"

    if [ ! -e "$packages_file" ] ; then
	mkdir -p "$xlocales_cache/$origin"
	codename="$(xlocales_debian_codename_for_origin "$origin")"

	xlocales_begin_status "$origin: checking if $codename is in archive repo"
	if curl -f -s -S "https://archive.debian.org/debian/dists/" | \
		grep ">$codename/" > /dev/null
	then
	    # it's in archive repo
	    repo_base_url="https://archive.debian.org/debian"
	else
	    # it's in main repo
	    repo_base_url="http://ftp.debian.org/debian"
	fi
	xlocales_end_status

	# Remember where it is.  This is used by
	# xlocales_debian_get_package_url().
	echo "$repo_base_url" > "$xlocales_cache/$origin/Packages.base_url"
	
	xlocales_debian_cat_packages_file "$origin" \
					  "$repo_base_url" \
					  "$codename" \
					  > "$packages_file.tmp"
	mv "$packages_file.tmp" "$packages_file"
    fi
}

xlocales_debian_list()
{
    for v in $(xlocales_debian_distro_info_for_source "debian" | \
	       cut -d, -f1 | \
	       sort -Vr) ; do
	if ! xlocales_version_le "$xlocales_debian_min" "$v" ; then
	    continue
	fi

	origin="debian$v"
	xlocales_debian_fetch_packages_file "$origin"

	package_version="$(xlocales_debian_get_package_field "$origin" \
							     "locales" \
							     "Version")"
	locale_version="$(echo "$package_version" | \
			  sed 's/^\([0-9]*\.[0-9]*\).*/\1/')"

	if ! xlocales_libc_version_in_range "$locale_version" ; then continue ; fi

	echo "$origin" "$package_version"
    done
}

xlocales_debian_fetch()
{
    origin="$1"

    src="$xlocales_src/$origin"

    if [ -e "$src/xlocales.configured" ] ; then return ; fi

    package_url="$(xlocales_debian_get_package_url "$origin" "locales")"
    file="$xlocales_cache/$origin/$(basename "$package_url")"

    xlocales_fetch "$origin" "$package_url" "$file"

    locale_version="$(basename "$package_url" | \
    		      sed 's/^[^0-9]*\([0-9]*\.[0-9]*\).*$/\1/')"
    package_version="$(xlocales_debian_get_package_field "$origin" \
    							 "locales" \
							 "Version")"

    xlocales_check_libc_version_supported "$locale_version"
    
    mkdir -p "$src"
    
    xlocales_begin_status "$origin: extracting $file"
    ar --output "$src" x "$file"
    ( cd "$src" ; tar xf data.tar.* )
    cp "$src/usr/share/i18n/SUPPORTED" "$src/supported"
    mkdir -p "$src/charmaps"
    for charmap_gz in $(ls "$src/usr/share/i18n/charmaps") ; do
	charmaps_gz_path="$fakeroot_path/usr/share/i18n/charmaps"
	charmap="$(basename "$charmap_gz" .gz)"
	gzip -d < "$charmaps_gz_path/$charmap_gz" > "$src/charmaps/$charmap"
    done
    xlocales_end_status

    # defer to the GNU glibc module for the rest
    xlocales_gnu_configure "$origin" \
			   "usr/share/i18n/locales" \
			   "charmaps" \
			   "$package_url" \
			   "$locale_version" \
			   "$package_version"
}

xlocales_debian_diff()
{
    xorigin="$1"

    package_version="$(debian_get_package_field "$origin" \
    						"locales" \
						"Version")"
    locale_version="$(echo "$package_version" | \
    		      sed 's/^[^0-9]*\([0-9]*\.[0-9]*\).*$/\1/')"
    upstream="gnu$locale_version"
    #src="$xlocales_src/$origin"
    #gnu="$xlocales_src/$upstream"

    xlocales_debian_fetch "$origin"
    xlocales_gnu_fetch "$upstream"

    src="$xlocales_src/$xorigin"
    gnu="$xlocales_src/$upstream"

    ls "$src/charmaps" | sort > "$src/charmaps.mine"
    ls "$gnu/glibc-$locale_version/localedata/charmaps" | sort > "$src/charmaps.upstream"
    diff -u "$src/charmaps.upstream" "$src/charmaps.mine" || true
    for x in $(ls "$src/charmaps") ; do
	diff -u "$gnu/glibc-$locale_version/localedata/charmaps/$x" "$src/charmaps/$x" || true
    done

    ls "$src/usr/share/i18n/locales" | sort > "$src/locales.mine"
    ls "$gnu/glibc-$locale_version/localedata/locales" | sort > "$src/locales.upstream"
    diff -u "$src/locales.upstream" "$src/locales.mine" || true
    for x in $(ls "$src/usr/share/i18n/locales") ; do
	if [ -e "$gnu/glibc-$locale_version/localedata/locales/$x" ] ; then
	    diff -u "$gnu/glibc-$locale_version/localedata/locales/$x" \
		 "$src/usr/share/i18n/locales/$x" || true
	fi
    done
}

#
