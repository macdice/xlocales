# XLOCALES

This is an experimental attempt to backport locales definitions from
older releases or different distributions, currently supporting glibc.
(Technique also works on FreeBSD; implementation to follow.)

# Example of usage

Glibc 2.34 changed weighting of W in Swedish, to make it distinct
from V, so we can use that for a very simple test:

    $ echo WA > file
    $ echo VB >> file

According to my Debian 13, glibc 2.41 system, V comes before W:

    $ LANG=sv_SE.UTF-8 sort file
    VB
    WA

If xlocales-debian11-system and xlocales-debian12-system are
installed, I can observe the change by using @debian modifiers:

    $ LANG=sv_SE.UTF-8@debian11 sort file
    WA
    VB
    $ LANG=sv_SE.UTF-8@debian12 sort file
    VB
    WA

These locales have only one intentional change made to them by the
xlocales scripts, other than being compiled with localedef 2.41 for
consumption by glibc 2.41.  It's the information appended after "1.0"
here:

    $ LANG=sv_SE.UTF-8@debian12 locale -k LC_IDENTIFICATION | grep revision
    revision="1.0; origin=debian12; unicode=14.0.0; localedata=2.36"

If xlocales-debian11-system-libc and xlocales-debian12-system-libc are
installed, I can also use @libc modifiers:

    $ LANG=sv_SE.UTF-8@libc2.31 sort file
    WA
    VB
    $ LANG=sv_SE.UTF-8@libc2.36 sort file
    VB
    WA

If xlocales-debian11 and xlocales-12 are installed without the
optional extra -system and -system-libc packages, then the
cross-compiled locales are only visible to libc by setting the LOCPATH
environment variable.

By pointing to locale.ORIGIN, I can use the standard names for locales
without any modifiers.  In that case, they hide the system locales:

    $ LOCPATH=/usr/lib/locale.debian11 LANG=sv_SE.UTF-8 sort file
    WA
    VB

By pointing to locale@ORIGIN, I can use either the @libc or @debian
modifier, but the normal system locales are not hidden:

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


## Building a subset

On a GNU/Linux system:

    $ ./xlocales list
    ORIGIN
    debian14
    debian13
    debian12
    debian10
    rocky10
    rocky9
    rocky8
    ...
    $ ./xlocales build rocky9 rocky10 ubuntu*

On a FreeBSD system:

    $ ./xlocales list
    ORIGIN       TAG
    freebsd15.0  release/15.0.0-p13
    freebsd14.5  release/14.5.0
    freebsd14.4  release/14.4.0-p9
    ...
    $ ./xlocales build freebsd14* freebsd13.4

## Installing

To create packages that install the locales under `/usr/lib/xlocales` (glibc) or
`/usr/locale/lib/xlocales` in .rpm, .deb or .pkg format as appropriate:

    $ ./xlocales build
    $ ./xlocales package

That creates a set of packages from the contents of `xlocales`, for example:

    xlocales-debian14
    xlocales-debian13
    xlocales-debian12
    xlocales-debian14-system
    xlocales-debian13-system
    xlocales-debian12-system

The optional `-system` packages add symlinks in the system default locale
search path, so that all programs can access them with modifiers such as
`en_US.utf8@debian13` without environment changes.

## Using backported locales

There are three main approaches:

- Setting the environment to use backported locales instead of the system
  locales
- Setting the environment to expose the backported locales with different names
  that have `@origin` or `@version` modifiers
- Installing the optional `xlocales-*-system` packages so that the default
  locale search path sees `@origin` and/or `@version` modifiers

The environment variable to set to affect just one process tree is `LOCPATH`
(glibc) or `PATH_LOCALE` (FreeBSD).  In the following sections, `XLOCALES`
stands for the choosen installation location.

### Replacing the system locales

If you set `LOCPATH`/`PATH_LOCALE` to `$XLOCALES/ORIGIN/locales`, non-modified names from `ORIGIN`  exposes
non-modified names from `debian12`, hiding system-provided locales of the same
name:

    export LOCPATH=$XLOCALES/debian13/locales

