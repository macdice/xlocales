#!/bin/sh

XLOCALES_SOURCE="azurelinux"
XLOCALES_RPM_REPO_URL1="https://packages.microsoft.com/yumrepos/azurelinux-@VERSION@-prod-base-x86_64"
XLOCALES_RPM_REPO_URL2="https://packages.microsoft.com/yumrepos/cbl-mariner-@VERSION@-prod-base-x86_64"
XLOCALES_RPM_PACKAGE="glibc-locale-source"
XLOCALES_RPM_MIN_VERSION=2.0
XLOCALES_RPM_PACKAGE="glibc-i18n"

. "./xlocales-get-rpm.sh"

