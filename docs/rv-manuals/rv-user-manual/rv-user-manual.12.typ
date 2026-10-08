#import "../common/manual-lib.typ": *
#show: manual

= Stereo Viewing <ch-stereo>

#app can display the first two image layers as stereo. There are several
options:

- Anaglyph
- Side-by-Side
- Mirrored Side-by-Side
- DLP Checker
- Scanline Interleaved
- Left or Right eye only
- Hardware Left and Right Buffers

The stereo rendering is designed to work with the other features of #app. In
most cases, color corrections, image geometry manipulations, and display
corrections will work in conjunction with stereo viewing.

When caching is on, all layers are cached (left and right eyes). You will
need to reduce the image resolution to cache as many frames as non-stereo.

The left and right eye images are normalized (i.e. conformed to fit the #app
window) so they may have different resolutions and/or bit depths. However,
it is not advisable to have differing aspect ratios.

You can create stereo sources and set individual stereo parameters from the
command line. See #xref(<stereo-layers-cli>)[Section 3.2.2] to see how to do
this.

== Anaglyph or Luminance Anaglyph

The anaglyph modes display the left eye in the red channel and the right eye
in the green and blue channels (as cyan). If you were to wear colored
red-cyan glasses and the eyes are correctly arranged, you should be able to
see stereo with pseudo-color. Color anaglyph images work best for outdoor
scenes (with lots of green) and in similar cases. They work very poorly with
blue or green screen photography. For grey scale/non-color rendition of
anaglyph, select the "Luminance Anaglyph" mode (@luminance-anaglyph).

For color anaglyphs, if the color contrast is too great, the stereo effect
will be difficult to see. If you turn on luminance viewing (hit the #key("l")
key in the user interface), you can improve the effect
(@anaglyph-luminance). A similar solution is to desaturate the image
slightly (hit #key("S") and scrub); this will reduce the color contrast but
keep some hints of color (@anaglyph-desaturation).

Compression artifacts can seriously degrade stereo viewing especially in
anaglyph mode. QuickTime movies, for example, with low quality compression
may look fine when viewed one eye at a time, but in anaglyph mode JPEG or
similar artifacts will be greatly amplified by slight color differences. The
best way to view compressed material is with luminance display turned on (no
color).

#figure(
    img("rv-user-manual-52-rv-cx-se-dice-anaglyph-51.png"),
    caption: [Anaglyph Stereo Display],
) <anaglyph>

#figure(
    img("rv-user-manual-53-rv-cx-dice-luma-anaglyph-52.png"),
    caption: [Anaglyph Stereo With Luminance Display],
) <anaglyph-luminance>

#figure(
    img("rv-user-manual-54-rv-cx-dice-desat-anaglyph-53.png"),
    caption: [Anaglyph Display With Desaturation],
) <anaglyph-desaturation>

#figure(
    img("rv-user-manual-dice-lumanaglyph-54.png"),
    caption: [Luminance Anaglyph Display],
) <luminance-anaglyph>

== Side-by-Side and Mirror

Side-by-Side mode displays the left and right eyes next to each other
horizontally in full color. Some people are comfortable crossing their eyes
to see stereo using this mode.

Mirror mode is similar, but the right eye is flopped. If you need the left
eye flopped, turn on mirror mode and select #menu(("Image", "Flop")) or hit
#key("X"); this will have the effect of mirroring the left eye instead. Note
that the same effect can be produced by flopping the right eye only in
mirror mode.

#figure(
    img("rv-user-manual-55-rv-cx-dice-side-by-side-55.jpg"),
    caption: [Side-by-Side Stereo Display],
)

#figure(
    img("rv-user-manual-56-rv-cx-ease-dice-mirror-56.jpg"),
    caption: [Mirror Display Mode],
)

== DLP Checker and Scanline

These modes are designed to work with DLP projectors or LCD displays that
directly support stereo display. In particular #app supports the SpectronIQ
HD LCD display and DLP projectors using the Texas Instruments checkerboard
3D DLP input.

#figure(
    img("rv-user-manual-57-rv-dice-dlp-and-scanline-57.jpg"),
    caption: [DLP (left) and LCD Scanline (right) Stereo Display],
)

== HDMI 1.4a

HDMI 1.4a stereo modes like Side-by-Side and Top-and-Bottom are supported via
#app's Presentation Mode, described in #xref(<ch-presentation>)[Chapter 6].
To select one of these modes for your Presentation Device, you choose the
appropriate Output Data Format in the Video preferences.

== Hardware Stereo Support

#app can render into left and right buffers if your graphics card supports
hardware stereo. You can tell if this is the case by seeing if the menu item
#menu(("View", "Stereo", "Hardware")) can be selected. If so, #app should be
able to create left and right buffers. There are a number of different ways
to view stereo with a standard graphics card. See
#xref(<app-stereo-setup>)[Appendix B] for information about how to set up
each platform and what options are available at the hardware level.

Typically, hardware support requires shutter glasses (monitor or projection)
or polarized glasses (projection only) in order to be useful.

== Additional Stereo Operations

These options can be applied per-source as well as part of the global
viewing stereo options. The per-source options can be found under the
#menu(("Image", "Stereo")) menu and the global view options are under
#menu(("View", "Stereo")).

=== Swap Eyes

Swap eyes changes the order of the left and right eyes (left becomes right
and vice versa). If you are looking at stereo pairs and you just cannot see
the stereo, you may want to try swapping the eyes. It is difficult to view
stereo when the eyes are inverted.

=== Relative Eye Offset

Relative eye offset controls how separated the left and right images are
horizontally. In the case of the anaglyph and hardware left and right buffer
modes the offset value determines the fusion depth. Objects at the fusion
depth appear coincident with the screen depth. In other words, they appear
to be right on the screen: not behind it or in front of it. This is most
evident in the anaglyph mode where the red and cyan components of a shape
will not be separated if it's at the fusion depth. The units of the offset
numbers are a percentage of the image width.

You have a choice to either offset the eye images away from each other (both
at the same time) or to offset the right eye only.

#figure(
    img("rv-user-manual-58-rv-cx-dice-offset-change-58.png"),
    caption: [Changing stereo relative eye offset. The left is the original
        image viewed in anaglyph mode. The right has an additional offset
        applied.],
)

=== Flip/Flop the Right Eye Only

If you are projecting stereo and require one eye be flipped (vertical) or
flopped (horizontal), you can select
#menu(("Image", "Stereo", "Flip Right Eye")) or
#menu(("Image", "Stereo", "Flop Right Eye")). This can further be combined
with #menu(("Image", "Flip")) and #menu(("Image", "Flop")) and rotation to
move the images into the correct position.

#figure(
    img("rv-user-manual-59-rv-cx-dice-one-eye-flipped-59.jpg"),
    caption: [Flipping One Eye],
)
