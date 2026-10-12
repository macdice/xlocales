xlocales_error()
{
    echo "$1" >&2
    exit 1
}

# Show temporary activity message.
xlocales_begin_status()
{
    string="$1"

    if [ -z "$COLUMNS" ] ; then
	    COLUMNS="$(tput cols)"
	    if [ -z "$COLUMNS" ] ; then
	        COLUMNS=80
	    fi
    fi
    
    if [ ${#string} -gt $(($COLUMNS - 3)) ] ; then	
        printf "%.*s... " $((COLUMNS - 6)) "$string" >&2
    else
        printf "%s " "$string" >&2
    fi
}

# Clear temporary activity message with ANSI control characters.
xlocales_end_status()
{
    printf "\r\033[K" >&2
}

# Fetch file from URL and store it at $2, unless it is already present.
xlocales_fetch()
{
    origin_or_source="$1"
    url="$2"
    dst="$3"

    if [ ! -e "$dst" ] ; then
        xlocales_begin_status "$origin_or_source: fetching $url"
        mkdir -p "$(dirname "$dst")"
        curl -L -f -s -S "$url" > "$dst.tmp"
        mv "$dst.tmp" "$dst"
        xlocales_end_status
    fi
}

# Extract source part of an origin string.
xlocales_origin_get_source()
{
    echo "$1" | sed 's/[0-9].*$//'
}

# Extract version part of an origin string.
xlocales_origin_get_version()
{
    origin="$1"
    version="$(echo "$origin" | sed 's/^[^0-9]*//')"
    if [ -z "$version" ] ; then
        xlocales_error "malformed origin: $origin"
    fi
    echo "$version"
}

# Test if x <= y using version string semantics.
xlocales_version_le()
{
    printf '%s\n%s\n' "$1" "$2" | sort -V --check=silent
}

# All xlocales-get-SOURCE.sh scripts have the same usage.
xlocales_get_usage()
{
    cat <<EOF >&2

Usage:

  $0 list: list valid ORIGIN values
  $0 ORIGIN [OUTPUT_DIR]: fetch from named origin

OUTPUT_DIR defauls to "xlocales-source".
EOF
    exit 1
}
