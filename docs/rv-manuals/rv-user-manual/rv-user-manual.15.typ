#import "../common/manual-lib.typ": *
#show: manual

= File Formats <ch-file-formats>

Each platform has a different set of file formats which #app can read by
default. In addition, it's possible to download or purchase additional file
format plug-ins which allow #app to read even more. This chapter is an
overview of the most important formats and how #app uses them.

You can have #app dump out all of the formats and codecs which it
understands on the command line by giving it the #inline-shell("-formats")
option.

#appshell("-formats")

If you don't see a codec or container format in the list, then #app doesn't
support it without installing one or more plug-ins.

== Movie File Formats

Movie files are single files which contain many images and often audio.
These are often called _container file formats_ because they usually
specify how to store data, but not how it should be used. In most cases,
that includes compression methods, play back algorithms, or even what the
meaning of the data in the container is.

Container file formats have additional sub-formats called _codecs_ which
determine things like compression and methods of play back. So even though a
program like #app might be able to open a container file and look inside it,
it might not understand one or more of the codecs which are being used in
the container. In some cases the codec might be proprietary or meant to be
used with a specific piece of software or hardware.

=== Stereo Movie Files

Most movie file formats can have multiple tracks. When #app reads a movie
file with two or more tracks it uses the first two tracks as the left and
right eye when in stereo mode. You can create these files using the Apple
QuickTime Player or #ioapp on macOS and Windows or #ioapp on Linux.

=== Text Tracks

On Linux, #app will read the text track of a movie file if it exists and put
the contents in an image attribute per frame. You can see this with the
image info widget. Text tracks can be used to store metadata about the movie
contents in a cross platform manner.

=== QuickTime Movie Files (.mov)

#app uses a plugin which leverages ffmpeg directly to handle as many formats
and codecs as possible.

There are literally hundreds of codecs which can appear in a QuickTime file,
but only some of them are useful in post-production. #app tries to support
the most popular and useful ones.

==== Photo-JPEG

This codec has qualities which make it popular in film post production. Each
frame is stored separately in the QuickTime file so moving to a random frame
is fast. JPEG offers a number of ways to compress the image data including
sub-sampling of color versus luminance and using sophisticated compression
techniques. Color representation can be excellent when using Photo-JPEG.
File sizes are moderate.

The ffmpeg plugin does not respect all of the QuickTime atom objects. Usually
this is a good thing as Apple's own library produces inconsistent results
from platform to platform when displaying movie files with `gama` and `colr`
atoms. The most notorious of the color atoms which typically affects the
color of Photo-JPEG movies is the `gama` atom. The `gama` atom causes Apple's
QuickTime to apply two gamma corrections to the image before it is
displayed. #app will not do that and #ioapp does not include the `gama` atom
when writing QuickTime movies.

==== Motion-JPEG

Motion JPEG is similar to Photo-JPEG in that they both use the same
compression algorithm. The main difference is that Motion-JPEG essentially
stores a single frame in two parts: all of the even scanlines as a single
JPEG image and all of the odd scanlines as a separate image. The codec
interlaces the two parts together to form the final image.

Motion-JPEG is supported on all platforms.

==== H.264 (avc1)

