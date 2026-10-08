#import "../common/manual-lib.typ": *
#show: manual

= Command Line Usage <ch-command-line>

In this chapter, the emphasis will be on using the software from a Unix-like
shell. On Windows, this can be done via Cygwin's bash shell or tcsh. If you
choose to use the command.com shell, the command syntax will be the same,
but some features (like pattern matching, etc.) which are common with Unix
shells may not work.

To use #app from a shell, you will need to have the binary executable in
your path. On Linux and Windows the #app executable is located in the
#inline-shell("bin") directory of the install tree.

On macOS this can be done by including
#raw("/Applications/" + app + ".app/Contents/MacOS") in your path (assuming
you installed #app there). The executable on macOS is called #raw(app)\; you
can either type the name in as is or create an alias or symbolic link from
#raw(appcmd) to #raw(app).

There are a number of ways to start #app from the command line:

#code-block(
    appcmd + " options",
    appcmd + " options source1 source2 source3 ...",
    appcmd + " options [ source1 source2 ... ] [ source4 source5 ... ]",
    appcmd + " options [ source-options source1 source2 ... ] [ source-options source4 source5 ... ]",
    appcmd + " file.rv",
)

The command line options are not required and may appear throughout the
command line. Sources are individual images, QuickTime #inline-shell(".mov")
files, #inline-shell(".avi") files, audio files, image sequences or directory
names. When specifying a #inline-shell(".rv") file, no other sources should
be on the command line (see @command-line-options).

The third example above uses square brackets around groups of sources. When
sources appear between brackets they are called layers. These will be
discussed in more detail below.

If #app is started with no arguments, it will launch a blank window; you can
later add source material to the window via file browser or drag and drop.

Options are all preceded by a dash (minus sign) in the Unix tradition, even
on Windows. Some of them take arguments and some of them are flags which
toggle the associated feature on or off. For example:

#appshell("-fullscreen foo.mov")

plays back a movie file in full screen mode. In this case
#inline-shell("-fullscreen") is a toggle which takes no arguments and
#inline-shell("foo.mov") is one of the source material. If an option takes
arguments, you supply them directly after the option:

#appshell("-fps 23.97 bar.#.exr")

Here the #inline-shell("-fps") option (frames per second) requires a single
floating point number#footnote[A floating point number in this context means
a number which may or may not have a decimal point. E.g., 10 and 10.5 are
both floating point numbers.]. With rare exception, #app's options are
either toggles or take a single argument.

The most important option to remember is #inline-shell("-help"). The help
option causes #app to print out all of the options and command line syntax
and can be anywhere in a command line. When unsure of what the next argument
is or whether you can add more options to a long command line, you can
always add #inline-shell("-help") onto the end of your command and
immediately hit enter. At that point, #app will ignore the entire command
and print the help out. You can always use your shell's history to get the
command back, remove the #inline-shell("-help") option, and continue typing
the rest of the command.

#code-block(
    "shell> " + appcmd + " -fps 30 -fullscreen -l -lram .5 -help",
    "(" + appcmd + " shows help)",
    "Usage: " + app + " movie and image viewer",
    "...",
    "(hit up arrow in shell, back up over -help and continue typing)",
    "shell> " + appcmd + " -fps 30 -fullscreen -l -lram .5 -play foo.mov",
)

Finally, you can do some simple arithmetic on option arguments. For example
if you know you want to apply an inverse gamma of 2.2 to an image to view it
you could do this:

#appshell("-gamma 1/2.2")

which is identical to this:

#appshell("-gamma 0.454545454545")

== Troubleshooting #app

Launching #app from the command line is the best way to troubleshoot #app
by giving you access to error messages or crash dumps.

You can also access the logs at the following locations:

#table(
    columns: 2,
    align: left,
    table.header[*OS*][*Logs location*],
    [Linux],   raw("~/.local/share/" + org + "/" + app + "/" + app + ".log"),
    [macOS],   raw("~/Library/Logs/" + org + "/" + app + ".log"),
    [Windows], raw("%AppData%\\" + org + "\\" + app + "\\" + app + ".log"),
)

These logs contain anything that is written in the #app Console.

You can control the size and number of log files kept by #app with the
following environment variables:

