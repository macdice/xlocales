xlocales_ubuntu_min="18.04"

xlocales_ubuntu_desc()
{
    echo "Ubuntu 'locales' packages"
}

xlocales_ubuntu_fetch_packages_file()
{
    origin="$1"

    packages_file="$xlocales_cache/$origin/Packages"

    if [ ! -e "$packages_file" ] ; then
	mkdir -p "$xlocales_cache/$origin"
	codename="$(debian_codename_for_origin "$origin")"

	# figure out which repo it's in
	old_dists_url="https://old-releases.ubuntu.com/ubuntu" \
	old_dists_cache="$xlocales_cache/ubuntu/old-dists.html"
	fetch_src "$old_dists_url/dists/" "$old_dists_cache"
	archive_dists_url="https://archive.ubuntu.com/ubuntu"
	archive_dists_cache="$xlocales_cache/ubuntu/archive-dists.html"
	fetch_src "$archive_dists_url/ubuntu/dists/" "$archive_dists_cache"
	if grep -q "\"$codename/\"" "$archive_dists_cache" ; then	    
	    repo_base_url="$archive_dists_url"
	elif grep -q "\"$codename/\"" "$old_dists_cache" ; then
	    repo_base_url="$old_dists_url"
	else
	    echo "xlocales_ubuntu_fetch_packages_file: could not find package repo for $origin ($codename)" >&2
	    exit 1
	fi
	    
	echo "$repo_base_url" > "$xlocales_cache/$origin/Packages.base_url"
	debian_cat_packages_file "$repo_base_url" "$codename" > "$packages_file.tmp"
	mv "$packages_file.tmp" "$packages_file"
    fi
}

xlocales_ubuntu_list()
{
    for v in $(debian_distro_info_data_for_source "ubuntu" | sed 's/ LTS,/,/' | cut -d, -f1 | sort -Vr) ; do
	if ! xlocales_version_le "$xlocales_ubuntu_min" "$v" ; then
	    continue
	fi
	origin="ubuntu$v"
	xlocales_ubuntu_fetch_packages_file "$origin"
	package_version="$(debian_get_package_field "$origin" "locales" "Version")"
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

xlocales_ubuntu_fetch()
{
    xlocales_debian_fetch "$1"
}
