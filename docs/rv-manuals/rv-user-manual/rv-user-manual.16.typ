#import "../common/manual-lib.typ": *
#show: manual

= #ioapp <ch-rvio>

#ioapp is a command line (re)mastering tool -- it converts image sequences,
audio files, and movie files from one format into another including possible
bit depth and image color and size resolution changes. #ioapp can also
generate custom slate frames, add per-frame information and matting directly
onto output images, and change color spaces (to a limited extent).

#ioapp supports all of the same movie, image, and audio formats that #app
does including the #inline-shell(".rv") session file. #app session files
(#inline-shell(".rv")) can be used to specify compositing operations, split
screens, tiling, color corrections, pixel aspect ratio changes, etc.

#figure(
    kind: table,
    table(
        columns: (auto, 1fr),
        align: left,
        table.header[*Option*][*Description*],
    [`-o` _string_], [Output sequence or image],
    [`-t` _string_], [Output time range (default=input time range)],
    [`-tio`], [Output time range from rv session files in/out points],
    [`-v`], [Verbose messages],
    [`-vv`], [Really verbose messages],
    [`-q`], [Best quality for color conversions (slower – mostly unnecessary)],
    [`-noRanges`], [No separate frame ranges (1-10 will be considered a file)],
    [`-rthreads` _int_], [Number of reader/render threads (default=1)],
    [`-wthreads` _int_], [Number of writer threads (default=same as -rthreads)],
    [`-formats`], [Show all supported image and movie formats],
    [`-iomethod` _int \[int\]_], [I/O Method (0=standard, 1=buffered, 2=unbuffered, 3=MemoryMap, 4=AsyncBuffered, 5=AsyncUnbuffered, default=3) and optional chunk size (default=61440)],
    [`-view` _string_], [View to render (default=defaultSequence or current view in rv file)],
    [`-leader` _..._], [Insert leader/slate (can use multiple times)],
    [`-leaderframes` _int_], [Number of leader frames (default=1)],
    [`-overlay` _..._], [Visual overlay(s) (can use multiple times)],
    [`-inlog`], [Convert input to linear space via Cineon Log→Lin],
    [`-insrgb`], [Convert input to linear space from sRGB space],
    [`-in709`], [Convert input to linear space from Rec-709 space],
    [`-ingamma` _float_], [Convert input using gamma correction],
    [`-fileGamma` _float_], [Convert input to linear space using gamma correction],
    [`-inchannelmap` _..._], [map input channels],
    [`-inpremult`], [premultiply alpha and color],
    [`-inunpremult`], [un-premultiply alpha and color],
    [`-exposure` _float_], [Apply relative exposure change (in stops)],
    [`-scale` _float_], [Scale input image geometry],
    [`-resize` _int \[int\]_], [Resize input image geometry to exact size on input (0 = maintain image aspect)],
    [`-resampleMethod` _string_], [Resampling method (area, linear, cubic, nearest, default=area)],
    [`-floatLUT` _int_], [Use floating point LUTs (1=yes, 0=no, default=1)],
    [`-flut` _string_], [Apply file LUT],
    [`-dlut` _string_], [Apply display LUT],
    [`-flip`], [Flip image (flip vertical) (keep orientation flags the same)],
    [`-flop`], [Flop image (flip horizontal) (keep orientation flags the same)],
    [`-yryby` _int int int_], [Y RY BY sub-sampled planar output],
    [`-yrybya` _int int int int_], [Y RY BY A sub-sampled planar output],
    [`-yuv` _int int int_], [Y U V sub-sampled planar output],
    [`-outparams` _..._], [Codec specific output parameters],
    [`-outchannelmap` _..._], [map output channels],
    [`-outrgb`], [same as -outChannelMap R G B],
    [`-outpremult`], [premultiply alpha and color],
    [`-outunpremult`], [un-premultiply alpha and color],
    [`-outlog`], [Convert output to log space via Cineon Lin→Log],
    [`-outsrgb`], [Convert output to sRGB ColorSpace],
    [`-out709`], [Convert output to Rec-709 ColorSpace],
    [`-outgamma`], [Apply gamma to output],
    [`-outstereo` _string_], [Output stereo (checker, scanline, anaglyph, lumanaglyph, left, right, pair, mirror, hsqueezed, vsqueezed, default=separate)],
    [`-outformat` _int string_], [Output bits and format (e.g. 16 float -or- 8 int)],
    [`-outhalf`], [Same as -outformat 16 float],
    [`-out8`], [Same as -outformat 8 int],
    [`-outres` _int int_], [Output resolution (image will be fit, not stretched)],
    [`-outfps`], [Output FPS],
    [`-codec` _string_], [Output codec (varies with file format)],
    [`-audiocodec` _string_], [Output audio codec (varies with file format)],
    [`-audiorate` _float_], [Output audio sample rate (default from input)],
    [`-audiochannels` _int_], [Output audio channels (default from input)],
    [`-quality` _float_], [Output codec quality 0.0 → 1.0 (use varies with file format and codec default=0.900000)],
    [`-outpa` _float_], [Output pixel aspect ratio (e.g. 1.33 or 4:3, etc, metadata only) default=1:1],
    [`-comment` _string_], [Output comment (movie files, default="")],
    [`-copyright` _string_], [Output copyright (movie files, default="")],
    [`-debug` _string_], [Debug category],
    [`-version`], [Show #ioapp version number],
    [`-exrcpus` _int_], [EXR decoder thread count (default = number of logical cores)],
    [`-exrRGBA`], [EXR use basic RGBA interface (default=false)],
    [`-exrInherit`], [EXR guesses channel inheritance (default=false)],
    [`-exrIOMethod` _int \[int\]_], [EXR I/O Method (0=standard, 1=buffered, 2=unbuffered, 3=MemoryMap, 4=AsyncBuffered, 5=AsyncUnbuffered, default=0) and optional chunk size (default=61440)],
    [`-jpegRGBA`], [Make JPEG four channel RGBA on read (default=no, use RGB or YUV)],
    [`-jpegIOMethod` _int \[int\]_], [JPEG I/O Method (0=standard, 1=buffered, 2=unbuffered, 3=MemoryMap, 4=AsyncBuffered, 5=AsyncUnbuffered, default=0) and optional chunk size (default=61440)],
    [`-cinpixel` _string_], [Cineon/DPX pixel storage (default=RGB16)],
    [`-cinchroma`], [Use file chromaticity values (ignores them by default)],
    [`-cinIOMethod` _int \[int\]_], [Cineon I/O Method (0=standard, 1=buffered, 2=unbuffered, 3=MemoryMap, 4=AsyncBuffered, 5=AsyncUnbuffered, default=3) and optional chunk size (default=61440)],
    [`-dpxpixel` _string_], [DPX pixel storage (default=RGB16)],
    [`-dpxchroma`], [Use DPX chromaticity values (ignores them by default)],
    [`-dpxIOMethod` _int \[int\]_], [DPX I/O Method (0=standard, 1=buffered, 2=unbuffered, 3=MemoryMap, 4=AsyncBuffered, 5=AsyncUnbuffered, default=3) and optional chunk size (default=61440)],
    [`-tgaIOMethod` _int \[int\]_], [TARGA I/O Method (0=standard, 1=buffered, 2=unbuffered, 3=MemoryMap, 4=AsyncBuffered, 5=AsyncUnbuffered, default=2) and optional chunk size (default=61440)],
    [`-tiffIOMethod` _int \[int\]_], [TIFF I/O Method (0=standard, 1=buffered, 2=unbuffered, 3=MemoryMap, 4=AsyncBuffered, 5=AsyncUnbuffered, default=2) and optional chunk size (default=61440)],
    [`-init` _string_], [Override init script],
    [`-err-to-out`], [Output errors to standard output (instead of standard error)],
    [`-noprerender`], [Turn off prerendering optimization],
    [`-flags` _..._], [Arbitrary flags (flag, or 'name=value') for Mu or Python],    ),
    caption: [#iocmd Options],
) <rvio-options>

== Basic Usage

=== Image Sequence Format Conversion

#ioapp's most basic operation is to convert a sequence of images from one
format into another. #ioapp uses the same sequence notation as #app to
specify input and output sequences. For example:

#ioshell(
    "foo.#.exr -o foo.#.tif",
    "foo.#.exr -o foo.#.jpg",
)

=== Image Sequence to QuickTime Movie Conversion

#ioapp can write out QuickTime movies. The default compression codec is
PhotoJPEG with a default quality of 0.9.

#ioshell("foo.#.exr -o foo.mov")

=== Resizing and Scaling

#ioapp does high quality filtering when it resizes images. Output resolution
can be specified explicitly, in which case #ioapp will conform to the new
resolution, padding the image to preserve pixel aspect ratio.

#ioshell(
    "foo.1-100@@@@.tga -scale 0.5 -o foo.#.tga",
    "foo.#.exr -outres 640 480",
)