- `RV_FILE_LOG_SIZE`: Sets the maximum size of each log file. When that
  maximum size is reached, #app creates a new log file. Default value is
  5 MB.
- `RV_FILE_LOG_NUM_FILES`: Sets the number of log files to keep. If there
  are a number of log files equal to `RV_FILE_LOG_NUM_FILES`, then #app
  deletes the oldest log file before creating a new one. Default value is 2.

== Command-Line Options <command-line-options>

#table(
    columns: (auto, 1fr),
    align: left,
    table.header[*Option*][*Description*],
    [`-c`], [Use region frame cache],
    [`-l`], [Use look-ahead cache],
    [`-nc`], [Use no caching],
    [`-s` _float_], [Image scale reduction],
    [`-stereo` _string_], [Stereo mode (hardware, checker, scanline, anaglyph, left, right, pair, mirror, hsqueezed, vsqueezed)],
    [`-vsync` _int_], [Video Sync (1 = on, 0 = off, default = 0)],
    [`-comp` _string_], [Composite mode (over, add, difference, replace, default=replace)],
    [`-layout` _string_], [Layout mode (packed, row, column, manual)],
    [`-over`], [Same as -comp over -view defaultStack],
    [`-diff`], [Same as -comp difference -view defaultStack],
    [`-tile`], [Same as -comp tile -view defaultStack],
    [`-wipe`], [Same as -over with wipes enabled],
    [`-view` _string_], [Start with a particular view],
    [`-noSequence`], [Don't contract files into sequences],
    [`-inferSequence`], [Infer sequences from one file],
    [`-autoRetime` _int_], [Automatically retime conflicting media fps in sequences and stacks (1 = on, 0 = off, default = 1)],
    [`-rthreads` _int_], [Number of reader threads (default = 1)],
    [`-renderer` _string_], [Default renderer type (Composite or Direct)],
    [`-fullscreen`], [Start in fullscreen mode],
    [`-present`], [Start in presentation mode (using presentation device)],
    [`-presentAudio` _int_], [Use presentation audio device in presentation mode (1 = on, 0 = off)],
    [`-presentDevice` _string_], [Presentation mode device],
    [`-presentVideoFormat` _string_], [Presentation mode override video format (device specific)],
    [`-presentDataFormat` _string_], [Presentation mode override data format (device specific)],
    [`-screen` _int_], [Start on screen (0, 1, 2, ...)],
    [`-noBorders`], [No window manager decorations],
    [`-geometry` _int int \[ int int \]_], [Start geometry x, y, w, h],
    [`-init` _string_], [Override init script],
    [`-nofloat`], [Turn off floating point by default],
    [`-maxbits` _int_], [Maximum default bit depth (default=32)],
    [`-gamma` _float_], [Set display gamma (default=1)],
    [`-sRGB`], [Display using linear → sRGB conversion],
    [`-rec709`], [Display using linear → Rec 709 conversion],
    [`-floatLUT` _int_], [Use floating point LUTs (requires hardware support, 1=yes, 0=no, default=_platform-dependent_)],
    [`-dlut` _string_], [Apply display LUT],
    [`-brightness` _float_], [Set display relative brightness in stops (default=0)],
    [`-resampleMethod` _string_], [Resampling method (area, linear, cube, nearest, default=area)],
    [`-eval` _string_], [Evaluate expression at every session start],
    [`-nomb`], [Hide menu bar on start up],
    [`-play`], [Play on startup],
    [`-fps` _float_], [Overall FPS],
    [`-cli`], [Mu command line interface],
    [`-vram` _float_], [VRAM usage limit in Mb, default = 64.000000],
    [`-cram` _float_], [Max region cache RAM usage in Gb],
    [`-lram` _float_], [Max look-ahead cache RAM usage in Gb],
    [`-noPBO`], [Prevent use of GL PBOs for pixel transfer],
    [`-prefetch`], [Prefetch images for rendering],
    [`-bwait` _float_], [Max buffer wait time in cached seconds, default 5.0],
    [`-lookback` _float_], [Percentage of the lookahead cache reserved for frames behind the playhead, default 25],
    [`-yuv`], [Assume YUV hardware conversion],
    [`-volume` _float_], [Overall audio volume],
    [`-noaudio`], [Turn off audio],
    [`-audiofs` _int_], [Use fixed audio frame size (results are hardware dependent ... try 512)],
    [`-audioCachePacket` _int_], [Audio cache packet size in samples (default=512)],
    [`-audioMinCache` _float_], [Audio cache min size in seconds (default=0.300000)],
    [`-audioMaxCache` _float_], [Audio cache max size in seconds (default=0.600000)],
    [`-audioModule` _string_], [Use specific audio module],
    [`-audioDevice` _int_], [Use specific audio device (default=-1)],
    [`-audioRate` _float_], [Use specific output audio rate (default=ask hardware)],
    [`-audioPrecision` _int_], [Use specific output audio precision (default=16)],
    [`-audioNice` _int_], [Close audio device when not playing (may cause problems on some hardware) default=0],
    [`-audioNoLock` _int_], [Do not use hardware audio/video synchronization (use software instead default=0)],
    [`-audioGlobalOffset` _int_], [Global audio offset in seconds],
    [`-bg` _string_], [Background pattern (default=black, grey18, grey50, checker, crosshatch)],
    [`-formats`], [Show all supported image and movie formats],
    [`-cmsTypes`], [Show all available Color Management Systems],
    [`-debug` _string_], [Debug category (events, threads, gpu, audio, audioverbose, dumpaudio, shaders, shadercode, profile, playback, playbackverbose, cache, mu, muc, compile, dtree, passes, imagefbo, nogpucache, imagefbolog, nodes, plugins)],
    [`-cinalt`], [Use alternate Cineon/DPX readers],
    [`-exrcpus` _int_], [EXR decoder thread count (0 = automatic: half the logical cores when there are more than 16, else logical cores minus 1; default=0)],
    [`-exrRGBA`], [EXR use basic RGBA interface (default=false)],
    [`-exrInherit`], [EXR guesses channel inheritance (default=false)],
    [`-exrIOMethod` _int \[int\]_], [EXR I/O Method (0=standard, 1=buffered, 2=unbuffered, 3=MemoryMap, 4=AsyncBuffered, 5=AsyncUnbuffered, default=0) and optional chunk size (default=61440)],
    [`-jpegRGBA`], [Make JPEG four channel RGBA on read (default=no, use RGB or YUV)],
    [`-jpegIOMethod` _int \[int\]_], [JPEG I/O Method (0=standard, 1=buffered, 2=unbuffered, 3=MemoryMap, 4=AsyncBuffered, 5=AsyncUnbuffered, default=0) and optional chunk size (default=61440)],
    [`-cinpixel` _string_], [Cineon/DPX pixel storage (default=RGB8\_PLANAR)],
    [`-cinchroma`], [Cineon pixel storage (default=RGB8\_PLANAR)],
    [`-cinIOMethod` _int \[int\]_], [Cineon I/O Method (0=standard, 1=buffered, 2=unbuffered, 3=MemoryMap, 4=AsyncBuffered, 5=AsyncUnbuffered, default=3) and optional chunk size (default=61440)],
    [`-dpxpixel` _string_], [DPX pixel storage (default=RGB8\_PLANAR)],
    [`-dpxchroma`], [Use DPX chromaticity values (for default reader only)],
    [`-dpxIOMethod` _int \[int\]_], [DPX I/O Method (0=standard, 1=buffered, 2=unbuffered, 3=MemoryMap, 4=AsyncBuffered, 5=AsyncUnbuffered, default=3) and optional chunk size (default=61440)],
    [`-tgaIOMethod` _int \[int\]_], [TARGA I/O Method (0=standard, 1=buffered, 2=unbuffered, 3=MemoryMap, 4=AsyncBuffered, 5=AsyncUnbuffered, default=2) and optional chunk size (default=61440)],
    [`-tiffIOMethod` _int \[int\]_], [TIFF I/O Method (0=standard, 1=buffered, 2=unbuffered, 3=MemoryMap, 4=AsyncBuffered, 5=AsyncUnbuffered, default=2) and optional chunk size (default=61440)],
    [`-noPrefs`], [Ignore preferences],
    [`-resetPrefs`], [Reset preferences to default values],
    [`-qtcss` _string_], [Use QT style sheet for UI],
    [`-qtstyle` _string_], [Use QT style, default=""],
    [`-qtdesktop`], [QT desktop aware, default=1 (on)],
    [`-xl`], [Aggressively absorb screen space for large media],
    [`-mouse` _int_], [Force tablet/stylus events to be treated as mouse events, default=0 (off)],
    [`-network`], [Start networking],
    [`-networkPort` _int_], [Port for networking],
    [`-networkHost` _string_], [Alternate host/address for incoming connections],
    [`-networkConnect` _string \[int\]_], [Start networking and connect to host at port],
    [`-networkPerm` _int_], [Default network connection permission (0=Ask, 1=Allow, 2=Deny, default=0)],
    [`-reuse` _int_], [Try to re-use the current session for incoming URLs (1 = reuse session, 0 = new session, default = 1; macOS only)],
    [`-nopackages`], [Don't load any packages at startup (for debugging)],
    [`-encodeURL`], [Encode the command line as an rvlink URL, print, and exit],
    [`-bakeURL`], [Fully bake the command line as an rvlink URL, print, and exit],
    [`-flags` _string_], [Arbitrary flags (flag, or 'name=value') for use in Mu code],
    [`-prefsPath` _string_], [Alternate path to preferences directory],
    [`-registerHandler`], [Register this executable as the default rvlink protocol handler (macOS only)],
    [`-scheduler` _string_], [Thread scheduling policy (may require root, Linux only)],
    [`-priorities` _int int_], [Set display and audio thread priorities (may require root, Linux only)],
    [`-version`], [Show #app version number],
)

=== Per-Source Options <per-source-options>

These options can be given inside the square brackets that group a source's
layers (see @per-source-arguments).

#table(
    columns: (auto, 1fr),
    align: left,
    table.header[*Option*][*Description*],
    [`-pa` _float_], [Set the Pixel Aspect Ratio],
    [`-ro` _int_], [Shifts first and last frames in the source range (range offset)],
    [`-rs` _int_], [Sets first frame number to argument and offsets the last frame number],
    [`-fps` _float_], [FPS override],
    [`-ao` _float_], [Audio Offset. Shifts audio in seconds (audio offset)],
    [`-so` _float_], [Set the Stereo Eye Relative Offset],
    [`-volume` _float_], [Audio volume override (default = 1)],
    [`-fcdl` _filename_], [Associate a file CDL with the source],
    [`-lcdl` _filename_], [Associate a look CDL with the source],
    [`-flut` _filename_], [Associate a file LUT with the source],
    [`-llut` _filename_], [Associate a look LUT with the source],
    [`-pclut` _filename_], [Associate a pre-cache software LUT with the source],
    [`-cmap` _channels_], [Remap color channels for this source (channel names separated by commas)],
    [`-select` _selectType selectName_], [Restrict loaded channels to a single view/layer/channel. _selectType_ must be one of view, layer, or channel. _selectName_ is a comma-separated list of view name, layer name, channel name.],
    [`-crop` _x0 y0 x1 y1_], [Crop image to box (all integer arguments)],
    [`-uncrop` _width height x y_], [Inset image into larger virtual image (all integer arguments)],
    [`-in` _int_], [Cut-in frame for this source in default EDL],
    [`-out` _int_], [Cut-out frame for this source in default EDL],
    [`-noMovieAudio`], [Turn off source movie's baked-in audio (aka “-nma”)],
)

== Image Sequence Notation

#app has a special syntax to describe image sequences as source movies.
Sequences are assumed to be files with a common base name followed by a
frame number and an image type extension. For example, the filenames
#inline-shell("foo.1.tif") and #inline-shell("foo.0001.tif") would be
interpreted as frame 1 of the TIFF sequence #inline-shell("foo"). #app sorts
images by frame numbers in numeric order. It sorts image base names in
lexical order. What this means is that #app will sort images into sequences
the way you expect it to. Padding tricks are unnecessary for #app to get the
image order correct; image order will be interpreted correctly.

#code-block(
    "foo.0001.tif foo.0002.tif foo.0003.tif foo.0004.tif",
    "foo.0005.tif foo.0006.tif foo.0007.tif foo.0008.tif",
    "foo.0009.tif foo.0010.tif",
)

To play this image sequence in #app from the command line, you could start
#app like this:

#appshell("foo.*.tif")

and #app will automatically attempt to group the files into a logical
movie. (*Note:* this will only work on Linux or macOS, or some other
Unix-like shell, like Cygwin on Windows.)

When you want to play a subset of frames or audio needs to be included, you
can specify the sequence using the `#` or `@` notation (similar to Shake's)
or the printf-like notation using `%` similar to Nuke.

#appshell(
    "foo.#.tif",
    "foo.2-8#.tif",
    "foo.2-8@@@@.tif",
    "foo.%04d.tif",
    "foo.%04d.tif 2-8",
    "foo.#.tif 2-8",
)

The first example above plays all frames in the #inline-shell("foo")
sequence, the second line plays frames starting at frame 2 through frame 8.
The third line uses the `@` notation which forces #app to assume 0 padded
frame numbers -- in this case, four `@` characters indicate a four character
padding.

The next two examples use the printf-like syntax accepted by Nuke. In the
first case, the entire frame range is specified with the assumption that the
frame numbers will be padded with 0 up to four characters (this notation
will also work with 6 or other amounts of padding). In the final two
examples, the range is limited to frames 2 through 8, and the range is
passed as a separate argument.

Sometimes, you will encounter or create an image sequence which is
purposefully missing frames. For example, you may be rendering something
that is very expensive to render and only wish to look at every tenth frame.
In this case, you can specify the increment using the `x` character like
this:

#appshell("foo.1-100x10#.tif")

or alternately like this using the `@` notation for padding to four digits:

#appshell("foo.1-100x10@@@@.tif")

or if the file was padded to three digits like #inline-shell("foo.001.tif"):

#appshell("foo.1-100x10@@@.tif")

In these examples, #app will play frames 1 through 100 by tens. So it will
expect frames 1, 11, 21, 31, 41, on up to 91.

If there is no obvious increment, but the frames need to be grouped into a
sequence, you can list the frame numbers with commas:

#appshell("foo.1,3,5,7,8,9#.tif")

In many cases, #app can detect file types automatically even if a file
extension is not present or is mislabeled.

#quote(block: true)[
    *Note:* Use the same format for exporting multiple annotated frames.
]

