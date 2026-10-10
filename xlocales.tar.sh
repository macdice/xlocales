xlocales_tar_origin()
{
    origin="$1"

    src="$xlocales_src/$origin"
    stage="$xlocales_stage/$origin"
    
    if [ ! -e "$stage/done" ] ; then
        xlocales_stage_origin "$origin"
    fi

    package_version="$(cat "$src/package.version")"
    package_url="$(cat "$src/package.url")"
    tarball="xlocales-${origin}-data_${package_version}.tgz"

    tar --owner=root --group=root -czf "$tarball" -C "$stage/xlocales-data" .
    echo "$tarball"
}
