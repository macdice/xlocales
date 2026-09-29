xlocales_gnu_url="https://ftp.gnu.org/gnu/glibc"
xlocales_gnu_min=2.28

xlocales_gnu_desc()
{
    echo "GNU glibc tarballs"
}

xlocales_gnu_list()
{
    index_file="$xlocales_cache/gnu/index.html"
    
    fetch_src "$xlocales_gnu_url/" "$index_file"
    for v in $(sed -n 's/^.*a href="glibc-\([0-9]\.[0-9][0-9]*\)\.tar\.xz".*$/\1/p' < "$index_file" | sort -r -V) ; do
	if ! xlocales_version_le "$xlocales_gnu_min" "$v" ; then continue ; fi
	echo "gnu$v" "$v"
    done
}

xlocales_gnu_fetch()
{
    origin="$1"

    version="$(origin_get_version "$origin")"
    src="$xlocales_src/$origin"    

    if [ -e "$src/xlocales.configured" ] ; then return ; fi
    
    version="$(origin_get_version "$origin")"
    url="$xlocales_gnu_url/glibc-$version.tar.xz"
    tarball="$xlocales_cache/$origin/glibc-$version.tar.xz"
    
    mkdir -p "$src/build"
    fetch_src "$url" "$tarball"
    tar xf "$tarball" -C "$src"

    (
	# Unlike downstream distributions, which ship the locale
	# definitions ready-made, here we need to configure and
	# compile a couple of things first.
	cd "$src/build"
	../glibc-$version/configure --quiet --prefix=/tmp/dummy --srcdir "../glibc-$version" --disable-sanity-checks
	make $xlocales_silent localedata/subdir_lib
    )

    xlocales_gnu_configure "$origin" \
			   "glibc-$version/localedata/locales" \
			   "glibc-$version/localedata/charmaps" \
			   "$url" \
			   "$version"
}

xlocales_gnu_munge_name()
{
    # en_US.UTF-8 -> en_US.utf8, just to confuse everyone
    prefix="$(echo "$1" | cut -d. -f1)"
    opt_codeset="$(echo "$1" | sed 's/^[^.]*//')"       
    opt_codeset_munged="$(echo "$opt_codeset" | sed 's/[^.a-zA-Z0-9]//g' | tr '[:upper:]' '[:lower:]')"
    echo "$prefix$opt_codeset_munged"
}

