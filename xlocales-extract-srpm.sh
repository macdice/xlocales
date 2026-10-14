#!/bin/sh
#
# Unpack a glibc source RPM, apply all maintainer patches in case they
# tweaked either locales or SUPPORTED, and run configure to generate
# the locale data files.
#
# It would be nice to get them ready-made from a binary package like
# glibc-locale-source (sometimes known as glibc-i18n[-data] etc), as
# we can for Debian's "locales", but unfortunately the RHEL-ish
# distros don't include the SUPPORTED file so we have to jump through
# this extra hoop.
#
# Trying to grok RPM spec syntax with a shell script would be a bit
# fragile, so we'll need the rpm tools as a build dependency to
# package this on a non-RPM system.

file="$1"

tmp="$(pwd)/rpmbuild_tmp"
spec="$tmp/SPECS/glibc.spec"

rm -fr "$tmp"

for dir in SOURCES BUILD SPECS ; do
    mkdir -p "$tmp/$dir"
done

rpm --quiet -iv --define "_topdir $tmp" "$file"
rpmbuild --quiet -bp --nodeps --quiet --define "_topdir $tmp" "$spec"

src_dir="$(sed -n 's|%.* \(glibc-.*\)$|\1|p' "$spec" | head -1)"
if [ -z "$src_dir" ] ; then
    echo "couldn't find source directory in $spec" >&2
    exit 1
fi

# Avoid complaints about missing tools that will never be used...
export MAKEINFO="$tmp/dummy_makeinfo"
echo "#!/bin/sh" > "$MAKEINFO"
echo "echo 'GNU texinfo.dummy 7.3'" >> "$MAKEINFO"
chmod +x "$MAKEINFO"

mkdir "$tmp/BUILD/$src_dir-build/tmp"
(
    cd "$tmp/BUILD/$glibc_src-build/tmp"
    ../"$src_dir"/configure --quiet --prefix=/tmp/dummy --srcdir="../$src_dir" --disable-sanity-checks
)

ln -s "$tmp/BUILD/$src_dir-build/$src_dir/localedata" "localedata"