### Exposing origin modifiers

- 

## Local installation

A temporary local installation to test:

    $ ./xlocales build

That builds locales from every system the script knows about, and takes quite a
long time.  To see what it will build:

    $ ./xlocales list
    ORIGIN       TAG
    freebsd15.0  release/15.0.0-p13
    freebsd14.5  release/14.5.0
    freebsd14.4  release/14.4.0-p9
    ...many more...

Then you name the ones you're interested in:

    $ ./xlocales build freebsd14.4 freebsd14.3
 
    freebsd14.3  release/14.3.0-p16
    freebsd14.2  release/14.2.0-p7
    freebsd14.1  release/14.1.0-p8
    freebsd14.0  release/14.0.0
    freebsd13.5  release/13.5.0-p14
    freebsd13.4  release/13.4.0-p5
    freebsd13.3  release/13.3.0
    freebsd13.2  release/13.2.0
    freebsd13.1  release/13.1.0
    freebsd13.0  release/13.0.0


This creates a directory "xlocales" in the current directory.

A shared installation in /usr/local/lib:

    ./xlocales build
    sudo ./xlocales --prefix /usr/local install

This installs them as /usr/local/lib/xlocales.

Using packages:

    ./xlocales build
    ./xlocales package

This creates .deb, .rpm or .pkg files that can be installed.

USING BACKPORTED LOCALES

In these examples, $XLOCALES stands for the path to the top level directory.

1.  The system locales can be temporary replaced/hidden by setting an
environment variable:

LOCPATH=$XLOCALE/ubuntu20/locales                               (glibc)

PATH_LOCALE=$XLOCALE/freebsd13.0/locales                        (FreeBSD)

2.  Locale names with @origin modifier can be added to the search path:

2.1.  One or more origin:

LOCPATH=$XLOCALE/ubuntu20/origin-mod                            (glibc)
LANG=en_US.utf8@ubuntu20

PATH_LOCALE=/usr/share/locales:$XLOCALE/freebsd13.0/origin-mod  (FreeBSD)
LANG=en_US.UTF-8@freebsd13.0

2.2.  All available locales from an origin family:

LOCPATH=$XLOCALE/ubuntu/origin-mod                              (glibc)
LANG=en_US.utf8@ubuntu18
LANG=en_US.utf8@ubuntu20
LANG=en_US.utf8@ubuntu22

PATH_LOCALE=/usr/share/locales:$XLOCALE/freebsd/origin-mod      (FreeBSD)
LANG=en_US.UTF-8@freebsd13.0
LANG=en_US.UTF-8@freebsd14.2

2.3.  All available locales from all origins:

LOCPATH=$XLOCALE/all/origin-mod                                 (glibc)
LANG=en_US.utf8@ubuntu18
LANG=en_US.utf8@debian12
LANG=en_US.utf8@rocky10

PATH_LOCALE=/usr/share/locales:$XLOCALE/all/origin-mod          (FreeBSD)
LANG=en_US.UTF-8@freebsd13.0
LANG=en_US.UTF-8@freebsd14.2

3.  Locale names with @version modifier can be added to the search path:

3.1.  One or more version:

LOCPATH=$XLOCALE/ubuntu20/version-mod                            (glibc)
LANG=en_US.utf8@glibc2.35

PATH_LOCALE=/usr/share/locales:$XLOCALE/freebsd13.0/version-mod  (FreeBSD)
LANG=en_US.UTF-8@cldr34.0

3.2.  All available locales from an origin family:

LOCPATH=$XLOCALE/ubuntu/version-mod                              (glibc)
LANG=en_US.utf8@glibc2.28
LANG=en_US.utf8@glibc2.31
LANG=en_US.utf8@glibc2.35

PATH_LOCALE=/usr/share/locales:$XLOCALE/freebsd/version-mod      (FreeBSD)
LANG=en_US.UTF-8@cldr34.0
LANG=en_US.UTF-8@cldr48.2

