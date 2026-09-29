xlocales_glibc_url="https://ftp.gnu.org/gnu/glibc"

xlocales_glibc_desc()
{
    echo "GNU glibc tarballs"
}

xlocales_glibc_list()
{
    index_file="$xlocales_cache/glibc/index.html"
    
    fetch_src "$xlocales_glibc_url/" "$index_file"
    for v in $(sed -n 's/^.*a href="glibc-\([0-9]\.[0-9][0-9]*\)\.tar\.xz".*$/\1/p' < "$index_file" | sort -r -V) ; do
	v_major="$(echo "$v" | cut -d. -f1)"
	v_minor="$(echo "$v" | cut -d. -f2)"
	if [ "$v_major" -eq 2 -a "$v_minor" -lt 28 ] ; then
	    continue # too old
	fi
	echo "glibc$v" "$v"
    done
}

xlocales_glibc_fetch()
{
    origin="$1"
    
    src="$xlocales_src/$origin"

    if [ ! -e "$src/Makefile" ] ; then
	version="$(origin_get_version "$origin")"
	url="$xlocales_glibc_url/glibc-$version.tar.xz"
	tarball="$xlocales_cache/$origin/glibc-$version.tar.xz"
	
	mkdir -p "$src/build"
	fetch_src "$url" "$tarball"
	tar xf "$tarball" -C "$src"
	(
	    # Need to run configure and make to convert en_US.in etc to en_US etc.
	    cd "$src/build"
	    ../glibc-$version/configure --quiet --prefix=/tmp/dummy --srcdir "../glibc-$version" --disable-sanity-checks
	    make -s localedata/subdir_lib
	    #cp localedata/* ../
	)
	
	# inject version information into LC_IDENTIFICATION revision field
	mkdir -p "$src/locales"
	for locale_src in $(ls $src/glibc-$version/localedata/locales) ; do
	    sed "s/^\(revision *\".*\)\"$/\1; xlocales=$xlocales_version; origin=$origin; localedef=$localedef_version; localedata=$version\"/" \
		< "$src/glibc-$version/localedata/locales/$locale_src" \
		> "$src/locales/$locale_src"
	done

	cp -r "$src/glibc-$version/localedata/charmaps" "$src/"
	#cp -r "$src/glibc-$version/localedata/locales" "$src/"

	localedef_version="$(localedef --version | head -1 | sed 's/.* //')"

	# write out meta-data that will be used to create packages
	echo "xlocales-$origin" > "$src/xlocales.package_name"
	echo "$version.$xlocales_version" > "$src/xlocales.package_version"
	echo "$url" > "$src/xlocales.package_source"
	echo "$version" > "$src/xlocales.package_source_libc"
	echo "$localedef_version" > "$src/xlocales.package_target_libc"

	echo "xlocales-system-$origin" > "$src/xlocales-system.package_name"
	echo "$version.$xlocales_version" > "$src/xlocales-system.package_version"
	echo "$url" > "$src/xlocales-system.package_source"
	echo "$version" > "$src/xlocales-system.package_source_libc"
	echo "$localedef_version" > "$src/xlocales-system.package_target_libc"
	
	# generate a makefile
	#
	# Note that @origin and @version happen to come out the same for glibc.
	grep '/' "$src/glibc-$version/localedata/SUPPORTED" | sed 's/ .*$//;s|/| |' > "$src/supported"	
	while read -r locale charmap ; do
	    locale_dst="xlocales/$origin/locales/$locale"
	    echo "LOCALES+=$locale_dst"
	done < "$src/supported"	> "$src/Makefile"
	echo 'all: $(LOCALES)' >> "$src/Makefile"
	echo "" >> "$src/Makefile"
	echo "clean:" >> "$src/Makefile"
	printf "\trm -fr glibc-$version locales charmaps build supported xlocales\n" >> "$src/Makefile"
	while read -r locale charmap ; do
	    locale_dst="xlocales/$origin/locales/$locale"
	    locale_src="locales/$(echo "$locale" | sed 's/\..*$//')"
	    echo "$locale_dst: $locale_src"
	    printf "\t@mkdir -p xlocales/$source/locales@origin\n"
	    printf "\t@mkdir -p xlocales/$source/locales@version\n"
	    printf "\t@mkdir -p xlocales/$source/locales@\n"
	    printf "\t@mkdir -p xlocales/$origin/locales\n"
	    printf "\t@mkdir -p xlocales/$origin/locales@origin\n"
	    printf "\t@mkdir -p xlocales/$origin/locales@version\n"
	    printf "\t@mkdir -p xlocales/$origin/locales@\n"
	    printf "\t@mkdir -p xlocales/locales@origin\n"
	    printf "\t@mkdir -p xlocales-system/locales\n"
	    printf "\tI18NPATH=./locales localedef -f charmaps/$charmap -i \$< \$@\n"
	    printf "\tln -f -s ../locales/$locale xlocales/$source/locales@origin/$locale@$origin\n"
	    printf "\tln -f -s ../locales/$locale xlocales/$source/locales@version/$locale@glibc$version\n"
	    printf "\tln -f -s ../locales/$locale xlocales/$source/locales@/$locale@$origin\n"
	    printf "\tln -f -s ../locales/$locale xlocales/$origin/locales@origin/$locale@$origin\n"
	    printf "\tln -f -s ../locales/$locale xlocales/$origin/locales@version/$locale@glibc$version\n"
	    printf "\tln -f -s ../$origin/locales/$locale xlocales/locales@origin/$locale@$origin\n"
	    printf "\tln -f -s ../$origin/locales/$locale xlocales/locales@/$locale@$origin\n"
	    printf "\tln -f -s $xlocales_prefix/lib/xlocales/locales/$locale@$origin xlocales-system/locales@origin/$locale@$origin\n"
	done < "$src/supported"	>> "$src/Makefile"
    fi
}
