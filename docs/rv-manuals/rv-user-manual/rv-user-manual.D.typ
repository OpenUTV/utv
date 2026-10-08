#import "../common/manual-lib.typ": *
#show: manual.with(appendix: true)

= Using #app as Nuke's Flipbook Player <app-nuke>

Nuke can easily be configured to use #app as a flipbook. Nuke can also be set
up to render out OpenEXR temp files instead of the default rgb files.

== Setting up a Custom Plugins Area for Nuke

In order to configure Nuke to work with #app, you should set up a custom
scripts/plugins directory where you can add new custom Nuke functionality
without disturbing the default Nuke install. This directory can be anywhere
on the `NUKE_PATH` environment variable, but note that the `$HOME/.nuke`
directory is always on that `NUKE_PATH`, so we'll assume we're working there
for now.

+ In your `$HOME/.nuke` directory, create a file called `init.py`, if it
  doesn't already exist, and also one called `menu.py`.

+ Add this line to the `init.py` file:

  #code-block(lang: "python", "nuke.pluginAddPath('./python')")

+ Create the directory referenced by the line we just added:

  #code-block("shell> mkdir $HOME/.nuke/python")

Done! Now Nuke will pick up new stuff from this area on start-up.

== Adding #app Support in the Custom Plugins Area

The following assumes that you've set up a custom plugin area as described in
the previous section.

+ Get the script `rv_this.py` (see the #app Nuke integration package
  documentation).

+ Move `rv_this.py` into `$HOME/.nuke/python`.

+ Add the following line to the `$HOME/.nuke/init.py` file, *after* the
  `pluginAddPath` lines mentioned above:

  #code-block(lang: "python", "import rv_this")

+ Add the following to the `$HOME/.nuke/menu.py` file:

  #code-block(lang: "python", ```
  menubar = nuke.menu("Nuke");
  menubar.addCommand("File/Flipbook Selected in &RV",
          "nukescripts.flipbook(rv_this.rv_this, nuke.selectedNode())", "#R")
  ```)

#app will now appear in the render menu and will be available with the hot
key #key("Alt+r").

To add an option to render your flipbook images in OpenEXR:

+ Find the file `nukescripts/flip.py` in your Nuke install and copy it to
  `$HOME/.nuke/python/flipEXR.py`.

+ Edit `$HOME/.nuke/python/flipEXR.py` and find the two lines that specify
  the output file name (search for `nuke_tmp_flip`) and change the file
  extension from `rgb` to `exr`.

+ Add the following line to the `$HOME/.nuke/menu.py` file:

  #code-block(lang: "python", ```
  menubar.addCommand("File/Flipbook Selected in &RV (EXR)",
          "flipEXR.flipbook(rv_this.rv_this, nuke.selectedNode())", "#E")
  ```)

Now you'll have the option in the #menu("File") menu to flipbook to EXR,
with the hotkey #key("Alt+e").

You can edit the `rv_this.py` script to specify any #app options you wish to
set as your viewing defaults. For example you could un-comment the script
lines that will apply #inline-shell("-gamma 2.2") or enable
#inline-shell("-sRGB"), or you could specify a file or display LUT for #app
to use.