Or you can use the #inline-shell("-resize x y") option, in which case
scaling will occur in either dimension (unless the number specified for that
dimension is 0).

=== Adding Audio to Movies

#ioapp uses the same layer notation as #app to combine audio with image
sequences. Multiple audio sources can be mixed in a single layer.

#ioshell(
    "[ foo.1-300#.tif foo.aiff ] -o foo.mov",
    "[ foo.1-300#.tif foo.aiff bar.aiff ] -o foo.mov",
)

== Advanced Usage

=== Editing Sequences

#ioapp can combine multiple sequences and write out a single output sequence
or movie. This allows you to quickly edit and conform.

#ioshell(
    "foo.25-122#.exr bar.8-78#.exr -o foo.mov",
    "[ foo.#.exr foo.aiff ] [ bar.#.exr bar.aiff ] \\",
    "       -o foobar.mov",
)

Note that you can cut in and out of movie files as well:

#ioshell("[ foo.mov -in 101 -out 120 ] [ bar.mov -in 58 -out 123 ] -o out.mov")

=== Processing #app Session Files

#app session files can be used as a way to author operations for processing
with #ioapp. Most operations and settings in #app can be used by #ioapp. For
example #app can be used in a compositing mode to do an over or difference
or split-screen comparison. #app can also be used to set up edits with per
source color corrections (e.g. a unique LUT for each sequence, exposure or
color adjustments per sequence, an overall output LUT, etc.).

