#!/bin/sh
#
# Fetch locale data from CentOS glibc-locale-source packages.

XLOCALES_SOURCE="centos"
#XLOCALES_RPM_REPO_META_URL="https://mirrors.centos.org/metalink?repo=centos-@VERSION@&arch=x86_64"
XLOCALES_RPM_REPO_URL1="https://vault.centos.org/centos/@VERSION@/BaseOS/x86_64/os"
XLOCALES_RPM_PACKAGE="glibc-locale-source"
XLOCALES_RPM_MIN_VERSION=8

. "./xlocales-get-rpm.sh"