# This routine is also used by distro-specific fetchers that used
# potentially patched versions of the GNU glibc sources.  Callers tell
# it where the charmaps and locales directories have been unpacked,
# and this routine creates Makefile.  The url argument is used only
# for package meta-data, ie where the data came from.
xlocales_gnu_configure()
{
    origin="$1"
    locales_dir="$2"
    charmaps_dir="$3"
    url="$4"
    locale_version="$5"
    
    src="$xlocales_src/$origin"

    # already done?
    if [ -e "$src/xlocales.configured" ] ; then return ; fi

    source="$(origin_get_source "$origin")"
    localedef_version="$(localedef --version | head -1 | sed 's/.* //')"

    # Inject version into LC_IDENTIFICATION revision field for each
    # locale definition; this provides a robust way to confirm that
    # opening "en_US@glibc2.31" actually opened 2.31, and didn't
    # silently drop the modifier because it wasn't found, but this
    # convention is made up.
    mkdir -p "$src/localedata"
    for locale_src in $(ls "$src/$locales_dir") ; do
	sed "s/^\(revision *\".*\)\"$/\1; xlocales=$xlocales_version; origin=$origin; localedef=$localedef_version; localedata=$version\"/" \
	    < "$src/$locales_dir/$locale_src" \
	    > "$src/localedata/$locale_src"
    done

    # write out meta-data files that will be used for packaging
    echo "xlocales-$origin" > "$src/xlocales.package_name"
    echo "$version.$xlocales_version" > "$src/xlocales.package_version"
    echo "$url" > "$src/xlocales.package_source_url"
    echo "$version" > "$src/xlocales.package_source_libc"
    echo "$localedef_version" > "$src/xlocales.package_target_libc"

    echo "xlocales-system-$origin" > "$src/xlocales-system.package_name"
    echo "$version.$xlocales_version" > "$src/xlocales-system.package_version"
    echo "$url" > "$src/xlocales-system.package_source"
    echo "$version" > "$src/xlocales-system.package_source_libc"
    echo "$localedef_version" > "$src/xlocales-system.package_target_libc"

    echo "xlocales-system-glibc-$origin" > "$src/xlocales-system-glibc.package_name"
    echo "$version.$xlocales_version" > "$src/xlocales-system-glibc.package_version"
    echo "$url" > "$src/xlocales-system-glibc.package_source"
    echo "$version" > "$src/xlocales-system-glinc.package_source_libc"
    echo "$localedef_version" > "$src/xlocales-system-glibc.package_target_libc"

    # convert the SUPPORTED file, which lists the names and charmaps
    # to compile, into an easy to parse format; this happens to be the
    # same format that Debian/Ubuntu ship, so check if it's already
    # been put there by the those fetch routines.
    if [ ! -e "$src/supported" ] ; then
	grep '/' "$src/glibc-$version/localedata/SUPPORTED" | \
	    sed 's/ .*$//;s|/| |' > "$src/supported"
    fi

    # generate "all" target
    while read -r locale charmap ; do
	locale="$(xlocales_gnu_munge_name "$locale")"
	locale_dst="xlocales/$xlocales_prefix/$xlocales_infix/locales@$source/$locale@$origin"
	echo "LOCALES+=$locale_dst"
    done < "$src/supported"	> "$src/Makefile"    
    echo 'all: $(LOCALES)' >> "$src/Makefile"
    #echo "" >> "$src/Makefile"

    # generate "clean" target
    echo "clean:" >> "$src/Makefile"    
    printf "\trm -fr xlocales.configured glibc-$version locales charmaps build supported xlocales\n" >> "$src/Makefile"

    # generate target for each locale
    while read -r locale charmap ; do
	locale="$(xlocales_gnu_munge_name "$locale")"
	locale_dst_dir="xlocales/$xlocales_prefix/$xlocales_infix/locales@$source"
	locale_dst="$locale_dst_dir/$locale@$origin"
	locale_src="localedata/$(echo "$locale" | cut -d. -f1)"

	echo "$locale_dst: $locale_src"
	
	# Cross-compiled locales with @ORIGIN modifiers are collected
	# under locales@SOURCE, so if you install xlocales-debian12
	# and xlocales-debian13 then /usr/lib/locales@debian will
	# contain:
	#
	# en_US.utf8@debian12
	# en_US.utf8@debian13
	# fr_FR.utf8@debian12
	# fr_FR.utf8@debian13
	# ...
	printf "\t@mkdir -p $locale_dst_dir\n"
	printf "\tI18NPATH=./locales localedef -f $charmaps_dir/$charmap -i \$< \$@\n"

	# Symlinks with @glibcX.Y modifiers are also collected under
	# locales@glibc.SOURCE.  For example, with two
	# xlocales-debianN packages installed, under
	# XLOCALES/locales@glibc.debian you might see:
	#
	# en_US.utf8@glibc2.31
	# en_US.utf8@glibc2.34
	# fr_FR.utf8@glibc2.31
	# fr_FR.utf8@glibc2.34
	# ...
	#
	# This allows glibc version-based locale selection, but
	# requires a separate directory for each source as the glibc
	# versions might coincide between Linux distributions,
	# preventing installation if they were to share a directory.
	dst_dir="xlocales/$xlocales_prefix/$xlocales_infix/locales@glibc.$source"
	printf "\t@mkdir -p $dst_dir\n"
	printf "\tln -f -s ../locales@$source/$locale@$origin $dst_dir/$locale@glibc$locale_version\n"

	# Symlinks with no modifiers at all are collected under
	# XLOCALES/locales.SOURCE.  These hide the system locales of
	# the same names, if that directory is set as LOCPATH.
	dst_dir="xlocales/$xlocales_prefix/$xlocales_infix/locales.$origin"
	printf "\t@mkdir -p $dst_dir\n"
	printf "\tln -f -s ../locales@$source/$locale@$origin $dst_dir/$locale\n"

	# Optional symlinks to make eg en_US.utf8@debian12 available
	# without modifying LOCPATH, installable with the
	# xlocales-system-ORIGIN package.
	dst_dir="xlocales-system/$xlocales_system_locales"
	printf "\t@mkdir -p $dst_dir\n"
	printf "\tln -f -s $xlocales_prefix/$xlocales_infix/locales@$source/$locale@$origin $dst_dir/$locale@$origin\n"

	# Optional symlinks to make eg en_US.utf8@glibcX.Y available
	# without modifying LOCPATH, installable with one or more
	# xlocales-system-glibc-ORIGIN packages from the same SOURCE.
	# (Different sources are likely to create clashes in glibc
	# versions and be uninstallable.)
	dst_dir="xlocales-system-glibc/$xlocales_system_locales"
	printf "\t@mkdir -p $dst_dir\n"
	printf "\tln -f -s $xlocales_prefix/$xlocales_infix/locales@$source/$locale@$origin $dst_dir/$locale@glibc$locale_version\n"

    done < "$src/supported" >> "$src/Makefile"

    touch "$src/xlocales.configured"
}