This is a codec which is usually associated with MPEG-4. H.264 stores
keyframes and data which helps it generate in-between frames on the fly.
Because it doesn't store every frame individually, H.264 compressed files
can be much smaller than codecs like Photo-JPEG. The image quality for H.264
can be good depending on how the movie was created. If relatively simple
creation software was used (like Apple's QuickTime player or #ioapp) the
results are usually OK, but not nearly as good as Photo or Motion-JPEG.

==== RAW Codecs

There are a number of _raw_ codecs for QuickTime. Some of these store the
pixel data as RGB, others as YUV. The raw codecs tend to be very fast to read
and play back. #app supports a number of raw codecs on all platforms.

==== Audio

#app supports most raw uncompressed audio codecs across platforms.

#app and #ioapp handle mono, stereo, and multichannel audio (such as 5.1 and
7.1). #app plays multichannel audio through the "Platform Audio" output
module, mixing or reordering channels to match the output device (see
#xref(<app-multichannel-layouts>)[Appendix I]); #ioapp can set the number of
output channels with #inline-shell("-audiochannels").

=== MPEG-4 Movie Files (.mp4)

The MPEG-4 container file (#inline-shell(".mp4")) is almost identical to the
QuickTime container file (#inline-shell(".mov")). The same codecs may be
used to store data in either format. However, typically you find files
encoded with H.264 or one of its predecessors.

#app supports the MPEG-4 container on all platforms.

=== Windows AVI Files (.avi)

#app supports AVI files with the same codecs as QuickTime on all platforms.

=== Windows Media Files (.wmv)

There is no official support for this file format.

=== #app's movieproc Format (.movieproc) <movieproc>

The movieproc "format" is not really a file format -- all of the information
about the pixels is encoded in the name of the file. So the file doesn't
even need to exist on disk to use it.

You might use a movieproc as a source if you need a procedural movie object
like color bars or a hold on a black or other solid color frame in a
sequence.

The syntax of the file name is as follows:

#code-block(lang: none, "TYPE,OPTION=VALUE,OPTION=VALUE,OPTION=VALUE.movieproc")

where _TYPE_ is one of `solid`, `smptebars`, `colorchart`, `noise`, `blank`,
`black`, `white`, `grey`/`gray`, `hramp`/`hbramp`, `hwramp`, or `error`, and
_OPTION_ and _VALUE_ are one of those listed in @movieproc-options. A blank
movieproc is one that will render no pixels but can occupy space in a
sequence, and so can be used to form sequences with "holes".

#figure(
    kind: table,
    table(
        columns: (auto, 1fr),
        align: left,
        table.header[*Option*][*Value*],
        [`red`, `green`, `blue`], [floating point value $[-infinity, infinity]$ (used as one "side" for ramp types)],
        `start`, [frame number],
        `end`, [frame number],
        `fps`, [frames-per-second (e.g. 30 or 29.97)],
        `inc`, [frame increment (default is 1)],
        [`grey`, `gray`], [short hand for red=green=blue image],
        `alpha`, [floating point value $[0, 1]$],
        `width`, [Image width in pixels],
        `height`, [Image height in pixels],
        `depth`, [Channel bit depth: one of `8i`, `16i`, `16f`, or `32f`],
        `interval`, [interval in seconds for "sync" and "flash" options below],
        `audio`, ["sine" for continuous tone, or "sync" for once-per-interval chirp],
        `freq`, [Audio frequency (pitch), e.g. 440 for concert A],
        `amp`, [Audio amplitude $[0, 1]$],
        `rate`, [Audio rate in samples-per-second (e.g, 44100 for CD quality)],
        `hpan`, ["animate" by shifting `hpan` pixels to the left each frame],
        `flash`, [flash one frame every interval],
        `filename`, [base64 string to spoof filename],
        [`attr:`_NAME_], [add an attribute named _NAME_ to the framebuffer with string value],
    ),
    caption: [Movieproc Options],
) <movieproc-options>

For example the following will show color bars with a 1000 Hz tone:

#code-block(lang: none, "smptebars,audio=sine,freq=1000,start=1,end=30,fps=30.movieproc")

and to make 100 black HD 1080 frames:

#code-block(lang: none, "solid,start=1,end=100,fps=24,width=1920,height=1080.movieproc")

or for an orange frame:

#code-block(lang: none, "solid,red=1,green=.5,blue=0,width=1920,height=1080.movieproc")

Anywhere you might use a normal file or sequence name in #app or #ioapp you
can use a movieproc instead.

== Image File Formats

Each platform which #app runs on has its own selection of image formats.
There are a few important ones which are implemented across all platforms.
Some of the most important formats are discussed in this chapter.

=== OpenEXR

OpenEXR (EXR) is a high dynamic range floating point file format developed
at ILM. It can store both 32 and 16 bit "half" floating point values with or
without compression. #app supports the EXR half float type natively and when
the GPU is capable, will render using the half type directly. #ioapp is
capable of converting to and from the half and full float formats.

The EXR format is extremely flexible, capable of holding everything from
multiple views (for stereo) to rendered layers like isolated diffuse and
specular components as separate images. In addition it's possible to store
subsampled chroma images or combinations of all the above.

There have been at least two important revisions to the original OpenEXR
specification, one the "multi-view" spec adds official support for top-level
"view" objects that contain channels, and the most recent, the "multi-part"
spec adjusts the file format so that groups of channels can be stored in
discrete sections ("parts") for efficient I/O. #app supports all varieties of
EXR file supported by the latest specifications, but attempts to hide some of
the resulting complexity from the user, as discussed below.

==== Multiple Views

Multiple view EXR files as defined by the Weta Multiview Extension are
supported by #app. When in stereo mode, #app will look for views called
"left" and "right" by default and can be programmatically told to use other
channels (see the Reference Manual).

You can also select one or more views in the UI to be loaded specifically
when not in stereo mode. In stereo mode if you specify two views those will
become the left and right.

#app defaults to loading the default (or first) EXR layer from the view. The
EXR views are independent of EXR layers which are described below -- there
can be multiple views each of which has multiple layers (or vice versa if you
prefer to think of it that way).

#app will recognize the file extensions #inline-shell("exr"),
#inline-shell("sxr") (stereo exr), or #inline-shell("openexr") as being
OpenEXR files. Stereo views may be stored as either #inline-shell("exr") or
#inline-shell("sxr"); #app does not distinguish between the two extensions.

==== Layers

A layer in EXR terminology is a collection of channels which share a common
channel name prefix separated by a dot character. Although EXR layers can
have sub-layers and so on, in #app the layer hierarchy is flattened to a
single level. So for example, an EXR channel in a traditional multi-view EXR
file (multi-part files are discussed below), might have a channel called
`left.keyLight.Diffuse.R`. In #app's simplified usage, the channel `R` is a
member of the layer `keyLight.Diffuse`, which is a member of the view
`left`.

EXR layers are usually used to store components of images output by a
renderer like Pixar's prman or Mental Images' Mental Ray. Often these layers
are recombined in compositing software like Nuke which can handle the
internal structure of the EXR file. This makes it easy for a compositor to
control render output at a fine level to match it into a shot. Note that
this is not how EXR views are used -- they are used for indicating stereo
eyes (for example) and each view may itself contain multiple EXR layers.

#app initially will load the default layer (the one that has no name) or the
first layer it finds. If this layer has R, G, B, A, Z, Y, RY, or BY channels,
these will be assigned accordingly. If there are no obvious channel
assignments to be made to the red, green, and blue channels, #app will take
the first four channels it finds in the layer. If there are additional
channels, you can assign these explicitly using the channel remap function in
the UI under #menu(("Image", "Remap Source Image Channels")).

You can view alternate layers by selecting them in the Session Manager, or by
selecting a layer on the command line.

==== Y RY BY Images and Subsampling

By default, #app will read EXR files as planar images. Normally this
distinction does not have any real effect at the user level, but in the case
of Y RY BY images -- which can be sub-sampled -- it can have a big impact on
playback performance. EXR has two special lossy compression schemes, B44 and
B44A, which allow fast decode of high dynamic range imagery. B44 maintains a
fixed size file regardless of the contents while B44A can potentially make
smaller file sizes. As of OpenEXR v2.2.0, two further lossy DCT compression
schemes were added: DWAA (based on 32 scanlines) and DWAB (based on 256
scanlines). The compression level for DWAA and DWAB can be set through the
#inline-shell("-quality <compression level value>") option in #iocmd when
writing out EXR files. This value is stored in the EXR header
(single/multipart) as a float attribute called `dwaCompressionLevel` and
defaults to 45 for DWAA and DWAB.

When used with Y RY BY images with sub-sampled chroma (the BY and RY
channels) #app will use the GPU to resample the chroma on the card resulting
in faster throughput. When coupled with one or more multi-core CPUs, #app can
get good direct from disk performance for these types of images while
keeping the HDR information intact. At some resolutions, #app can even play
back stereo HDR imagery in real-time from disk when used with the correct
hardware.

The OpenEXR file will only use B44 or B44A with half float images currently.
32 bit float images will not typically get as good performance.

==== Chromaticities

EXR files may have chromaticities (primaries) included in the image
attributes. If #app sees the `Color/Primaries` attribute, it will apply the
corresponding transform to the Rec 709 primaries by default. You can turn off
this behavior by selecting #menu(("Color", "Ignore File Primaries")).

==== Channel Inheritance

Some programs may assume channels should be "inherited" in EXR files. For
example, a renderer may write a single alpha channel in the default layer and
exclude redundant alpha channels from additional layers in the file like
diffuse and specular. The idea is that these layers will share the default
alpha during compositing.

#app can attempt to aggregate channels assumed to be related like this by
using either the command line option #inline-shell("-exrInherit") or by
setting the flag in preferences (under the OpenEXR format).

==== Data/Display Window Handling

How an EXR image is displayed on screen, under certain data/display window
overlap permutations, can vary across commercial and/or in-house viewing
tools. To accommodate this and allow #app to emulate these differing
behaviors, we provide several EXR format preferences; see @exr-window-settings
for typical settings.

The two OpenEXR preferences, found under
#menu(("Preferences", "Formats", "OpenEXR")), that define #app's
data/display window handling behavior are #inline-shell("-exrReadWindow")
and #inline-shell("-exrReadWindowIsDisplayWindow"). The flag
#inline-shell("-exrReadWindow") specifies how the final data/display window
(i.e. ReadWindow) is defined. The choices are "Data Window", "Display
Window", "Data Window Inside Display Window" and "Union of Data and Display
Window". In addition the flag #inline-shell("-exrReadWindowIsDisplayWindow")
may optionally be set to always make the ReadWindow the EXR display window;
otherwise the display window is determined by the source's EXR display
window attributes.

#figure(
    kind: table,
    table(
        columns: 3,
        align: left,
        table.header[*Read Window*][*Read Window Is Display Window*][*Tool*],
        [Data Window], [Checked], [macOS Preview, Adobe Photoshop],
        [Display Window], [Not applicable], [Nuke, exrdisplay],
        [Data Window Inside Display Window], [Not applicable], [],
        [Union of Data and Display Window], [Checked], [RenderMan it, exrdisplay -w],
    ),
    caption: [OpenEXR format settings that emulate data/display window
        handling of various tools#footnote[Subject to change by the
        vendor.]],
) <exr-window-settings>

