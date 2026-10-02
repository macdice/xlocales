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
	    codename="$(xlocales_debian_codename_for_origin "$origin")"

	    # figure out which repo it's in
	    old_dists_url="https://old-releases.ubuntu.com/ubuntu"
	    old_dists_cache="$xlocales_cache/ubuntu/old-dists.html"
	    xlocales_fetch "$origin" "$old_dists_url/dists/" "$old_dists_cache"
	    archive_dists_url="https://archive.ubuntu.com/ubuntu"
	    archive_dists_cache="$xlocales_cache/ubuntu/archive-dists.html"
	    xlocales_fetch "$origin" \
                       "$archive_dists_url/ubuntu/dists/" \
                       "$archive_dists_cache"
	    if grep -q "\"$codename/\"" "$archive_dists_cache" ; then	    
	        repo_base_url="$archive_dists_url"
	    elif grep -q "\"$codename/\"" "$old_dists_cache" ; then
	        repo_base_url="$old_dists_url"
	    else
	        xlocales_error "xlocales_ubuntu_fetch_packages_file: could not find package repo for $origin ($codename)"
	        exit 1
	    fi
	    
	    echo "$repo_base_url" > "$xlocales_cache/$origin/Packages.base_url"
	    xlocales_debian_cat_packages_file "$origin" \
                                          "$repo_base_url" \
                                          "$codename" \
                                          > "$packages_file.tmp"
	    mv "$packages_file.tmp" "$packages_file"
    fi
}

xlocales_ubuntu_list()
{
    for v in $(xlocales_debian_distro_info_for_source "ubuntu" | \
                   sed 's/ LTS,/,/' | \
                   cut -d, -f1 | \
                   sort -Vr) ; do
	    if ! xlocales_version_le "$xlocales_ubuntu_min" "$v" ; then
	        continue
	    fi
        
	    origin="ubuntu$v"
	    xlocales_ubuntu_fetch_packages_file "$origin"

	    package_version="$(xlocales_debian_get_package_field "$origin" \
                                                             "locales" \
                                                             "Version")"
	    locale_version="$(echo "$package_version" | \
                          sed 's/^\([0-9]*\.[0-9]*\).*/\1/')"
    
	    if ! xlocales_libc_version_in_range "$locale_version" ; then continue ; fi
    
	    echo "$origin" "$package_version"
    done
}

xlocales_ubuntu_fetch()
{
    xlocales_debian_fetch "$1"
}
