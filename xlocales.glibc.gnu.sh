xlocales_gnu_url="https://ftp.gnu.org/gnu/glibc"

xlocales_gnu_desc()
{
    echo "Upstream glibc tarballs from gnu.org"
}

xlocales_gnu_list()
{
    index_file="$xlocales_cache/gnu/index.html"

    fetch_src "$xlocales_gnu_url/" "$index_file"
    for locale_version in $(sed -n 's/^.*a href="glibc-\([0-9]\.[0-9][0-9]*\)\.tar\.xz".*$/\1/p' < "$index_file" | sort -r -V) ; do
	if ! xlocales_version_le "$xlocales_min_libc_version" "$locale_version" ; then
	    continue
	fi
	if ! xlocales_version_le "$locale_version" "$xlocales_max_libc_version" ; then
	    continue
	fi
	echo "gnu$locale_version" "$locale_version"
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
			   "$version" \
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
    package_version="$6"
    
    src="$xlocales_src/$origin"

    # already done?
    if [ -e "$src/xlocales.configured" ] ; then return ; fi

    source="$(origin_get_source "$origin")"
    localedef_version="$(localedef --version | head -1 | sed 's/.* //')"

    mkdir -p "$src/localedata"

    # Inject version into LC_IDENTIFICATION revision field for each
    # locale definition; this provides a robust way to confirm that
    # opening "en_US@glibc2.31" actually opened 2.31, and didn't
    # silently drop the modifier because it wasn't found, but this
    # convention is made up.
    #
    # There is already potentially useful information in there in
    # the source: the Unicode version version used to generate ctype.
    # Unfortunately it does not survive into compiled locales, so
    # let's invent a format for bolting arbitrary extra version on
    # after the stagnant "1.0" that most locales report.
    unicode_version="$(sed -n 's/^revision *\"\(.*\)\"$/\1/p' < "$src/$locales_dir/i18n_ctype" | head -1)"    
    for locale_src in $(ls "$src/$locales_dir") ; do
	sed "s/^\(revision *\".*\)\"$/\1; xlocales=$xlocales_version; origin=$origin; unicode=$unicode_version; localedef=$localedef_version; localedata=$version\"/" \
	    < "$src/$locales_dir/$locale_src" \
	    > "$src/localedata/$locale_src"
    done

    mkdir -p "xlocales-$origin"
    mkdir -p "xlocales-system-$origin"
    mkdir -p "xlocales-system-extra-$origin"

    printf "Generating $src/Makefile..." >&2    
    echo > "$src/Makefile"
    
    case "$xlocales_package" in
	deb)
	    package_arch="$(dpkg --print-architecture)"
	    echo "PACKAGES+=../../xlocales-${origin}_${package_version}_${package_arch}.deb" >> "$src/Makefile"
	    mkdir -p "$src/xlocales-$origin/DEBIAN"
	    if [ "$source" = "$xlocales_host_os" ] ; then
		opt_source=""
	    else
		opt_source=".$source"
	    fi
	    cat <<EOF > "$src/xlocales-$origin/DEBIAN/control"
Package: xlocales-$origin
Version: $package_version
Architecture: $package_arch
Depends: libc6 (>= $localedef_version), libc6 (<< $localedef_version+)
Maintainer: $xlocales_maintainer
Homepage: $xlocales_homepage
Description: Locales from $origin compiled for $xlocales_host_origin
 Locale data obtained from:
  $url
 and then cross-compiled with localedef $localedef_version for $xlocales_host_origin.
 Can be made available to libc with various names by setting LOCPATH to:
  * $xlocales_prefix/$xlocales_infix/locale@$source (e.g. en_US.utf8@$origin)
  * $xlocales_prefix/$xlocales_infix/locale@glibc$opt_source (e.g. en_US.utf8@glibc$locale_version)
  * $xlocales_prefix/$xlocales_infix/locale.$origin (e.g. en_US.utf8, hiding system locale)
 The only intentional change is to append additional version information to
 the LC_IDENTIFICATION revision string.  Other variations in behaviour
 compared to the system locales on $origin systems are possible due to C code
 changes and bug fixes in libc or localedef.
EOF
	    echo "PACKAGES+=../../xlocales-system-${origin}_${package_version}_${package_arch}.deb" >> "$src/Makefile"
	    mkdir -p "$src/xlocales-system-$origin/DEBIAN"
	    cat <<EOF > "$src/xlocales-system-$origin/DEBIAN/control"
Package: xlocales-system-$origin
Version: $package_version
Architecture: $package_arch
Depends: xlocales-$origin (= $package_version)
Maintainer: $xlocales_maintainer
Homepage: $xlocales_homepage
Description: @$origin locales in system locale path
 Adds locale names with @$origin modifiers to the standard locale path
 so that they are available wihout setting LOCPATH.
EOF
	    echo "PACKAGES+=../../xlocales-system-extra-${origin}_${package_version}_${package_arch}.deb" >> "$src/Makefile"
	    mkdir -p "$src/xlocales-system-extra-$origin/DEBIAN"
	    cat <<EOF > "$src/xlocales-system-extra-$origin/DEBIAN/control"
