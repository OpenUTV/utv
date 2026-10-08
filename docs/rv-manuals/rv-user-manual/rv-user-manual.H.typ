#import "../common/manual-lib.typ": *
#show: manual.with(appendix: true)

= PySide Example Usage <app-pyside>

#app ships with PySide6 on all platforms. In this section, we present two
simple examples of PySide usage. We also demonstrate how to access the #app
session window in the second example.

The first example, shown below, is a simple executable Python/PySide file
that uses #app's #inline-shell("py-interp"). Replace `/path/to/py-interp`
with the location of #inline-shell("py-interp") in your #app install.

#code-block(lang: "python", ```
#!/path/to/py-interp

# Import PySide classes
import sys
from PySide6.QtWidgets import QApplication, QLabel

# Create a Qt application.
# IMPORTANT: py-interp may already contain an instance of QApplication,
# so always check if an instance already exists.
app = QApplication.instance()
if app is None:
    app = QApplication(sys.argv)

# Display the file path of the app.
print(app.applicationFilePath())

# Create a Label and show it.
label = QLabel("Using PySide6")
label.show()

# Enter Qt application main loop.
sys.exit(app.exec())
```)

The second example is the `pyside_example` package that ships with #app. It
uses PySide for building its UI with Qt widgets that control property values
on an `RVLensWarp` node, and PyOpenGL to draw a spinning tetrahedron over
the image from its `render` event handler. Note too that in this example, the
current #app session `QMainWindow` is obtained from
`rv.qtutils.sessionWindow()` and we use it to change the session window's
opacity with the "Enable" checkbox.

This "PySide Example" can be loaded in #app through
#menu(("Preferences", "Packages")), and appears under
#menu(("Tools", "PySide Example")). The listing below is the package source
(`src/plugins/rv-packages/pyside_example/pyside_example.py`).

// Read straight from the source tree so the listing never goes stale. This
// needs the Typst root to be the repository root (--root ../../..).
#let example-source = (
    read("../../../src/plugins/rv-packages/pyside_example/pyside_example.py")
        .split("\n")
        .filter(l => not l.starts-with("#"))   // drop the license header
        .join("\n")
        .trim()
)

#code-block(lang: "python", example-source)
