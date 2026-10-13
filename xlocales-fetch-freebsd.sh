#!/bin/sh

set -e

XLOCALES_FREEBSD_MIN_VERSION="11.0"
xlocales_freebsd_release_url="https://api.github.com/repos/freebsd/freebsd-src/tarball/refs/tags/release"

. "./xlocales-utils.sh"


xlocales_get_freebsd_list()
{
    mkdir -p "cache/freebsd"

    # FreeBSD has release tarballs on freebsd.org (10.0, 10.1, ...),
    # but not patch-level updates (-p1, -p2, ...) and it seems better
    # to use the latest of those, so scan the tarballs from the
    # project github repo.
    #
    # We could just fetch the list of git tags to find out what is
    # available, but it's remotely possible that they'll be out of
    # sync for short periods, so do the github API paging dance.
    cache_file_base="cache/freebsd/tarball_list"
    page=1
    while : ; do
	if [ ! -e "$cache_file_base.contents.$page" ] ; then
	    url="https://api.github.com/repos/freebsd/freebsd-src/tags?per_page=100&page=$page"
	    xlocales_begin_status "Fetching $url"
	    curl -L -D "$cache_file_base.headers.$page" -f -s -S \
		 "$url" -o "$cache_file_base.contents.$page.tmp"
	    xlocales_end_status
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
	    if ! xlocales_version_le "$XLOCALES_FREEBSD_MIN_VERSION" "$version" ; then
		    continue
	    fi
	    echo "freebsd$version" "$full_version"
	done
}

xlocales_get_freebsd()
{ 
    origin="$1"

    src="src/$origin"

    full_version="$(xlocales_get_freebsd_list | grep "^$origin " | cut -d' ' -f2)"
    if [ -z "$full_version" ] ; then
	    xlocales_error "Origin unknown: $origin"
    fi

    tarball="cache/$origin/$full_version.tar.gz"
    xlocales_fetch "$origin" "$xlocales_freebsd_release_url/$full_version" "$tarball"
    mkdir -p "$src"
    xlocales_begin_status "Extracting locale data from $tarball"
    tar -C "$src" --strip-components 1 -xf "$tarball" \ '*/share/*def*/'
    xlocales_end_status

    
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

case "$1" in
    ''|help|-h|--help)
        cat <<EOF >&2
Usage:
  $0 --list                  list available origins
  $0 freebsd [output_dir]    fetch locale data for all versions
  $0 freebsdX.Y [output_dir] fetch locale data for one version
EOF
        exit 1
        ;;
    -l|--list)
        xlocales_get_freebsd_list
        ;;
    *[0-9]*)
        origin="$1"
        source="$(xlocales_origin_get_source "$origin")"
        xlocales_get_freebsd "$origin" "$2"
        ;;
    *)
        source="$1"
        output_dir="$2"
        for origin in $(xlocales_get_freebsd_list | cut -d' ' -f1) ; do
            xlocales_get_freebsd "$origin" "$output_dir"
        done
        ;;
esac
