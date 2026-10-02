#xlocales_freebsd_tarballs="http://ftp-archive.freebsd.org/pub/FreeBSD-Archive/old-releases/amd64/"
#xlocales_freebsd_list=

xlocales_freebsd_release_url="https://api.github.com/repos/freebsd/freebsd-src/tarball/refs/tags/release"

xlocales_freebsd_desc()
{
    echo "FreeBSD releases"
}

xlocales_freebsd_list()
{
    mkdir -p "$xlocales_cache/freebsd"

    # FreeBSD has release tarballs on freebsd.org (10.0, 10.1, ...),
    # but not patch-level updates (-p1, -p2, ...) and it seems better
    # to use the latest of those, so scan the tarballs from the
    # project github repo.
    #
    # We could just fetch the list of git tags to find out what is
    # available, but it's remotely possible that they'll be out of
    # sync for short periods, so do the github API paging dance.
    cache_file_base="$xlocales_cache/freebsd/tarball_list"
    page=1
    while : ; do
	if [ ! -e "$cache_file_base.contents.$page" ] ; then
	    url="https://api.github.com/repos/freebsd/freebsd-src/tags?per_page=100&page=$page"
	    begin_status "Fetching $url"
	    curl -L -D "$cache_file_base.headers.$page" -f -s -S \
		 "$url" -o "$cache_file_base.contents.$page.tmp"
	    end_status
	    mv "$cache_file_base.contents.$page.tmp" "$cache_file_base.contents.$page"
	fi

	# is there another page?
	if ! grep -q '^link: .*; rel="next"' "$cache_file_base.headers.$page" ; then
	    break
	fi
	page=$((page + 1))
    done

    # Since we have an inconsistent snapshot of the pages, concatenate them
    # and find the unique release tags.  This assumes that items are
    # only added (ie shift to later pages and thus might be duplicated
    # if we're unlucky) and never deleted...
    last_version=""
    cat "$cache_file_base.contents".* | \
	sed -n 's|^.*"tarball_url": "https://.*/release/\([^"]*\)".*|\1|p' | \
	sort -Vr | \
	uniq | \
	grep -v '_cvs$' | \
	sed 's|^\([0-9][0-9]*\.[0-9][0-9]*\)\(.*\)$|\1 \1\2|' | \
	while read -r version full_version ; do
	    if [ "$version" = "$last_version" ] ; then continue ; fi
	    last_version="$version"
	    if ! xlocales_version_le "$xlocales_min_libc_version" "$version" ; then
		continue
	    fi
	    if ! xlocales_version_le "$version" "$xlocales_max_libc_version" ; then
		continue
	    fi
	    echo "freebsd$version" "$full_version"
	done
}

xlocales_freebsd_fetch()
{ 
    origin="$1"

    src="$xlocales_src/$origin"

    if [ -e "$src/xlocales.configured" ] ; then
	return
    fi

    full_version="$(xlocales_freebsd_list | grep "^$origin " | cut -d' ' -f2)"
    if [ -z "$full_version" ] ; then
	echo "Origin unknown: $origin" >&2
	exit 1
    fi

    tarball="$xlocales_cache/$origin/$full_version.tar.gz"
    fetch_src "$xlocales_freebsd_release_url/$full_version" "$tarball"
    mkdir -p "$src"
    begin_status "Extracting locale data from $tarball"
    tar -C "$src" --strip-components 1 -xf "$tarball" \ '*/share/*def*/'
    end_status

    
    #for share_dir in $(xlocales_freebsd_dir "$tag" "share") ; do
#	case "$share_dir" in
#	    *def*) xlocales_freebsd_fetch_dir "$origin" "$tag" "share/$share_dir";;
#	esac
#    done
	       
    #xlocales_freebsd_fetch_dir "$origin" "$tag" "share/colldef"
    #xlocales_freebsd_fetch_dir "$origin" "$tag" "share/colldef"
    #xlocales_freebsd_fetch_dir "$origin" "$tag" "share/colldef"
    #xlocales_freebsd_dir "$tag" "share/colldef" #"$src/share/colldef"
    #git archive --remote="$xlocales_freebsd_url" --format=tar.gz "$tag":share/colldef > x.tgz
    #rm -fr "$src"
    #git init "$src"
    #git -C "$src" remote add origin "$xlocales_freebsd_url"
    #git -C "$src" sparse-checkout set --cone
    #git -C "$src" sparse-checkout set share/colldef share/ctypedef share/monetdef
    #echo git -C "$src" pull --depth 1 origin "$tag"
    #git -C "$src" fetch --tags
    #git -C "$src" checkout --depth 1 "$tag"
    #git clone --filter=blob:none --sparse "$xlocales_freebsd_url" "$src"
}