=== Negative Frame Numbers

#app can handle negative frames in image sequences. If the frame numbers are
zero padded, they should look like so:

#code-block(
    "foo.-012.tif",
    "foo.-001.tif",
)

To specify in and out points on the command line in the presence of
negative frames, just include the minus signs:

#code-block(
    "foo.-10-20#.tif",
    "foo.-10--5#.tif",
)

The first example uses frames -10 to +20. The second example uses frames
-10 to -5. Although the use of the `-` character to specify ranges can make
the sequence a bit visually confusing, the interpretation is not ambiguous.

=== Stereo Notation

#app can accept stereo notation similar to Nuke's `%v` and `%V` syntax. By
default, #app can only recognize `left`, `right`, `Left`, and `Right` for
`%V` and for `%v` it will try `L`, `R`, or `l` and `r`. You can change the
substitutions by setting the environment variables `RV_STEREO_NAME_PAIRS`
and `RV_STEREO_CHAR_PAIRS`. These should be set to a colon separated list of
values (even on Windows). For example, the defaults would look like this:

#code-block(
    "RV_STEREO_NAME_PAIRS = left:right:Left:Right",
    "RV_STEREO_CHAR_PAIRS = L:R:l:r",
)

So for example, if you have two image sequences:

#code-block(
    "foo.0001.left.exr",
    "foo.0002.left.exr",
    "foo.0001.right.exr",
    "foo.0002.right.exr",
)