Package: xlocales-system-extra-$origin
Version: $package_version
Architecture: $package_arch
Depends: xlocales-$origin (= $package_version)
Maintainer: $xlocales_maintainer
Homepage: $xlocales_homepage
Description: @glibc$locale_version and @unicode$unicode_version in system locale path
 Adds locale names with @glibc$locale_version and @unicode$unicode_version
 modifiers to the standard locale path so that they are available without
 setting LOCPATH.
EOF
	    ;;
    esac
    
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
	locale_dst="xlocales-$origin/$xlocales_prefix/$xlocales_infix/locale@$source/$locale@$origin"
	echo "LOCALES+=$locale_dst"
    done < "$src/supported"	>> "$src/Makefile"    
    echo 'all: $(LOCALES) $(PACKAGES)' >> "$src/Makefile"

    # generate the package target rule
    case "$xlocales_package" in
	deb)
	    echo '%.deb: $(LOCALES)' >> "$src/Makefile"
	    printf "\tdpkg-deb --root-owner-group -b \$(patsubst %%_${package_version}_${package_arch}.deb,%%,\$(notdir \$@)) \$(dir \$@)\n" >> "$src/Makefile"
	    ;;
    esac   

    # generate target for each locale
    while read -r locale charmap ; do
	locale="$(xlocales_gnu_munge_name "$locale")"
	locale_dst_dir="xlocales-$origin/$xlocales_prefix/$xlocales_infix/locale@$source"
	locale_dst="$locale_dst_dir/$locale@$origin"
	locale_src="localedata/$(echo "$locale" | cut -d. -f1)"

	echo "$locale_dst: $locale_src"
	
	# Cross-compiled locales with @origin modifiers are collected
	# under locales@source, so if you install xlocales-debian12
	# and xlocales-debian13 then /usr/lib/locales@debian will
	# contain both en_US.utf8@debian12 and en_US.utf8@debian13.
	printf "\t@mkdir -p $locale_dst_dir\n"
	printf "\tI18NPATH=./locales localedef -f $charmaps_dir/$charmap -i \$< \$@\n"

	# Symlinks with @glibcX.Y modifiers are also collected under
	# locale@glibc, or locale@glibc.SOURCE if SOURCE doesn't
	# matches the host OS.  For example, with two xlocales-debianN
	# packages installed on Debian, under /usr/lib/locale@glibc
	# you might see something lik en_US.utf8@glibc2.31 and
	# en_US.utf8@glibc2.34.
	if [ "$source" = "$xlocales_host_os" ] ; then
	    dst_dir="xlocales-$origin/$xlocales_prefix/$xlocales_infix/locale@glibc"
	else
	    dst_dir="xlocales-$origin/$xlocales_prefix/$xlocales_infix/locale@glibc.$source"
	fi
	printf "\t@mkdir -p $dst_dir\n"
	printf "\tln -f -s ../locale@$source/$locale@$origin $dst_dir/$locale@glibc$locale_version\n"

	# Likewise for @unicodeX.Y.Z, collated under locale@unicode or
	# locale@unicode.SOURCE for non-host sources.
	#
	# XXX In theory two major releases of an OS could use two
	# releases of glibc that use the same Unicode version.  You
	# won't be able to install them both, so it might become
	# necessary to disable this or put it in a separate package so
	# you can skip installing one of them?
	if [ "$source" = "$xlocales_host_os" ] ; then
	    dst_dir="xlocales-$origin/$xlocales_prefix/$xlocales_infix/locale@unicode"
	else
	    dst_dir="xlocales-$origin/$xlocales_prefix/$xlocales_infix/locale@unicode.$source"
	fi
	printf "\t@mkdir -p $dst_dir\n"
	printf "\tln -f -s ../locale@$source/$locale@$origin $dst_dir/$locale@unicode$unicode_version\n"	

	# Symlinks with no modifiers are collected under
	# locale.ORIGIN.  They hide the system locales of the same
	# names, if that directory is set as LOCPATH.
	dst_dir="xlocales-$origin/$xlocales_prefix/$xlocales_infix/locale.$origin"
	printf "\t@mkdir -p $dst_dir\n"
	printf "\tln -f -s ../locale@$source/$locale@$origin $dst_dir/$locale\n"

	# Optional symlinks to make eg en_US.utf8@debian12 available
	# without setting LOCPATH.  Packaged as xlocales-system-ORIGIN.
	dst_dir="xlocales-system-$origin/$xlocales_system_locales"
	printf "\t@mkdir -p $dst_dir\n"
	printf "\tln -f -s $xlocales_prefix/$xlocales_infix/locale@$source/$locale@$origin $dst_dir/$locale@$origin\n"

	# Optional extra symlinks to make eg en_US.utf8@glibc2.31 and
	# en_US.utf*@unicode13.0.0 available without setting LOCPATH.
	dst_dir="xlocales-system-extra-$origin/$xlocales_system_locales"
	printf "\t@mkdir -p $dst_dir\n"
	printf "\tln -f -s $xlocales_prefix/$xlocales_infix/locale@$source/$locale@$origin $dst_dir/$locale@glibc$locale_version\n"
	printf "\tln -f -s $xlocales_prefix/$xlocales_infix/locale@$source/$locale@$origin $dst_dir/$locale@unicode$unicode_version\n"

    done < "$src/supported" >> "$src/Makefile"
    printf "\r\033[K" >&2

    touch "$src/xlocales.configured"
}
