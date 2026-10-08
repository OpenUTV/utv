#import "../common/manual-lib.typ": *
#show: manual

= Packages <ch-packages>

There are multiple ways to customize and extend #app, and almost all these
ways can be encapsulated in #a-app Package. A package is a zip file with
source or binary code that extends #app's feature set. Packages are
constructed so that they can be automatically installed and removed. This
makes it much easier for you to maintain #app than if you modify #app source
directly. (Note: although packages are zip files, they are labeled with a
#inline-shell(".rvpkg") extension to prevent mail programs, etc, from
automatically unzipping them.)

Packages can encapsulate a wide variety of features: everything from setting
the title of the window automatically to implementing a paint annotation
package. Some of #app's internal code is also in package form prior to
shipping: e.g. the entire remote sync feature is initially constructed as a
package of Mu source code (but is permanently installed when shipped).

The package manager can be found in the preferences dialog. There are two
sections to the user interface: the list of packages available and the
description of the selected package. Some packages may be "hidden" by
default; to see those packages toggle the show hidden packages button. To
add and remove packages use the add and remove buttons located at the bottom
left.

The Reference Manual contains detailed information about how to create a
package.

== Package Support Path

When a package is added, a list of permissible directories in the support
path is presented. At that time you can choose which support directory to
add the package to. When #app starts, these directories are automatically
added to various paths (like image I/O plugins).

By default, #app will include the application directory's plug-ins directory
(which is probably not writable by the user) and one of the following which
is usually writable by the user:

#table(
    columns: 2,
    align: left,
    table.header[*OS*][*User support directory*],
    [macOS],   `~/Library/Application Support/RV`,
    [Linux],   `~/.rv`,
    [Windows], `%APPDATA%\RV`,
)

You can override the default support path locations by setting the
environment variable `RV_SUPPORT_PATH`. The variable contents should be the
usual colon (Linux and Mac) or semicolon (Windows) separated list of
directories. The user support directory is not included by default if you
set the `RV_SUPPORT_PATH` variable, so be sure to explicitly include it if
you want #app to include that path. Also note that the support path elements
will have subdirectories called `Mu`, `Packages`, etc. In particular, when
using the support path to install Packages, you want to include the
directory above `Packages` in the path, not the `Packages` subdirectory
itself.

The file system of each directory in the support path contains these
directories:

#table(
    columns: (auto, 1fr),
    align: left,
    table.header[*Directory*][*Contents*],
    `Packages/`,     [Package zip files],
    `ConfigFiles/`,  [Area used by packages to store non-preference configuration information],
    `ImageFormats/`, [Image format plug-ins],
    `MovieFormats/`, [Movie format plug-ins],
    `Mu/`,           [Mu files implementing packages],
    `Output/`,       [Output plug-ins (audio/video)],
    `MediaLibrary/`, [Media library plug-ins],
    `Python/`,       [Python files implementing packages],
    `SupportFiles/`, [Additional files used by packages (icons, etc)],
    `lib/`,          [Shared libraries required by packages],
)

#app will create this structure if it's not already there the first time you
add or install a package.

== Installation

To add a package:

+ Open the Package Manager.
+ In the Packages tab, click *Add Packages…*
+ Navigate to the package's #inline-shell(".rvpkg") file.

#figure(
    img("rv-user-manual-51-rv-cx-ase-packagesShot-50.jpg"),
    caption: [Package Manager],
)

#quote(block: true)[
    *Tip:* When you are troubleshooting packages you have installed, enable
    the *Show Hidden Packages* checkbox.
]

Once a package has been added, to install or uninstall simply click on the
check box next to the name. The package is installed in the same support
directory in which it was added.

A package can be added, removed, installed, and uninstalled for all users or
by a single user. Usually administrator privileges are necessary to operate
on packages system wide. When a package is added (the #inline-shell(".rvpkg")
file) it is copied into a known location in the support path.

It's best to avoid editing files in these locations because #app tries to
manage them itself. When a package is installed the contents will be
installed in directories of the support directory.

When first installed, packages are loaded by default. To prevent a package
from loading uncheck the load check box. This is useful for installed
packages which are not uninstallable because of permissions. While the
install status of a package is universal to everyone that can see it, the
load status is per-user.

#quote(block: true)[
    *Note:* A restart of #app is required before a change in a package's
    Installed or Loaded state takes effect.
]

Packages can also be managed from the command line with the #raw(pkgcmd)
tool.

== Package Dependencies

Packages may be dependent on other packages. If you select a package to be
installed but it requires that other packages be installed as well, #app
will ask you if it can install them immediately. A similar situation can
occur when setting the load flag for a package. When uninstalling/unloading
the opposite can happen: a package may be required by another that is
"using" it. In that case #app will ask to uninstall/unload the dependent
packages as well.

Some packages may require a minimum version of #app. If a package requires a
newer version, #app shouldn't allow you to install it.

In some cases, manual editing of the support directory may lead to a
partially installed or uninstalled package. The package manager has a
limited ability to recover from that situation and will ask for guidance.