#ioshell("foo.rv -o foo.mov")

Any View in the session file can be used as the source for the #ioapp
output:

#ioshell("foo.rv -o foo.mov -view \"latest shots\"")

=== Advanced Image Conversions

#ioapp has flags to handle standard colorspace, gamma, and log/lin
conversions for both inputs and outputs.

#ioshell(
    "foo.#.cin -inlog -o foo.#.exr",
    "foo.#.exr -o foo.#.cin -outlog",
    "foo.#.jpeg -insrgb -o foo.#.exr",
    "foo.#.exr -o foo.#.tiff -outgamma 2.2",
    "foo.#.exr -o foo.#.jpeg -outsrgb",
    "foo.#.cin -inlog -o foo.mov -outsrgb \\",
    "       -comment \"Movie is in sRGB space\"",
)

=== LUTs

#ioapp can apply a LUT to input files and an output LUT. #ioapp's command
line only supports one file LUT and one display LUT. The file LUT will be
applied to all the input sources before conversion and the output LUT will
be applied to the entire session on output. If you need to process sequences
with a different file LUT per sequence, you can do that by creating #a-app
session file with the desired LUTs and color settings to use as input to
#ioapp.

#ioshell(
    "foo.#.cin bar.#.cin -inlog -flut in.cube \\",
    "       -dlut out.cube -o foobar.mov",
)

=== Pixel Storage Formats and Channel Mapping

#ioapp provides control over pixel storage (floating point or integer, bit
depth, planar subsampling) and channel mapping. The planar subsampling
options are particularly used to support OpenEXR's B44 compression, which is
a fixed bandwidth, floating point, high-dynamic range compression scheme.

#ioshell(
    "foo.#.exr -outformat 8 int -o foo.#.tif",
    "foo.#.exr -outformat 8 int -o foo.#.tif -outrgb",
    "foo.#.cin -inlog -o foo.#.tiff -outformat 16 float",
    "foo.#.exr -outformat 32 float -o foo.#.tif",
    "foo.#.exr -codec B44A -yrybya 1 2 2 2 -outformat \\",
    "       16 float",
    "foo.#.exr -codec B44A -yryby 1 2 2 -outformat \\",
    "       16 float -outchannelmap R G B",
)

=== Advanced QuickTime Movie Conversions

