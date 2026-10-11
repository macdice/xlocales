#!/bin/sh

XLOCALES_SOURCE="alma"
XLOCALES_RPM_MIN_VERSION=10
XLOCALES_RPM_REPO_URL1="https://repo.almalinux.org/almalinux/@VERSION@/AppStream/x86_64_v2/os"
XLOCALES_RPM_REPO_URL2="https://vault.almalinux.org/@VERSION@/AppStream/x86_64_v2/os"
XLOCALES_RPM_PACKAGE="glibc-locale-source"

. "./xlocales-get-rpm.sh"
