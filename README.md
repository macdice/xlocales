# XLOCALES

This is an experimental attempt to compile locales definitions from
older releases or different distributions, currently supporting glibc.
(Technique also works on FreeBSD; implementation to follow.)

# Example of usage

Glibc 2.34 changed the weighting of W in Swedish to make it distinct
from V, so we can use that for a very simple test:

    $ echo WA >> file
    $ echo VB >> file

According to Debian 13 (glibc 2.41), V comes before W:

    $ LANG=sv_SE.UTF-8 sort file
    VB
    WA

If xlocales-debian11-system and xlocales-debian12-system are
installed, I can observe the historical change by adding modifiers:

    $ LANG=sv_SE.UTF-8@debian11 sort file
    WA
    VB
    $ LANG=sv_SE.UTF-8@debian12 sort file
    VB
    WA

These locales have only one intentional change made to them by the
xlocales scripts, other than being compiled with the newer host
localedef for consumption by the host glibc, namely the identification
information appended after "1.0" in the revision string:

    $ LANG=sv_SE.UTF-8@debian12 locale -k LC_IDENTIFICATION | grep revision
    revision="1.0; origin=debian12; unicode=14.0.0; localedata=2.36"

If xlocales-debian11-system-libc and xlocales-debian12-system-libc are
also installed, I can also use @libc modifiers to select between them:

    $ LANG=sv_SE.UTF-8@libc2.31 sort file
    WA
    VB
    $ LANG=sv_SE.UTF-8@libc2.36 sort file
    VB
    WA

If xlocales-debian11 and xlocales-debian12 are installed without the
optional extra -system and -system-libc packages, then the
cross-compiled locales are only visible to libc if I set the LOCPATH
environment variable.

By setting it to locale.ORIGIN, I can use the standard names for
locales without modifiers.  This means that they hide the normal
system locales completely:

    $ LOCPATH=/usr/lib/locale.debian11 LANG=sv_SE.UTF-8 sort file
    WA
    VB

By pointing to locale@ORIGIN, I can use either the @libc or @debian
modifier, and the normal system locales are still available without
modifiers:

    $ LOCPATH=/usr/lib/locale@debian11 LANG=sv_SE.UTF-8@debian11 sort file
    WA
    VB

# Fetching glibc locale data

Three scripts are available to fetching glibc locale data from several
distributions.

## Fetching directly from gnu.org

See which "origins" are available from gnu.org:

    $ ./xlocales-fetch-glibc.sh --list
    glibc2.44
    glibc2.43
    glibc2.42
    glibc2.41
    glibc2.40
    ...

Fetching from one origin:

    $ ./xlocales-fetch-glibc.sh glibc2.44
    share/i18n.glibc2.44

The name of a newly created directory is printed, and it contains
locales and charmaps subdirectories along with some meta-data files
including xlocales.supported, which controls the combinations of
locales and codesets that should be produced.

To fetch all available from gnu.org, above a supported minimum, leave
off the version part:

    $ ./xlocales-fetch-glibc.sh glibc
    share/i18n.glibc2.44
    share/i18n.glibc2.43
    share/i18n.glibc2.42
    ...

## Fetching from .rpm and .deb-based distributions

These works the same way, except --list by itself now shows available
sources:

    $ ./xlocales-fetch-deb.sh --list
    debian
    ubuntu

    $ ./xlocales-fetch-rpm.sh --list
    almalinux
    amzn
    azurelinux
    centos
    fedora
    opensuse
    rocky

To see the major versions from one source, and the packages that would
be used:

    $ ./xlocales-fetch-deb.sh --list debian
    debian13 (locales 2.41-12+deb13u4)
    debian12 (locales 2.36-9+deb12u14)
    debian11 (locales 2.31-13+deb11u11)
    debian10 (locales 2.28-10+deb10u1)

    $ ./xlocales-fetch-rpm.sh --list rocky
    rocky9 (glibc-locale-source 2.34-283.el9_8)
    rocky10 (glibc-locale-source 2.39-142.el10_2)

The configuration for each package repository can be found in the
deb_sources and rpm_sources directories (patches welcome).

One motivation for using files from distributions instead of gnu.org
is that they are sometimes patched.  Differences between fetched
locale data and the corresponding upstream glibc version can be seen
with:

    $ ./xlocales-diff.sh debian11

Differences between any two origins can be seen by naming them both:

    $ ./xlocales-diff.sh debian11 debian12

# Compiling locales

To compile share/i18n.debian12:

    $ ./xlocales-gen.sh debian12

By default this compiles locales from share/i18n.debian12, and writes
output to lib/locale.debian12, but the directories can be overridden
with --input-dir and --output-dir options.

# Building packages

## Debian packages

Packages that should be installable on any .deb-based system can be
built with:

    $ ./xlocales-make-deb.sh

It scans share for i18n.ORIGIN directories, and builds several
packages for each ORIGIN that has been fetched and places them under
deb_packages.  Packages that already exist there are not rebuilt.

There are two ways to install cross-compiled locales.  It can be done
on installation using these architecture-independent packages:

- xlocales-ORIGIN-data: contains /usr/share/i18n.ORIGIN
- xlocales-ORIGIN-gen: compiles to /usr/share/locale.ORIGIN on installation

Or it can be done using an architecture- and OS-specific package that
is only generated if --precompiled is specified:

- xlocales-ORIGIN: contains precompiled locales in /usr/lib/locale.ORIGIN

The result is a set of locales in /usr/lib/locale@ORIGIN and
/usr/lib/locale.ORIGIN, which can be made visible to libc by setting
the LOCPATH environment variable.  The names in locale@ORIGIN have
@ORIGIN and @libcX.Y modifiers, and the names in locale.ORIGIN have no
modifiers, so they hide the system locales of the same name.

Two optional packages also make the locales visible to all programs by
default without needing an environment change:

- xlocales-ORIGIN-system: places @ORIGIN symlinks in /usr/lib/locale
- xlocales-ORIGIN-system-libc: places @libcX.Y symlinks in /usr/lib/locale

XXX TODO: Should produce source packages instead of using dpkg-deb.

## RPM packages

XXX TODO Not yet implemented

## FreeBSD packages

XXX TODO Not yet implemented