4. Any or all of the 


All 
It can be used to make

The resulting tree of files is intended to be installed in a location such as
/usr/lib/xlocales or /usr/local/share/xlocales.  It has a subdirectory for each
"origin" system:

    glibc:

    xlocales/
      rocky8/
      rocky9/
      rocky10/
      ubuntu18/
      ubuntu20/
      ubuntu22/
      ubuntu24/
      ...

    FreeBSD:

    xlocales/
      freebsd13.0/
      freebsd13.1/
      freebsd13.2/
      ...

Each has a "locales" subdirectory that contains the complied locales with their
original names:

    xlocales/
      rocky8/
        locales/
          en_US.utf8/
            LC_COLLATE
            LC_CTYPE
            ...
          fr_FR.utf8/
            LC_COLLATE
            LC_CTYPE
            ...
     
It also contains directories of symlinks that have POSIX modifiers denoting the
origin and the version, providing alternative naming schemes:

    xlocales/
      rocky8/
        locales/
          en_US.utf8/
          ...
        origin-mod/
          en_US.utf8@rocky8 -> ../locales/en_US.utf8
          fr_FR.utf8@rocky8 -> ../locales/fr_FR.utf8
          ...
        version-mod/
          en_US.utf8@glibc2.28 -> ../locales/en_US.utf8
          fr_FR.utf8@glibc2.28 -> ../locales/fr_FR.utf8
          ...

Another tree of symlinks is provided to gather all locales from all origins
"families", eg all version of Rocky Linux, all versions of Ubuntu:

    xlocales/
      rocky/
        origin-mod/
          en_US.utf8@rocky8 -> ../rocky8/plain/en_US.utf8
          en_US.utf8@rocky9 -> ../rocky9/plain/en_US.utf8
          en_US.utf8@rocky10 -> ../rocky10/plain/en_US.utf8
          ...
        version-mod/
          en_US.utf8@glibc2.28 -> ../rocky8/plain/en_US.utf8
          en_US.utf8@glibc2.34 -> ../rocky9/plain/en_US.utf8
          en_US.utf8@glibc2.39 -> ../rocky10/plain/en_US.utf8
          ...
        all-mod/
          en_US.utf8@rocky8 -> ../rocky8/plain/en_US.utf8
          en_US.utf8@rocky9 -> ../rocky9/plain/en_US.utf8
          en_US.utf8@rocky10 -> ../rocky10/plain/en_US.utf8
          en_US.utf8@glibc2.28 -> ../rocky8/plain/en_US.utf8
          en_US.utf8@glibc2.34 -> ../rocky9/plain/en_US.utf8
          en_US.utf8@glibc2.39 -> ../rocky10/plain/en_US.utf8
          ...
      ubuntu/
        ...

A further tree has all origins from all families:

    xlocales/
      all/
        origin-mod/
          en_US.utf8@rocky8 -> ../rocky8/plain/en_US.utf8
          en_US.utf8@rocky9 -> ../rocky9/plain/en_US.utf8
          en_US.utf8@rocky10 -> ../rocky10/plain/en_US.utf8
          en_US.utf8@ubuntu18 -> ../ubuntu18/plain/en_US.utf8
          en_US.utf8@ubuntu20 -> ../ubuntu20/plain/en_US.utf8
          en_US.utf8@ubuntu22 -> ../ubuntu22/plain/en_US.utf8
          ...
 

Any of these directories can be added to the LOCPATH (glibc) or PATH_LOCALE
(FreeBSD) environment variable, to expose them to newlocale():

* add a single xlocales/ORIGIN/locales directory to replace the system locales
* add one or more of the *-mod directories to reveal the explicit modifier
  names

Another approach is provided to 

Alternatively, symlinks to the "version-mod" or "origin-mod" directories 

* create symlinks to the "version-mod" or "origin-mod" directories

