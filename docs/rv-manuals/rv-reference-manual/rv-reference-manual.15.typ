#import "../common/manual-lib.typ": *
#show: manual

= Hierarchical Preferences <ref-ch-hierarchical-prefs>

Each #app user has a Preferences file where their personal settings are
stored. Most preferences are viewed and edited with the Preferences dialog
(accessed via the #app menu), but preferences can also be programmatically
read and written from custom code via the readSetting and writeSetting Mu
commands. The preferences files are stored in different places on different
platforms.

#table(
    columns: (auto, 1fr),
    align: left,
    table.header[*Platform*][*Location*],
    [macOS], raw(names.prefs.macos),
    [Linux], raw(names.prefs.linux),
    [Windows], raw(names.prefs.windows),
)

Initial values of preferences can be overridden on a site-wide or show-wide
basis by setting the environment variable `RV_PREFS_OVERRIDE_PATH` to point
to one or more directories that contain files of the name and type listed in
the above table. For example, if you have your #app\.conf file under
\$HOME/Documents/ you can set `RV_PREFS_OVERRIDE_PATH`=\$HOME/Documents.
Each of these overriding preferences file can provide default values for one
or more preferences. A value from one of these overriding files will
override the users's preference only if the user's preferences file has no
value for this preference yet.

In the simplest case, if you want to provide overriding initial values for
all preferences, you should

+ Delete your preferences file.
+ Start #app, go to the Preferences dialog, and adjust any preferences you
  want.
+ Close the dialog and exit #app\.
+ Copy your preferences file into the `RV_PREFS_OVERRIDE_PATH`.

If you want to override at several levels (say per-site and per-show), you
can add preferences files to any number of directories in the PATH, but
you'll have to edit them so that each only contains the preferences you want
to override with that file. Preferences files found in directories earlier
in the path will override those found in later directories.

Note that this system only provides the ability to override initial settings
for the preferences. Nothing prevents the user from changing those settings
after initialization.

It's also possible to create show/site/whatever-specific preferences files
that *always* clobber the user's personal preferences. This mechanism is
exactly analogous to the above, except that the name of the environment
variable that holds paths to clobbering prefs files is
`RV_PREFS_CLOBBER_PATH`. Again, the user can freely change any “live” values
managed in the Preferences dialog, but in the next run, the clobbering
preferences will again take precedence. Note that a value from a clobbering
file (at any level) will take precedence over a value from an overriding
file (at any level).
