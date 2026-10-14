#!/bin/sh

file="$1"
src_dir="$(basename "$file" .tar.xz)"
top="$(pwd)"

tar xf "$file"

mkdir build
cd build
../$src_dir/configure --quiet --prefix=/tmp/dummy --srcdir "../$src_dir" --disable-sanity-checks MAKEINFO="$top/xlocales-texinfo.sh"
ln -s $src_dir/localedata ../localedata
