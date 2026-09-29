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
	echo "XXXX!"
	
	mkdir -p "$src/locales"
	for locale_src in $(ls $src/glibc-$version/localedata/locales) ; do
	    # inject version information into LC_IDENTIFICATION
	    echo "XXXX2! begin $locale_src"
	    sed "s/^\(revision *\".*\)\"$/\1; xlocales-origin=$origin; localedef=$localedef_version; localedata=$version\"/" \
		< "$src/glibc-$version/localedata/locales/$locale_src" \
		> "$src/locales/$locale_src"
	    echo "XXXX2! end $locale_src"
	done

	echo "XXXX3!"
	cp -r "$src/glibc-$version/localedata/charmaps" "$src/"
	#cp -r "$src/glibc-$version/localedata/locales" "$src/"

	# generate a makefile
	#
	# Note that @origin and @version happen to come out the same for glibc.
	grep '/' "$src/glibc-$version/localedata/SUPPORTED" | sed 's/ .*$//;s|/| |' > "$src/supported"	
	while read -r locale charmap ; do
	    dst="../../$xlocales_build/$origin"
	    locale_dst="$dst/$origin/locales/$locale"
	    echo "LOCALES+=$locale_dst"
	done < "$src/supported"	> "$src/Makefile"
	echo 'all: $(LOCALES)' >> "$src/Makefile"
	echo "" >> "$src/Makefile"
	echo "clean:" >> "$src/Makefile" >> "$src/Makefile"
	printf "\trm -fr ../build/$origin ../build/locales@origin/*@$origin" >> "$src/Makefile"
	while read -r locale charmap ; do
	    dst="../../$xlocales_build"
	    locale_dst="$dst/$origin/locales/$locale"
	    locale_src="locales/$(echo "$locale" | sed 's/\..*$//')"
	    echo "$locale_dst: $locale_src"
	    printf "\t@mkdir -p $dst/$origin/locales\n"
	    printf "\tI18NPATH=$src/locales localedef -f charmaps/$charmap -i \$< \$@\n"
	    printf "\t@mkdir -p $dst/$origin/locales@origin\n"
	    printf "\tln -f -s ../locales/$locale $dst/$origin/locales@origin/$locale@$origin\n"
	    printf "\t@mkdir -p $dst/$origin/locales@version\n"
	    printf "\tln -f -s ../locales/$locale $dst/$origin/locales@version/$locale@glibc$version\n"
	    printf "\t@mkdir -p $dst/locales@origin\n"
	    printf "\tln -f -s ../$origin/locales/$locale $dst/locales@origin/$locale@$origin\n"
	done < "$src/supported"	>> "$src/Makefile"
    fi
}