==== Parts

As of OpenEXR version 2.0, EXR files can be written in separate sections,
called "parts". Each part has its own header, and the underlying OpenEXR API
can quickly skip to parts requested by the reader. Parts can contain layered
and unlayered channels and be associated with views, but parts have names and
so can also act as "layers" in the sense that unique parts can contain
channels of the same name.

In order to merge these possibly multiple and simultaneous uses of "parts"
into the standard view/layer/channel hierarchy, #app subsumes EXR "parts"
into the definition of "layer" when necessary. That is, as far as #app is
concerned, a fully-specified channel name always looks like
`view.layer.channel`, where (in the case of an EXR file) the three
period-separated components of the name have these meanings:

#figure(
    kind: table,
    table(
        columns: (auto, 1fr),
        align: left,
        table.header[*Component*][*Meaning*],
        `view`, [The name of the stereo view. This may be missing or "default"
            for "the default view". The view name cannot contain a ".".
            Example: "left", "right", "center", etc.],
        `layer`, [This component may include part names as well as
            traditional EXR layer names. The rule is that if there are no
            channel-name conflicts within a single view, the part names will
            be ignored (since they are not necessary to distinguish the
            channels); if there *is* a channel-name conflict, the part names
            may be incorporated into the layer names. Sub-layers are also
            included. To be concrete, a channel called `Diffuse.R` stored in a
            part called `keyLight` is considered to be a member of a layer
            called `keyLight.Diffuse` if the channel `Diffuse.R` also appears
            in another part within the same view.],
        `channel`, [The last component of a traditional EXR channel name,
            containing no ".". Example: "R", "G", "B", "A", "Z", etc.],
    ),
    caption: [Components of a fully-qualified channel name],
)

