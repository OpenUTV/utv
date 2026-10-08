#import "../common/manual-lib.typ": *
#show: manual

= #lsapp <ch-rvls>

#lsapp provides command line information about images, sequences, movie
files and audio files.

By default #lscmd with no arguments will list the contents of the current
directory. Unlike its namesake #inline-shell("ls"), #lscmd will contract
image sequences into a single listing. The output image sequences can be used
as arguments to #appcmd or #iocmd#footnote[You can use #lsapp to create image
sequence completions in bash or tcsh for #appcmd and #iocmd. See the
Reference Manual for an example.].

For more detailed information about a file or sequence the
#inline-shell("-l") option can be used: this will show each file or sequence
on a separate line with the image width and height, channel bit depth, and
number of channels. For movie files and audio files, additional information
about the audio like the sample rate and number of channels will be
displayed.

#code-block(lang: none,
    "shell> " + lscmd + " -l",
    "        w x h      typ   #ch   file",
    "      623 x 261    16i   3     ./16bit.tiff",
    "     1600 x 1071    8i   3     ./2287176218_5514bbc63a_o.jpg",
    "     1024 x 680     8i   3     ./best-picture.jpg",
    "     2048 x 1556   16f   3     ./sheet.hi.90.exr",
    "     5892 x 4800    8i   1     ./BurialMount.psd",
    "       64 x 64      8i   1     ./caust19.bw",
    "     5892 x 4992    8i   1     ./common_sense.psd",
    "      640 x 486    16i   3     ./colorWheel.685.cin",
    "      640 x 480     8i   1     ./colour-bars-smpte-75-640x480.tiff",
)

or to see certain files in a directory as a sequence:

#code-block(lang: none,
    "shell> ls *.iff",
    "render_maya.1.iff",
    "render_maya.10.iff",
    "render_maya.2.iff",
    "render_maya.3.iff",
    "render_maya.4.iff",
    "render_maya.5.iff",
    "render_maya.6.iff",
    "render_maya.7.iff",
    "render_maya.8.iff",
    "render_maya.9.iff",
    "shell> " + lscmd + " *.iff",
    "render_maya.1-10@.iff",
)

It is also possible to list the image attributes using #lsapp using the
#inline-shell("-x") option. This will display the same attribute information
that is displayed in #app's Image Info Widget:

#code-block(lang: none,
    "shell> " + lscmd + " -x unnamed_5_channel.exr",
    "unnamed_5_channel.exr:",
    "",
    "             Resolution   640 x 480, 5ch, 16 bits/ch floating point",
    "               Channels",
    "       PixelAspectRatio   1",
    "  EXR/screenWindowWidth   1",
    " EXR/screenWindowCenter   (0 0)",
    "   EXR/pixelAspectRatio   1",
    "          EXR/lineOrder   INCREASING_Y",
    "      EXR/displayWindow   (0 0) - (639 479)",
    "         EXR/dataWindow   (0 0) - (639 479)",
    "        EXR/compression   ZIP_COMPRESSION",
    "             Colorspace   Linear",
)

Additional command line options can be seen in @rvls-options.

#figure(
    kind: table,
    table(
        columns: (auto, 1fr),
        align: left,
        table.header[*Option*][*Description*],
        [`-a`], [Show hidden files],
        [`-s`], [Show sequences only (no non-sequence member files)],
        [`-l`], [Show long listing],
        [`-x`], [Show extended attributes and image structure],
        [`-b`], [Use brute force if no reader found],
        [`-nr`], [Do not show frame ranges],
        [`-ns`], [Do not infer sequences (list each file separately)],
        [`-min` _int_], [Minimum number of files considered a sequence (default=3)],
        [`-formats`], [List image/movie formats],
        [`-version`], [Show #lscmd version number],
    ),
    caption: [#lsapp Options],
) <rvls-options>