#ioapp uses ffmpeg for reading and writing. You can find out what codecs are
available for reading and writing by using the #inline-shell("-formats")
flag. This will also tell you the full name of the encoder, e.g. writing
Motion JPEG requires "mjpeg" by ffmpeg. #ioapp lets you specify the output
codec and can collect parameters for the output from
#inline-shell("-outparams"). Please examine the following two examples. The
first is with the default settings for mjpeg's Motion JPEG writing, and the
second is a popular command derived from using the ffmpeg binary directly,
something of the form:

#code-block(
    "shell> ffmpeg -i foo.%04d.tif -ac 2 -b:v 2000k -c:a pcm_s16be -c:v mjpeg \\",
    "       -pix_fmt yuv420p -g 30 -b:a 160k -vprofile high -bf 0 \\",
    "       -strict experimental -f mov outfile.mov",
)

#ioshell(
    "foo.#.tif -codec mjpeg -o foo.mov",
    "foo.#.tif -codec mjpeg -audiocodec pcm_s16be \\",
    "       -outparams pix_fmt=yuv420p vcc:b=2000000 acc:b=160000 \\",
    "       vcc:g=30 vcc:profile=high vcc:bf=0 -o foo.mov",
)

=== Audio Conversions

#ioapp can operate directly on audio files and can also add or extract audio
to/from QuickTime movies. #ioapp provides flags to set the audio codec,
sample rate, storage format (8, 16, and 32 bits), storage type (int, float),
and number of output channels. #ioapp does high quality resampling using 32
bit floating point operations. #ioapp will mix together multiple audio files
specified in a layer.

#ioshell(
    "foo.mov -o foo.aiff",
    "foo.mov -o foo.aiff -audiorate 22050",
    "[ foo.#.exr foo.aiff bar.wav ] -codec H.264 \\",
    "       -quality 1.0 \\",
    "       -audiocodec \"Apple Lossless\" -audiorate 44100 \\",
    "       -audioquality 1.0 -o foo.mov",
)

=== Stereoscopic and Multiview Conversions

#app and #ioapp support stereoscopic playback and conversions. #ioapp can be
used to create stereo QuickTime files or multiview OpenEXR files (Weta's SXR
files) by specifying two input layers and using the
#inline-shell("-outstereo") flag. Stereo QuickTime movies contain multiple
video tracks. #app interprets the first two tracks as left and right views.
#ioapp will also render output using stereo modes specified in #a-app session
file -- this allows you to output anaglyph images from stereo inputs or to
render out scanline or alternating pixel stereo material.

#ioshell(
    "[ foo_l.#.exr foo_r.#.exr foo.aiff ] -outstereo \\",
    "       -o stereo.mov",
    "[ foo_left.#.exr foo_right.#.exr ] -outstereo \\",
    "       -o stereo.#.exr",
)

Or you can specify an output stereo format:

#ioshell(
    "[ foo_l.#.exr foo_r.#.exr foo.aiff ] -outstereo hsqueezed \\",
    "       -o stereo.mov",
)

=== Slates, Mattes, Watermarks, and Burn-ins

#ioapp supports script based creation of slates and overlays. The default
scripts that come with #app can be used as is, or they can be customized to
create any kind of overlay or slate that you need. Customization of these
scripts is covered in the #app Reference Manual. #ioapp has two command line
flags to manage these scripts, #inline-shell("-leader") and
#inline-shell("-overlay"). #inline-shell("-leader") scripts are used to
create slates or other frames that will be added to the beginning of a
sequence or movie. #inline-shell("-overlay") scripts will draw on top of the
image frames. Multiple overlays can be layered on top of the image, so that
you can build up a frame with mattes, frame burn-in, bugs, etc. The scripts
that come with #app include:

- `simpleslate`
- `watermark`
- `matte`
- `frameburn`
- `bug`

==== Simpleslate Leader

Simpleslate allows you to build up a slate from a list of attribute/value
pairs. It will automatically scale all of your text to fit onto the frame.
It works like this:

#ioshell(
    "foo.#.exr -leader simpleslate \\",
    "       \"Acme Post\" \"Show=My Show\" \"Shot=foo\" \"Type=comp\" \\",
    "       \"Artist=John Doe\" \"Comments=Lighter and Darker as \\",
    "       requested by director\" -o foo.mov",
)