Version strings are stored inside backported locales can be retrieved with:

    const char *version;
    locale_t loc;

    /*
     * FreeBSD: querylocale() returns values that match the ones in
     * FreeBSD's system-provided locales, as already queried by PostgreSQL and
       recorded in its catalogues.
     */
    loc = newlocale(LC_ALL_MASK, "en_US.utf8@freebsd13.0", 0);
    if (loc) {
        version = querylocale(LC_VERSION_MASK | LC_COLLATE_MASK, loc);
        if (version)
            printf("version = %s\n", version);

        /* prints: version = 34.0" */
    }

    /*
     * glibc: The LC_IDENTIFICATION category has an item called "revision", but
     * in most cases it is "1.0" and does not change.  xlocales appends
     * additional data to it: the "origin", the version of localedef that is
     * being used to compile it, and the glibc version that provided the
     * localedata.  In some distributions it might have been patched, so it
     * seems wise to record a bit more information while we're making up a new
     * convention.  The final part is comparable with the values that
     * PostgreSQL stores in its cataloges.
     */
    loc = newlocale(LC_ALL_MASK, "en_US.utf8@rocky8", 0);
    if (loc) {
        version = nl_langinfo_l(_NL_IDENTIFICATION_REVISION, loc);
        if (version)
            printf("version = %s\n", version);

        /* prints: 1.0; origin=rocky10; localedef=2.34; localedata=2.28 */
    }

This is useful for cross-checking, because newlocale() silently drops modifiers
if the locale can't be found, which seems a bit too fragile for this purpose.


A set of optional packages can also be generated that places "origin" and/or "version" symlinks 

Three mode of operation are envisaged:

1.  Hiding the default locales: by setting LOCPATH (glibc) or PATH_LOCALE
(FreeBSD) to /usr/share/

THE PROBLEM TO BE SOLVED

Software that uses POSIX's <locale.h> facilities to order persistent data
structures faces the problem that the underlying implementation might change
the order for any locale other than "C" or "POSIX" (binary sort order).

Modern POSIX systems provide locles based on Unicode and CLDR or a subset, in
some cases indirectly via ISO/IEC 15897 or other aligned standards.  The
underlying Unicode standards and data are constantly envolving.

https://en.wikipedia.org/wiki/Common_Locale_Data_Repository
https://en.wikipedia.org/wiki/ISO/IEC_15897

POSIX systems provide a localedef tool that reads source in a standardised
format, and produces unspecified output that is uderstood by the implementation
of <locale.h>:

https://pubs.opengroup.org/onlinepubs/9799919799.2024edition//basedefs/V1_chap07.html#tag_07

In actual implementations, the output is a binary data structure in one or many
files that libc maps into memory.  Its format might change between operating
system releases, so they are strictly non-portable.

THE THEORY OF THIS EXPERIMENT

Since the source format is standardised, if we take the liberty of assuming
that any non-standard extensions change incompatibly or disappear, it must be
possible to compile the locale source files from an earlier release of the same
operating system, and hope that libc to sorts strings in the same order on the
new system.

KNOWN PROBLEMS