you could refer to the entire stereo sequence as:

#code-block("foo.%04d.%V.exr")

== Source Layers from the Command Line

You can create source material from multiple audio, image, and movie files
from the command line by enclosing them in square brackets. The typical
usage looks something like this:

#appshell("[ foo.#.exr soundtrack.aiff ]")

Note that there are spaces around the brackets: they must be completely
separated from subsequent arguments to be interpreted correctly. You cannot
nest brackets and the brackets must be matched; for every begin bracket
there must be an end bracket.

=== Associating Audio with Image Sequences or Movie Files

Frequently a movie file or image sequence needs to be viewed with one or
more separate audio files. When you have multiple layers on the command line
and one or more of the layers are audio files, #app will play back all of
the audio files mixed together along with the images or movies. For example,
to play back two wav files with an image sequence:

#appshell("[ foo.#.exr first.wav second.wav ]")

If you have a movie file which already has audio you can still add
additional audio files to be played:

#appshell("[ movie_with_audio.mov more_audio.aiff ]")

=== Dual Image Sequences and/or Movie Files as Stereo <stereo-layers-cli>

It's not unusual to render left and right eyes separately and want to view
them as stereo together. When you give #app multiple layers of movie files
or image sequences, it uses the first two as the left and right eyes.

#appshell("[ left.#.exr right.#.exr ]")

