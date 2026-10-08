#import "../common/manual-lib.typ": *
#show: manual

= OpenColorIO <ch-ocio>

OpenColorIO (OCIO) is a software library which provides cross application
color consistency.

#quote(block: true)[
    *Note:* #app supports OCIO v2, but is limited to the legacy API of OCIO
    v1.
]

You can use OCIO in #app's display, look, viewing, linearize and color
pipelines. In each case OCIO can be used to convert from an incoming and
outgoing color space with a user defined OCIO context. OCIO requires some
work to set up and should be considered an advanced feature. Large
facilities may find OCIO particularly useful in #app when used in
conjunction with Nuke, Mari, or other products which support it.

You can learn about OpenColorIO at the
#link("https://opencolorio.org")[OpenColorIO website].

In order to use OCIO with #app a source setup package needs to be created
along with OCIO configuration files, LUTs, and an appropriate user
environment. #app comes with a package called `ocio_source_setup` which
implements a default policy for using OCIO. We recommend the package be
copied and modified to suit each facility that uses OCIO. When the OCIO
source setup package is enabled, parts or all of #app's existing color
pipelines may be replaced with OCIO equivalents.

#quote(block: true)[
    *Note:* The sample OCIO source setup package *supplements* the default
    `source_setup` and does not replace it; there is no need to turn off the
    default `source_setup`. We highly recommend copying and customizing the
    sample OCIO package for real world use.
]

There are four OCIO node types available in #app: `OCIOLook`, `OCIOFile`,
`OCIODisplay`, and the generic `OCIO` node. The default `ocio_source_setup`
will use these nodes to replace #app's existing color, look, and display
pipelines.

#app uses the OCIO GPU path instead of the more common CPU path for color
computation. There are slight differences between the two which you will
need to be aware of. Specifically, the color allocation parameters in the
config file can have a big effect on the quality of the OCIO LUTs generated
by the library.

The Reference Manual contains more detailed information about how to
configure #app's OCIO nodes.

== The ocio_source_setup Package

OpenColorIO defines color spaces which are used to transform images for
viewing or for storage in various file formats. It does not have any policy
about when to apply these transforms.

The provided `ocio_source_setup` package uses the default Sony Pictures
Imageworks method of detecting color space names in the incoming file names.
The package queries OCIO and if the file name matches, the package will use
OCIO nodes in various places in #app's pipelines instead of the usual #app
color processing. If the incoming file name does not match an OCIO color
space, the package will allow the existing #app color management to be used.

One gotcha with this package is that once an OCIO managed file name has been
detected, the package will use OCIO for the display correction as well. So
mixed OCIO and #app managed imagery will always be viewed using OCIO's
display color corrections.

The package provides a basic menu fashioned after the OCIO display example
program which allows you to choose file, look, and display transforms as well
as forcing unrecognized media to use OCIO.

In order to use the `ocio_source_setup` package you need to do the
following:

- Find the "OpenColorIO Basic Color Management" package in the Packages tab
  of the preferences. Make sure the "load" button next to the package name is
  activated and restart #app.
- Set the `OCIO` environment variable to the path to your config file.
- Start #app and load an image with the color space in the name.
- Note the #menu("OCIO") top-level menu that appears when you use #app this
  way. You can use this menu to choose a Linearizing transform, or Display
  transform, from those provided by your config.

The OpenColorIO mailing list and website are a good place to get help about
config files, documentation, and general operation.

=== Testing the Sample OCIO Source Setup

+ Find the "OpenColorIO Basic Color Management" Package in the Packages tab
  of the Preferences. Click the "Load" button next to the package and exit.

+ Set the `OCIO` environment variable to the path to your favorite OCIO
  config file:

  #code-block("shell> setenv OCIO /OCIO/spi-vfx/config.ocio")

+ Start #app and load an image with the color space in the name or otherwise
  (however is appropriate for your config).

  #appshell("/media/images/ocio_special_names/marcie_clean_lg10.cin")

+ Note the #menu("OCIO") top-level menu that appears when you use #app this
  way. You can use this menu to choose a Linearizing transform, or Display
  transform, from those provided by your config.

=== Operation of the OCIO Node

The OCIO node in the OpenColorIO Basic Color Management package is
configured to emulate three of the OCIO Nuke node types: color, look, and
display.

The OCIO nodes can be used in any of the #app pipelines as either a
supplement to #app's existing color pipeline or in place of it. The
pipelines are placed in #app's node graph in the places where all of the
significant color processing occurs. By default these pipelines contain
#app's color nodes (`RVLinearize`, `RVColor`, `RVLookLUT`,
`RVDisplayColor`).

The default OCIO package will swap in OCIO equivalent nodes for the existing
#app nodes. For example when using the SPI OCIO config with an "lg10" cineon
file the OCIO package will remove #app's `RVLinearize` node in the
linearization pipeline and replace it with an `OCIOFile` node set to take the
lg10 input by default and output scene referred linear. The default OCIO
package will also swap out the `RVDisplayColor` node (which does display
color correction) for an `OCIODisplay` node. The `OCIODisplay` node is set to
take scene referred linear and output to the default viewing transform (by
default).

There are four OCIO node types: `OCIONode`, `OCIOFile`, `OCIODisplay`, and
`OCIOLook`. All of them have the same properties; they only differ in their
default configuration. Each of them can be used in any context if desired.
The different node type names are primarily to make it easy to identify the
nodes from the user interface.

The generic `OCIONode` can be used as a top level (user) node. As with the
`RVColor` node the `OCIONode` can therefore be used as a secondary color
correction.

#quote(block: true)[
    *Note:* You can use both #app and OCIO nodes in any of the pipelines.
    However, the example package does not do this: the intention is to show
    how OCIO can be used (at least for some media) _in place of_ #app's color
    pipeline.
]

#figure(
    kind: table,
    table(
        columns: (auto, auto, 1fr),
        align: left,
        table.header[*Type*][*Property*][*Description*],
        [string], `ocio.function`, [One of "color", "look", or "display"],
        [float], `ocio.lut`, [Used internally to store the OCIO generated 3D LUT],
        [int], `ocio.active`, [Activates/deactivates the OCIO node],
        [int], `ocio.lut3DSize`, [The desired size of the OCIO generated 3D LUT (default=32)],
        [string], `ocio.inColorSpace`, [The OCIO name of the input color space],
        [string], `ocio_color.outColorSpace`, [The OCIO name of the output color space when `ocio.function == "color"`],
        [string], `ocio_look.look`, [The OCIO command string for the look when `ocio.function == "look"`],
        [int], `ocio_look.direction`, [0=forward, 1=inverse],
        [string], `ocio_display.display`, [OCIO display name when `ocio.function == "display"`],
        [string], `ocio_display.view`, [OCIO view name when `ocio.function == "display"`],
        [component], `ocio_context`, [String properties in this component become OCIO config name/value pairs],
    ),
    caption: [OCIO Node Properties],
) <ocio-node-properties>

=== The ocio_context Component

You can add properties to the OCIO node in #app to create an OCIO context.
Any string property in the component called `ocio_context` will become a
name/value pair for the OCIO context.