==== Watermark Overlay

The watermark overlay burns a text comment onto output images. This makes it
easy to generate custom watermarked movies for clients or vendors. Watermark
takes two arguments, the comment in quotes and the opacity (from 0 to 1).

#ioshell(
    "foo.mov -overlay watermark \"For Client X Review\" 0.1 \\",
    "       -o foo_client_x.mov",
)

==== Matte Overlay

The matte overlay mattes your images to the desired aspect ratio. It takes
two arguments, the aspect ratio and the opacity.

#ioshell("foo.#.exr -overlay matte 2.35 1.0 -o foo.mov")

==== Frameburn Overlay

The frameburn overlay renders the source frame number onto each frame. It
takes three arguments, the opacity, the luminance, and the size.

#ioshell("foo.#.exr -overlay frameburn 0.1 0.1 50 -o foo.mov")

==== Bug Overlay

The bug overlay lets you render an image on top of each output frame. It
takes three arguments, the image name, the opacity, and the size.

#ioshell("foo.#.exr -overlay bug \"/path/to/logo.tif\" 0.5 48")

=== EXR Attributes

#ioapp can create and pass through header attributes. To create an attribute
from the command line use #inline-shell("-outparams"):

#ioshell("in.exr -o foo.exr -outparams NAME:TYPE=VALUE0,VALUE1,VALUE2,...")

_TYPE_ is one of:

#table(
    columns: 2,
    align: left,
    table.header[*TYPE*][*Attribute type*],
    `f`, `float`,
    `i`, `int`,
    `s`, `string`,
    `sv`, `Imf::StringVector`,
    `v2i`, `Imath::V2i`,
    `v2f`, `Imath::V2f`,
    `v3i`, `Imath::V3i`,
    `v3f`, `Imath::V3f`,
    `b2i`, `Imath::Box2i`,
    `b2f`, `Imath::Box2f`,
    `m33f`, `Imath::M33f`,
    `m44f`, `Imath::M44f`,
    `c`, `Imf::Chromaticities`,
)

Values are comma separated. For example to create an `Imath::V2i` attribute
called `myvec` with the value `V2i(1,2)`:

#ioshell("in.exr -o out.exr -outparams myvec:v2i=1,2")

similarly a string vector attribute would be:

#ioshell("in.exr -o out.exr -outparams mystringvector:sv=one,two,three,four")

and a 3 by 3 float matrix attribute would be:

#ioshell("in.exr -o out.exr -outparams myfloatmatrix:m33f=1.0,2.0,3.0,4.0,5.0,6.0,7.0,8.0,9.0")

where the first row of the matrix would be 1.0 2.0 3.0.

If you want to pass through attributes from the incoming image to the output
EXR file you can use the `passthrough` variable. Setting `passthrough` to a
regular expression will cause the writer code to select matching incoming
attribute names.

#ioshell("in.exr -o out.exr -outparams \"passthrough=.*\"")

The name matching includes any non-EXR format identifiers that are created
by #app and #ioapp.

#ioshell("in.jpg -o out.exr -insrgb -outparams \"passthrough=.*EXIF.*\"")

The name matching includes any EXIF attributes (e.g. from TIFF or JPEG
files).

=== IIF/ACES Files

#ioapp can convert pixels to the very wide gamut ACES color space for output
using the #inline-shell("-outaces") flag. In addition, use of the
#inline-shell(".aces") extension will cause the OpenEXR writer to enforce
the IIF container subset of EXR. For example, to convert an existing EXR
file to an IIF file:

#ioshell("in.exr -o out.aces -outaces")

It's possible to write to other formats using #inline-shell("-outaces"), but
it's not recommended.

=== DPX Header Fields

Using #inline-shell("-outparams") it's possible to set almost any DPX header
field. Setting the field will not change the pixels in the final file, just
the value of the header field.

There are a couple of fields treated in a special way: the
`film/frame_position`, `tv/time_code`, and `tv/user_bits` fields are all
incremented automatically when a sequence of frames is output. In the case
of `tv/user_bits` and `tv/time_code`, the initial value comes either from the
output frame number, or starting at the time code passed in.

