xlocales_freebsd_user="freebsd"
xlocales_freebsd_repo="freebsd-src"
xlocales_freebsd_gh_api="https://api.github.com/repos/$xlocales_freebsd_user/$xlocales_freebsd_repo"
xlocales_freebsd_gh_raw="https://raw.githubusercontent.com/$xlocales_freebsd_user/$xlocales_freebsd_repo"

xlocales_freebsd_desc()
{
    echo "FreeBSD releases"
}

xlocales_freebsd_release_tags()
{
    cache_file="$xlocales_cache/freebsd/release_tags"

    if [ ! -e "$cache_file" ] ; then
	mkdir -p "$xlocales_cache/freebsd"
	git ls-remote --tags "$xlocales_freebsd_url" | cut -f2 | sed 's|refs/tags/||' | \
            grep -v '\^{}' | \
            grep -v '_cvs$' | \
            grep '^release/[0-9][0-9]*\.[0-9][0-9]*\.' | \
            sort -Vr > "$cache_file.tmp"
	mv "$cache_file.tmp" "$cache_file"
    fi

    cat "$cache_file"
}

# I want to download just a bit of the huge FreeBSD source tree
# without checking the whole thing out, but Github doesn't allow git
# archive and even sparse cloning is really slow and transfers a lot
# of data.
#
# This is a quick and dirty way to get a directory listing at a tag
# using the Github JSON API.  Processing JSON wth sed is not the most
# robust solution, but it works enough for this cases it needs to
# handle...
xlocales_freebsd_dir()
{
    src_tag="$1"
    src_path="$2"

    url="$xlocales_freebsd_gh_api/contents/$src_path?ref=$src_tag"

    cache_file="$xlocales_cache/freebsd/dir/$src_tag/$src_path.cached"
    if [ -e "$cache_file" ] ; then
	cat "$cache_file"
	return
    fi

    begin_status "Fetching directory $url"
    response="$(curl -s \
                -H "Accept: application/vnd.github+json" \
              	-H "User-Agent: https://github.com/macdice/xlocales configure script" \
                "$url")"

    if [ -z "$response" ] || echo "$response" | grep -q "message"; then
        echo "Could not fetch $url: $response" >&2
	exit 1
    fi
    end_status
    
    mkdir -p "$(dirname "$cache_file")"
    for file in $(echo "$response" | sed 's/"name":"\([^"]*\)"/\
name=\1\
/g' | grep '^name=' | cut -d= -f2) ; do
	echo "$file"
    done > "$cache_file.tmp"
    mv "$cache_file.tmp" "$cache_file"
    cat "$cache_file"
}

xlocales_freebsd_fetch_dir()
{
    origin="$1"
    tag="$2"
    dir="$3"

    src="$xlocales_src/$origin"

    mkdir -p "$src/$dir"
    for file in $(xlocales_freebsd_dir "$tag" "$dir") ; do
	fetch_src "$xlocales_freebsd_gh_raw/$tag/$dir/$file" "$src/$dir/$file"
    done
}

xlocales_freebsd_list()
{    
    last_version=""
    for tag in $(xlocales_freebsd_release_tags) ; do
	full_version="$(echo "$tag" | sed 's/^[^0-9]*//')"
	version="$(echo "$full_version" | sed 's/^\([0-9][0-9]*\.[0-9][0-9]*\).*$/\1/')"
	if [ "$version" = "$last_version" ] ; then
	    continue
	fi
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
    full_version="$(xlocales_freebsd_list | grep "^$origin " | cut -d' ' -f2)"
    if [ -z "$full_version" ] ; then
	echo "Origin unknown: $origin" >&2
	exit 1
    fi
    tag="release/$full_version"
    src="$xlocales_src/$origin"

    mkdir -p "$src"

    for share_dir in $(xlocales_freebsd_dir "$tag" "share") ; do
	case "$share_dir" in
	    *def*) xlocales_freebsd_fetch_dir "$origin" "$tag" "share/$share_dir";;
	esac
    done
	       
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