* glibc doesn't respect the declared weight of the UNDEFINED block in the
  LC_COLLATE category, and might differ between versions (I'm not sure about
  of the details).  We can wave that particular issue away by reducing the
  scope of the project to characters defined by Unicode.

  (That's a bit weak, because we can't tell users not to use undefined code
  points when they don't even know which version of Unicode their libc is base
  on.  Code points they're actually using might be defined in a later Unicode
  release, and in any case there is no validation of definedness either in
  PostgreSQL or libc.  I don't know )

* Debian and Red Hat historically patched their glibc to define a C.UTF-8
  locale that intended to sort in code point order by simply listing every code
  point in order in LC_COLLATE, but the actual sort order produced varied from
  version to version due to various implementation bugs and changes; glibc 2.35
  eventually introduce a new special keyword to achieve efficient code point
  order without listing them; it does not seem to be possible to convince a
  modern glibc system to reproduce the old order.  Historical C.UTF-8 LC_COLLATE
  seems to be unsalvageable.

In general, "backporting" locales by compiling them with a newer localedef and
using them with a newer strcoll_l() can't hide fundamental changes due to
historical bugs that are not presented in the locale data.

LC_COLLATE block, which glibc or at least some versions don't respect.
When a bug like that is fixed, you can't expect stability.  We can wave that
particular issue away by reducing the scope to defined code points only.
(That's a bit weak, because we can't tell users not to use undefined code
points when they don't even know which version of Unicode their libc is base
on, and code points they're actually using might be defined in a later Unicode
release, and there is no validation of definedness either in PostgreSQL or
libc.  But assuming that you don't 


take

You should be able to compile at least older 

In theory, we should then be able to take the sources from each operating system release, and compile 

AWARENESS

The first step is to know when the rules change.  POSIX doesn't inlucde t


OTHER POSIX IMPLEMENTATIONS

* musl, openbsd and netbsd just punt strcoll() to strcmp(), so there is
  currently no point, at least as far as LC_COLLATE goes, our primary
  interest

* macos seems almost feasible, but...

  History: In v79 of Apple adv_cmds, localedef was a perl script, and in that
  era strcoll() was taken from very old pre-Unicode FreeBSD libc, and the
  locale sources were here:

  https://github.com/apple-oss-distributions/adv_cmds/tree/rel/adv_cmds-79/usr-share-locale.tproj

  In modern Apple adv_cmds, localedef is Garrett D'Amore's
  implementation.  Nice.  It was developed for illumos (OpenSolaris never
  shipped Sun's localedef/strcoll/etc, licences, lawyers?, so the illumos crew
  had to write a new one), which was imported by FreeBSD 11 to gain Unicode
  support, and Apple is clearly getting it from FreeBSD because it has has the
  -V option from FreeBSD 13+.  That stores a version string that is retrievable
  with querylocale(LC_VERSION_MASK | LC_COLLATE_MASK, locale).

  https://github.com/apple-oss-distributions/adv_cmds/tree/main/localedef

  Problem #1: they no longer publish the locale source files!  Or not in
  the adv_cmds package, anyway.  Anyone know where they can be found?
  They presumably have D'Amore's scripts for converting from CLDR to
  locale source files, hopefully FreeBSD's fork of them that sticks
  CLDR_VERSION into the Makefile, and xlocales would need those files
  for each release of macOS.

  Problem #2: they have FreeBSD's querylocale() (which FreeBSD itself
  originally got from Apple), but they have stripped out the LC_VERSION_MASK
  support leaving just a comment:

  https://github.com/apple-oss-distributions/Libc/blob/main/locale/xlocale.c

* illumos seems to be taking backports of some things from FreeBSD, but does
  not have querylocale() and has not backported -V:

  https://github.com/illumos/illumos-gate/blob/master/usr/src/cmd/localedef/localedef.c

  So, see next...

* AIX and Solaris presumably have industrial strength POSIX localedef and the
  locale source are presumably available, but POSIX <locale.h> provides no
  way to query the version.  I think you'd have to invent a convention,
  perhaps an LC_MESSAGES key, or hide it in a nl_langinfo_l(ERA, locale) or
  something like that, and PostgreSQL would need to learn how to read it.

IMAGINING STANDARDISED VERSION SUPPORT IN POSIX

* The grammar for localedef could have a simple version declaration:

  LC_COLLATE
  version "34.1"
  ...
  END LC_COLLATE

  LC_CTYPE
  version "12.0"
  ...
  END LC_CTYPE

  LC_TIME
  version "1.0"
  ...
  END LC_TIME

* It would be nice if <locale.h> provided a way to retrieve that string.
  Following the example of POSIX:2024 getlocalename_l(), perhaps it could be:

  const char *getlocaleversion_l(int category, locale_t loc);

  The point of this would be to be able to know what you *actually* opened when
  using modifiers like "en_US.UTF-8@collate_version_34.1".

* I wrote to the Austin Group about this:

  https://www.mail-archive.com/austin-group-l@opengroup.org/msg12849.html