If an EXR has multiple parts and no channels are selected, #app will make a
best effort to determine the most viable default channels. If multiple
layers are similarly viable, #app will prefer a layer with RGB or RGBA
channels from the first part (part 0). Unless explicitly directed, the
channels chosen will not cross part boundaries unless Guess Channel
Inheritance is enabled.

#quote(block: true)[
    *Note:* You can obtain uncached playback FPS speedups of between 2-3x
    (macOS/Linux/Windows) with multipart EXR files over single part EXR files
    for deep channeled images.
]

=== TIFF

TIFF files come in many flavors some of which are rarely used. #app supports
a useful subset of all possible TIFF files. This includes 32 bit floating
point and multiple channels (beyond four) in both tiled and scanline. #app
can read planar and interleaved TIFF files, but currently only reads the
first image directory if there is more than one.

#app will read all TIFF tags including EXIF tags and present them as image
attributes.

=== DPX and Cineon

#app and #ioapp currently support 8 and 16 bit, and the common 10 and 12 bit
DPX and 10 bit Cineon files reading direct from disk on all platforms. The
standard header fields are read and reported if they contain useful
information (e.g., Motion Picture and TV fields). We do not currently
support any of the vendor headers.

#app supports the linear, log, and Rec. 709 transfer functions for DPX
natively and others through the use of LUTs.