#figure(
    kind: table,
    table(
        columns: (auto, 1fr),
        align: left,
        table.header[*Keyword*][*Description*],
        `transfer`, [Transfer function (LOG, DENSITY, REC709, USER, VIDEO, SMPTE274M, REC601-625, REC601-525, NTSC, PAL, or number)],
        `colorimetric`, [Colorimetric specification (REC709, USER, VIDEO, SMPTE274M, REC601-625, REC601-525, NTSC, PAL, or number)],
        `creator`, [ASCII string],
        `copyright`, [ASCII string],
        `project`, [ASCII string],
        `orientation`, [Pixel origin string or int (TOP_LEFT, TOP_RIGHT, BOTTOM_LEFT, BOTTOM_RIGHT, ROTATED_TOP_LEFT, ROTATED_TOP_RIGHT, ROTATED_BOTTOM_LEFT, ROTATED_BOTTOM_RIGHT)],
        `create_time`, [ISO 8601 ASCII string: `YYYY:MM:DD:hh:mm:ssTZ`],
        `film/mfg_id`, [2 digit manufacturer ID edge code],
        `film/type`, [2 digit film type edge code],
        `film/offset`, [2 digit film offset in perfs edge code],
        `film/prefix`, [6 digit film prefix edge code],
        `film/count`, [4 digit film count edge code],
        `film/format`, [32 char film format (e.g. Academy)],
        `film/frame_position`, [Frame position in sequence (0 indexed)],
        `film/sequence_len`, [Sequence length],
        `film/frame_rate`, [Frame rate (frames per second)],
        `film/shutter_angle`, [Shutter angle in degrees],
        `film/frame_id`, [32 character frame identification],
        `film/slate_info`, [100 character slate info],
        `tv/time_code`, [SMPTE time code as an ASCII string (e.g. 01:02:03:04)],
        `tv/user_bits`, [SMPTE user bits as an ASCII string (e.g. 01:02:03:04)],
        `tv/interlace`, [Interlace (0=no, 1=2:1)],
        `tv/field_num`, [Field number],
        `tv/video_signal`, [Video signal standard 0-254 (see DPX spec)],
        `tv/horizontal_sample_rate`, [Horizontal sampling rate in Hz],
        `tv/vertical_sample_rate`, [Vertical sampling rate in Hz],
        `tv/frame_rate`, [Temporal sampling rate or frame rate in Hz],
        `tv/time_offset`, [Time offset from sync to first pixel in ms],
        `tv/gamma`, [Gamma],
        `tv/black_level`, [Black level],
        `tv/black_gain`, [Black gain],
        `tv/break_point`, [Breakpoint],
        `tv/white_level`, [White level],
        `tv/integration_times`, [Integration times],
        `source/x_offset`, [X offset],
        `source/y_offset`, [Y offset],
        `source/x_center`, [X center],
        `source/y_center`, [Y center],
        `source/x_original_size`, [X original size],
        `source/y_original_size`, [Y original size],
        `source/file_name`, [Source file name],
        `source/creation_time`, [Source creation time `YYYY:MM:DD:hh:mm:ssTZ`],
        `source/input_dev`, [Input device name],
        `source/input_serial`, [Input device serial number],
        `source/border_XL`, [Border validity left],
        `source/border_XR`, [Border validity right],
        `source/border_YT`, [Border validity top],
        `source/border_YB`, [Border validity bottom],
        `source/pixel_aspect_H`, [Pixel aspect ratio horizontal component],
        `source/pixel_aspect_V`, [Pixel aspect ratio vertical component],
    ),
    caption: [DPX Output Parameters],
) <dpx-output-params>

This example sets the start time code of the DPX sequence:

#ioshell("in.#.tif -o out.#.dpx -outparams tv/time_code=00:11:22:00")

It is also possible to set the alignment of pixel data relative to the start
of the file using `alignment`. For example, to force the pixel data to start
at byte 4096 in the DPX file:

#ioshell("in.#.tif -o out.#.dpx -outparams alignment=4096")

The smallest value for alignment is 2048 which includes the size of the
default DPX headers.

The DPX writer cannot automatically pass through header fields from input DPX
images to the output DPX images.

To set the project header value:

#ioshell("in.#.exr -o out.#.dpx -outparams \"project=THE PROJECT\"")

To set colorspace header values:

#ioshell("in.#.exr -o out.#.dpx -outparams transfer=LINEAR colorimetric=REC709")
