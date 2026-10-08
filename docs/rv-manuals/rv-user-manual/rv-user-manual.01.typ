#import "../common/manual-lib.typ": *
#show: manual

= Introduction

== Overview

#app and its companion tools, #ioapp and #lsapp have been created to
support digital artists, directors, supervisors, and production crews who
need reliable, flexible, high-performance tools to review image sequences,
movie files, and audio. #app is clean and simple in appearance and has been
designed to let users load, play, inspect, navigate and edit image
sequences and audio as simply and directly as possible. #app's advanced
features do not clutter its appearance but are available through a rich
command-line interface, extensive hot keys and key-chords, and smart
drag/drop targets. #app can be extensively customized for integration into
proprietary pipelines. The #app Reference Manual has information about #app
customization.

This chapter provides quick-start guides to #app and #iocmd. If you already
have successfully installed #app, and want to get going right away, this
chapter will show you enough to get started.

== Getting Started With #app

=== Loading Media and Saving Sessions
There are four basic ways to load media into #app,

+ On the Command Line
+ Via the #menu(("File","Open")) Dialog
+ Drag and Drop Onto a Session Window
+ Clicking on an #inline-shell("rvlink:") Protocol URL

#app can load individual files or multiple files (i.e. a sequence) and it
can also read directories and figure out the sequences they contain; you
can pass #app a directory on the command-line or drag and drop a folder onto
#app. #app's ability to read directories can be particularly useful. If your
shots are stored as one take per directory you can get in the habit of just
dropping directories into #app or loading them on the command line. Or you
can quickly load multiple sequences or movies that are stored in a single
directory.

Command line examples that load media into #app:

#appshell(
    "foo.mov",
    "[ foo.#.exr foo.aiff ]",
    "foo_dir/",
    ".",
)

when in doubt about command line options:

#appshell("-help")

#app sessions can be saved out as #inline-shell(".rv") files using the
#menu(("File","Save")) menus. Saved sessions contain the default views,
user-defined views, color setup, compositing setup, and other
settings. This is useful for reloading and sharing sessions, and also for
setting up image conversion, compositing, or editing operations to be
processed by #iocmd.

=== Caching

If your image sequences are too large to play back at speed directly from
disk, you can cache them into system memory using #app's _region cache_ . If
you are playing compressed movies like large H.264 QuickTime movies, you
can use #app's _lookahead cache_ to smooth out playback without having to
cache the entire movie. If your IO subsystems can provide the bandwidth, #app
can be used to stream large uncompressed images from disk. You can set the
#app cache options from the #menu("Tools") menu, using the hot keys 
#key("Shift+C") and #key("Ctrl+L") (#key("Command+L") on Mac) 
for the region cache and lookahead cache respectively, or from the command
line using #inline-shell("-c") or #inline-shell("-l") 
flags. Also see the Caching tab of the Preferences dialog.


=== Sources and Layers

#app gives you the option to load media (image sequences or audio) as a
 _source_ or a _layer_ . A source is a new sequence or movie that gets
 added to the end of the default sequence of the #app session. Adding sources
 is the simplest way to build an edit in #app. Layers are the way that #app
 associates related media, e.g. an audio clip that goes with an EXR
 sequence can be added as a layer so that it plays back along with the
 sequence. Layers make it very simple to string together sequences with
 associated audio clips–each movie or image sequence can be added as source
 with a corresponding audio clip added as a layer (see soundfile
 commandline example above). #app's stereoscopic display features can
 interpret the first two image layers in a source as left and right views.

=== #app Views

#app provides three default views, and the ability to make views of your
own. The three that all sessions have are the Default Sequence, which shows
you all your sources in order, the Default Stack, which shows you all your
sources stacked on top of one another, and the Default Layout, which has
all the sources arranged in a grid (or a column, row, or any other custom
layout of your own design). In addition to the default views, you can
create any number of Sources, Sequences, Stacks, and Layouts of your
own. See #xref(<ch-session>)[Chapter 5] for information
about the process of creating and managing your own views.

=== Marking and Navigating

#app's timeline (hit #key("Tab") or #key("F2") to bring it up) can be
_marked_ to make it easy to navigate around #a-app session. #app can mark
sequence boundaries automatically, but you can also use the #key("m")
key to place marks anywhere on the timeline. Once a session is marked you
can use hot keys to quickly navigate the timeline,
e.g. #key("Ctrl+Right-Arrow") (or #key("Command+Right-Arrow") on Mac)
will set the in/out points to the next pair of marks so you can loop over
that part of the timeline. If no marks are set, many of these navigation
options interpret the boundaries between sources as “virtual marks”, so
that even without marking you can easily step from one source to the next,
etc.

=== Color

#app provides fine grained control over color management. Subsequent sections
of this manual describe the #app color pipeline and options with a fair
amount of technical detail. #app supports file LUTs and CDLs per source and
an overall display LUT as well as a completely customizable 'source setup'
function (described in the Reference Manual). For basic operation,
however, you may find that the built in hardware conversions can do
everything you need. A common example is playing a QuickTime movie that has
baked-in sRGB together with an EXR sequence stored as linear floating
point. #app can bring the QuickTime into linear space using the menu command
#menu(("Color","sRGB")) and then the whole session can be displayed to the monitor
using the menu command #menu(("View","sRGB")).

=== Menus, Help and Hot Keys

#menu(("Help","Show","Show Current Bindings")) will print out all of #app's
current key bindings to the shell or console (these are also included in
chapter X of this manual). #app's menus can be reached through the menu bar
or by using the right mouse button. Menus items with hot keys will display
the hot key on the right side of the menu item. Some hot keys worth
learning right away are:

#key-table(
    key("Space"), [Toggle playback],
    [#key("Tab") or #key("F2")], [Toggle Show Timeline],
    key("i"), [Toggle Show Info Widget],
    key("`"), [(back-tick) Toggle Full Screen],
    key("F1"), [Toggle Show Menu],
    key("Shift+Left-Click"), [Open Pixel Inspector at pointer],
    key("q"), [to quit #app (or close the current session)]
)

=== Parameter Editing and Virtual Sliders

Many settings in #app, like exposure, volume, or frame rate, can be changed
quickly using Parameter Edit Mode. This mode lets you use virtual sliders,
the mouse wheel or the keyboard to edit #app parameters. Hot keys and
Parameter Editing Mode allow artists to easily and rapidly interact with
images in #app. It is worth a little practice to get comfortable using
these tools. For example, to adjust the exposure setting of a sequence you
can use any of the following techniques:

+ Hit the #key("e") key to enter exposure editing mode 
+ Click and drag left or right to vary the exposure, and then release the mouse button to leave the mode
+ _OR_ Roll the mouse wheel to vary the exposure and then hit #key("Return") to leave the mode.
+ _OR_ Hit #key("Return"), type the new exposure value at the prompt, and hit #key("Return") again (typing #key(".") or any digit also starts this text-entry mode)
+ _OR_ Use the #key("+") and #key("-") keys to vary the exposure and then hit #key("Return") to leave the mode.

Some advanced usage:

- Use the #key("r") #key("g") #key("b") keys to edit individual color channels. (#key("c") to return to editing all 3 channels.) Parameters that can be “unganged” in this way will display a 3-color glyph in the display feedback when you start editing.
- Hit the #key("l") to lock (or unlock) slider mode, so that you can repeatedly set the same parameter (#key("Escape") to exit).
- The #key("Delete")' or #key("Backspace") key will reset the parameter to it's default value.
- When multiple Sources are visible, as in a Layout view, parameter sliders will affect all Sources. Or you can use #key("s") to select only the source under the pointer for editing.

Some parameters in #app don't use virtual sliders; you can edit these directly by entering the new value, e.g. to change the playback frames per second:

+ Hit #key("Shift+F")
+ Type in the new frame rate at the prompt and hit #key("Return")

Some other useful parameters and their hot keys:

#key-table(
    key("y"), [Gamma],
    key("h"), [Hue],
    key("k"), [Contrast],
    [#key("Ctrl+v") or #key("Command+v") on Mac], [Audio Volume]
)

=== Preferences and Command Line Parameters

#app's preferences can be opened with the #menu((app,"Preferences")) menu item. These
are worth exploring in some detail. They give you fine control over how #app
loads and displays images, handles color, manages the cache, handles audio,
etc. #app's preferences map to #app's command line options, so almost any
option available at the command line can be set to a preferred default
value in the preferences. #app also has a #inline-shell("-noPrefs") command
line flag so that you can temporarily ignore the preferences, and a
#inline-shell("-resetPrefs") flag that will reset all preferences to their
default values. #inline-shell("-help") will display all options:

#appshell("-help")

=== Customizing #app

#app is built to be customized. For many users, this may be completely
ignored or be limited to sharing startup scripts and packages created by
other users. A package is a collection of script code (Mu or Python) and
interface elements which can be automatically loaded into #app. A package can
be installed site wide, per-show, or per-user and a command line tool
(#pkgcmd) is included for package administration tasks.

#app Packages are discussed in #xref(<ch-packages>)[Chapter 10].

Customization is discussed in detail in the _#app Reference Manual_. The #app
command API technical documentation can be browsed from
#menu(("Help","Mu")) API browser (select *commands* in the first column).

== Getting Started with #ioapp

=== Converting Sequences and Audio

#ioapp is a powerful pipeline tool. Like #app, the basic operation of
#ioapp is very simple, but advanced (and complex) operations are
possible. #ioapp can be used with a command line very similar to #app's,
with additional arguments for specifying the output. Any number of sources
and layers can be given to #ioapp using the same syntax as you would use
for #app. Some basic #ioapp command line examples are:

#ioshell(
    "foo.exr -o foo.mov",
    "foo.exr -o foo.mov",
    "[ foo.#.exr foo.aiff ] -o foo.mov",
    "[ foo_right.#.exr  foo_left.#.exr foo.aiff ] -outstereo -o foo.mov",
)

And of course:

#ioshell("-help")

#ioapp usage is more fully described in #xref(<ch-rvio>)[Chapter 16].

=== Processing UTV Session Files

#ioapp can also take #app session files (#inline-shell(".rv") files) as input. #app session
files can contain composites, color corrections, LUTs, CDLs, edits, and
other information that might be easier to specify interactively in #app
than by using the command line. #app session files can be saved from #app
and then processed with #ioapp. For example

#ioshell("foo.rv -o foo_out.#.exr")

When #ioapp operates on a session file, any of the views defined in the
session file can be selected to provide #iocmd's output, so a single
session could generate any number of different output sequences or movies,
depending on which of the session's views you choose.

=== Slates, Mattes, Watermarks, etc

#ioapp uses Mu scripts to create slates, frame burn-in and other operations
that are useful for generating dailies, client reviews and other
outputs. These scripts are usable as is, but they can also be modified or
replaced by users. For example:

#ioshell(
    "foo.#.exr -overlay watermark \"For Client Review\" 0.5 -o #foo.mov",
    "foo.#.exr -leader simpleslate \"Tweak Films\" \"Artist=Jane Doe\" \"Shot=SC101_vfx_01\" \"Notes=Lighter/Darker\" -o foo.mov",
)