#app decodes DPX and Cineon to 8 bit integer per channel by default. However,
the reader can be configured from the command line or preferences to use 16
bit if needed. In addition the reader can use either planar or interleaved
pixel formats. We have found that the combination of OS and hardware
determines which format is fastest for playback, but we currently recommend
`RGB8_PLANAR` on systems that can use OpenGL Pixel Buffer Objects (PBOs) and
`RGBA8` on systems that cannot. If you opt for 16 bit pixels, use
`RGB16_PLANAR` as the pixel format on PBO equipped hardware for maximum
throughput.

For best color fidelity use #app's built in Cineon Log → Linear option and
sRGB display (or a particular display LUT if available). This option decodes
the log space pixels directly to linear without interpolation inside a
hardware shader and results in the full $[0, approx 13.5]$ range.

#ioapp decodes Cineon and DPX to 16 bit integer by default.

The DPX and Cineon writers are both currently limited to 10 bit output.

=== IFF (ILBM)

The IFF image format commonly created by Maya or Shake is supported by #app
including the 32 bit float version.

=== JPEG

#app can read JPEG natively as YUV or RGB formats. The reader can collect any
EXIF tags and pass them along as image attributes. The reader is limited to
8 bits per channel files. Like OpenEXR, DPX, and Cineon, there is a choice
of I/O method with JPEG images.

=== RAW DSLR Camera Formats

There are a number of camera vendor specific formats which #app can read
through #app's cross platform image plugin `io_raw`. This plugin uses the
open source package LibRaw. @raw-formats lists some of the common raw
formats that are read with this plugin.

#figure(
    kind: table,
    table(
        columns: 2,
        align: left,
        table.header[*File Extension*][*File Format*],
        `.arw`, [Sony/Minolta RAW],
        `.cr2`, [Canon RAW 2],
        `.cr3`, [Canon RAW 3],
        `.crw`, [Canon RAW],
        `.dng`, [Digital Negative],
        `.nef`, [Nikon Electronic Format],
        `.orf`, [Olympus RAW],
        `.pef`, [Pentax RAW],
        `.ptx`, [Pentax RAW 2],
        `.raf`, [Fuji RAW],
        `.rdc`, [Ricoh RAW],
        `.rmf`, [Canon Raw Media Format],
    ),
    caption: [Supported RAW formats],
) <raw-formats>

== Audio File Formats

#app supports a number of basic uncompressed audio file formats across
platforms. On Windows and macOS a number of compressed formats may be
supported. Currently Microsoft WAV files and Apple's AIFF format are the
best bet for cross platform use. #app does support multichannel audio files
for playback to multichannel audio devices (see
#xref(<app-multichannel-layouts>)[Appendix I]).

== Simple ASCII EDL Format <ascii-edl>

Each line of the ASCII file is either blank, a comment, or an edit event. A
comment starts with a `#` character and continues until the end of a line. A
comment can appear on the same line as an edit event.

The format of an edit event is:

#code-block(lang: none, "\"SOURCE\" START END")

where _SOURCE_ is the path to a logical source movie such as:

#code-block(lang: none,
    "\"/some/path/to/foo.mov\"",
    "\"/some/path/to/bar.1-100#.exr\"",
    "\"/some/other_path/baz.1-100#.exr\"",
)

Note that the _SOURCE_ name must always be in double quotes. If the path
includes spaces, you do not need to use special escape characters to make
sure they are accepted. So this:

#code-block(lang: none, "\"/some/place with spaces/foo.mov\"")

is OK.

_START_ and _END_ are frame numbers in the movie. Note that _START_ is the
first frame to be included in the clip, and _END_ is the last frame to be
included (not, as in some EDL formats, the frame *after* the last frame). For
QuickTime #inline-shell(".mov") files or #inline-shell(".avi") files, the
first frame of the file is frame 1.

Here's an example #inline-shell(".rvedl") file:

#code-block(lang: none, ```
#
#  4 source movies
#

"/movies/foo.mov" 1 100
"/movies/bar.mov" 20 50
"/movies/render.1-100#.exr" 25 100
"/movies/with a space.#.exr" 1 25
```)