It's OK to mix and match formats with layers:

#appshell("[ left.mov right.100-300#.jpg ]")

if you want audio too:

#appshell("[ left.#.exr right.#.exr soundtrack.aiff ]")

As with the mono case, any number of audio files can be added: they will be
played simultaneously.

=== Per-Source Arguments <per-source-arguments>

There are a few arguments which can be applied within the square brackets
(see @per-source-options). The range start (#inline-shell("-rs")) sets the
first frame number to its argument; so for example to set the start frame of
a movie file with or without a time code track so that it starts at frame
101:

#appshell("[ -rs 101 foo.mov ]")

You must use the square brackets to set per-source arguments (and the square
brackets must be surrounded by spaces).

The #inline-shell("-in") and #inline-shell("-out") per-source arguments are
an easy way to create an EDL on the command line, even when playing movie
files.

=== A Note on the -fps Per-Source Argument

The point of the #inline-shell("-fps") argument is to provide a scaling
factor in cases where the frame rate of the media cannot be determined and
you want to play an audio file with it. For example, if you want to play
#inline-shell("[ foo.#.dpx foo.wav ]") in the same session with
#inline-shell("[ bar.#.dpx bar.wav ]") but the native frame rate of
#inline-shell("foo") is 24fps and the native frame rate of
#inline-shell("bar") is 30fps, then you might want to say:

#appshell("[ foo.#.dpx foo.wav -fps 24 ] [ bar.#.dpx bar.wav -fps 30 ]")

This will ensure that the video and audio are synced properly no matter what
frame rate you use for playback. To clarify further, the per-source
#inline-shell("-fps") flag has no relation to the frame rate that is used for
playback, and in general #app plays media (all loaded media) at whatever
single frame rate is currently in use.

=== Source Layer Caveats and Capabilities

There are a number of things you should be aware of when using source
layers. In most cases, #app will attempt to do something with what you give
it. However, if your input is logically ambiguous the result may be
different than what you expect. Here are some things you should avoid using
in layers of a single source:

- Images or movies with differing frame rates
- Images or movies with different image or pixel aspect ratios
- Images or movies which require special color correction for only one eye
- Images or movies stored with differing color spaces (e.g. cineon log
  images + jpeg)

Here are some things that are OK to do with layers:

- Images with different resolutions but the same image aspect ratio
- Images with different bit depths or number of channels or chroma sampling
- Audio files with different sample rates or bit depths
- Mixing movies with audio and separate audio files
- An image sequence for one eye and a movie for the other
- A movie with audio for one eye and a movie without audio for the other
- Audio files with no imagery

== Directories as Input

If you give #app the name of a directory instead of a single file or an
image sequence it will attempt to interpret the contents of the directory.
#app will find any single images, image sequences, or single movie files
that it can and present them as individual source movies. This is especially
useful with the directory #inline-shell(".") on Linux and macOS. If you
navigate in a shell to a directory that contains an image sequence for
example, you need only type the following to play it:

#appshell(".")

You don't even need to get a directory listing. If #app finds multiple
sequences or a sequence and movie files, it will sort and organize them into
a playlist automatically. #app will attempt to read files without extensions
if they look like image files (for example the file ends in a number). If
#app is unable to parse the contents of a directory correctly, you will need
to specify the image sequences directly to force it to read them.
