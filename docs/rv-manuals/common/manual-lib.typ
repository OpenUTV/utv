// Shared helpers and document template for the RV / OpenRV / OpenUTV manuals.
//
//   #import "manual-lib.typ": *
//   #show: manual
//
// Select the product at build time:
//   typst compile --input product=openrv rv-user-manual.typ

// org and prefs are guesses for rv/openrv. TODO: verify.
#let products = (
    rv: (
        app: "RV", article: "an", appcmd: "rv",
        ioapp: "RVIO", iocmd: "rvio",
        lsapp: "RVLS", lscmd: "rvls",
        pkgcmd: "rvpkg",
        pushapp: "RVPUSH", pushcmd: "rvpush",
        org: "ASWF",
        prefs: (
            macos: "~/Library/Preferences/com.tweaksoftware.RV.plist",
            linux: "~/.config/TweakSoftware/RV.conf",
            windows: "%APPDATA%\\TweakSoftware\\RV.ini",
        ),
        features: (),
    ),
    openrv: (
        app: "OpenRV", article: "an", appcmd: "rv",
        ioapp: "RVIO", iocmd: "rvio",
        lsapp: "RVLS", lscmd: "rvls",
        pkgcmd: "rvpkg",
        pushapp: "RVPUSH", pushcmd: "rvpush",
        org: "ASWF",
        prefs: (
            macos: "~/Library/Preferences/com.tweaksoftware.RV.plist",
            linux: "~/.config/TweakSoftware/RV.conf",
            windows: "%APPDATA%\\TweakSoftware\\RV.ini",
        ),
        features: (),
    ),
    openutv: (
        app: "UTV", article: "a", appcmd: "utv",
        ioapp: "UTVIO", iocmd: "utvio",
        lsapp: "UTVLS", lscmd: "utvls",
        pkgcmd: "utvpkg",
        pushapp: "UTVPUSH", pushcmd: "utvpush",
        org: "OpenUTV",
        prefs: (
            macos: "~/Library/Preferences/com.openutv.UTV.plist",
            linux: "~/.config/OpenUTV/UTV.conf",
            windows: "%APPDATA%\\OpenUTV\\UTV\\OpenUTV\\UTV.ini",
        ),
        features: (),
    ),
)

#let product = sys.inputs.at("product", default: "openutv")
#assert(product in products, message: "unknown product: " + product)
#let names = products.at(product)

// Release version shown on the title page, in the PDF footer and in the HTML
// title. build-docs.sh passes it (see docs-version.sh); chapter text can use
// #version too.
#let version = sys.inputs.at("version", default: "development")

#let app = names.app
// "a UTV" / "an RV": use #a-app mid-sentence and #A-app to start one
#let a-app = names.article + " " + names.app
#let A-app = upper(names.article.first()) + names.article.slice(1) + " " + names.app
#let appcmd = names.appcmd
#let ioapp = names.ioapp
#let iocmd = names.iocmd
#let lsapp = names.lsapp
#let lscmd = names.lscmd
#let pkgcmd = names.pkgcmd
#let pushapp = names.pushapp
#let pushcmd = names.pushcmd
#let org = names.org

// Content shown only for some products or features:
//   #only-for("rv", "openrv")[RV-only text]
//   #if-feature("stereo")[stereo text]
#let only-for(..prods, body) = if product in prods.pos() { body }
#let if-feature(name, body) = if name in names.features { body }

// Screenshots: the manuals load the compressed copies in docs/images-web,
// made from the originals in docs/images by ../compress-images.py (build
// with ./build-docs.sh, which sets the Typst root so they can be read).
#let image-dir = "../../images-web/"

// All screenshots share one pixel scale so a small menu and a big dialog look
// consistent. Sizes are in logical pixels (pixels adjusted for the file's DPI,
// so a 144 DPI Retina capture counts at half size):
//   PDF:  one logical pixel = image-scale pt; an image only shrinks further
//         when it is wider than image-max-width of its space (page, or
//         image-row cell)
//   HTML: one logical pixel = one CSS pixel (1:1 on screen); CSS max-width
//         shrinks it on narrow windows
// Passing width: or height: to img() overrides this for that image.
#let image-scale = 0.5
// Widest an image may be, as a fraction of the space it's in, so wide
// screenshots keep a margin (5% each side) instead of running text-width.
#let image-max-width = 0.9

#let img(name, ..args) = context {
    let path = image-dir + name
    let border(im) = if target() == "html" { im } else { box(stroke: 0.5pt + luma(200), im) }
    if "width" in args.named() or "height" in args.named() {
        border(image(path, ..args))
    } else {
        // natural size in pt is the logical pixel count
        let natural = measure(image(path)).width
        if target() == "html" {
            image(path, width: natural * 0.75, ..args)   // 0.75pt = 1 CSS px
        } else {
            layout(space => border(image(path,
                width: calc.min(natural * image-scale, space.width * image-max-width), ..args)))
        }
    }
}

// Images side by side, e.g. inside a figure:
//   #figure(image-row(img("a.png"), img("b.png")), caption: [...])
#let image-row(..imgs) = context {
    let n = imgs.pos().len()
    if target() == "html" {
        html.elem("div", attrs: (class: "image-row"), imgs.pos().join())
    } else {
        grid(columns: (1fr,) * n, gutter: 1em, align: center + bottom, ..imgs)
    }
}

// Reference to a label in another chapter. When the chapters are compiled
// together it becomes a real link; compiled alone it shows the fallback text.
//   #xref(<ch-luts>)[Chapter 8]
#let xref(target, fallback) = context {
    if query(target).len() > 0 { ref(target) } else { fallback }
}

#let key-font = "Fira Code"
#let menu-font = "Helvetica Neue"
#let shell-font = "Fira Code"

// One shaded block holding one or more lines of code, each on its own line:
//   #code-block("foo.0001.tif", "foo.0002.tif")
// Lines may also be a raw block, and lang can be changed (none = plain):
//   #code-block(lang: none, ```
//   Section "Monitor"
//   ```)
#let code-block(lang: "bash", ..lines) = {
    set text(font: shell-font)
    let text = lines.pos().map(l => if type(l) == content { l.text } else { l }).join("\n")
    let code = raw(text, block: true, lang: lang)
    context if target() == "html" {
        html.elem("div", attrs: (class: "shell"), code)
    } else {
        block(width: 100%, inset: 8pt, radius: 3pt, fill: luma(240), code)
    }
}

// Like code-block, with a "shell> bin" prompt on each command:
//   #shell("utv", "foo.mov", "-help")
// Lines starting with whitespace are continuations and get no prompt.
#let shell(bin, ..cmds) = code-block(..cmds.pos().map(cmd =>
    if cmd.starts-with(" ") { cmd } else { "shell> " + bin + " " + cmd }))
#let inline-shell(cmd) = {
    raw(cmd, lang: "bash")
}
#let appshell(..cmds) = shell(appcmd, ..cmds)
#let ioshell(..cmds) = shell(iocmd, ..cmds)
#let lsshell(..cmds) = shell(lscmd, ..cmds)
#let menu(parts) = context {
    let content = if type(parts) == array {parts.join("⭢")} else {parts}
    if target() == "html" {
        html.elem("span", attrs: (class: "menuitem"), content)
    } else {
        set text(font: menu-font, weight: "bold")
        content
    }
}
#let key(k) = context {
    if target() == "html" {
        html.elem("kbd", attrs: (class: "key"), k)
    } else {
        set text(font: key-font)
        box(width: auto,
            inset: 3pt,
            radius: 3pt,
            stroke: teal,
            fill: rgb(85%,85%,85%),
            k)
    }
}

// compact: true uses a smaller font, for long reference tables
#let key-table(compact: false, ..stuff) = context {
    if target() == "html" {
        html.elem("div", attrs: (class: if compact { "key-table compact" } else { "key-table" }),
            table(columns: 2, table.header[Key][Action], ..stuff))
    } else {
        set text(size: 0.85em) if compact
        table(columns: (auto, auto),
            align: left + horizon,
            inset: if compact { (x: 6pt, y: 2pt) } else { (x: 8pt, y: 5pt) },
            // no vertical rules; heavy rule under the header, light rule at the bottom
            stroke: (x, y) => (
                top: if y == 0 { 1pt + teal } else if y == 1 { 0.75pt + teal } else { none },
                bottom: 0.5pt + teal.lighten(40%),
            ),
            fill: (x, y) => if y == 0 { teal.lighten(80%) } else if calc.even(y) { luma(245) },
            table.header[*Key*][*Action*],
            ..stuff
        )
    }
}

// Master files: the title (a title page in the PDF, a heading block in HTML)
// and the page footer for the body:
//   #title-page[#app User Manual]
//   #outline(depth: 2)
//   #show: body-pages.with[#app User Manual]
#let title-page(title) = context {
    if target() == "html" {
        html.elem("header", attrs: (class: "doc-title"), {
            html.elem("h1", title)
            html.elem("p", attrs: (class: "doc-version"), [Version #version])
        })
    } else {
        set page(numbering: none)
        align(center + horizon, {
            text(size: 32pt, weight: "bold", title)
            v(1.2em)
            text(size: 14pt, fill: luma(90))[Version #version]
        })
        pagebreak()
    }
}
// PDF only (HTML has no pages): page numbers, and the manual and version in
// small type at the bottom of every page.
#let body-pages(title, body) = context if target() == "html" { body } else {
    set page(numbering: "1", footer: context {
        set text(size: 8pt, fill: luma(120))
        [#title, version #version]
        h(1fr)
        counter(page).display("1")
    })
    body
}

// Document template: every set/show rule lives here so it applies to the
// whole document (rules do not carry across #import).
//   chapter files:   #show: manual
//   appendix files:  #show: manual.with(appendix: true)   (A, A.1, ...)
//   the master file: #show: manual.with(master: true)
// Chapter files keep their own #show: manual so they still build alone.

// Set by the master file so included chapters don't repeat the stylesheet.
#let in-master = state("manual-in-master", false)

#let manual(appendix: false, master: false, body) = {
    set heading(numbering: if appendix { "A.1." } else { "1." })
    // @ref to a chapter reads "Chapter 4" / "Appendix B", not "Section 4"
    show heading.where(level: 1): set heading(
        supplement: if appendix [Appendix] else [Chapter])
    // each chapter starts a page and restarts figure/table numbering
    show heading.where(level: 1): it => {
        context if target() != "html" { pagebreak(weak: true) }
        counter(figure.where(kind: image)).update(0)
        counter(figure.where(kind: table)).update(0)
        it
    }
    // figures and tables are numbered per chapter: 4.2, B.1, ...
    set figure(numbering: n => numbering(
        if appendix { "A.1" } else { "1.1" },
        counter(heading).get().first(), n))
    show table: set align(center)
    // default table look: thin grey horizontal rules, shaded header row
    // (key-table and tables that set their own stroke/fill are unaffected)
    set table(
        stroke: (x, y) => (
            top: if y == 1 { 0.6pt + luma(150) } else { 0.4pt + luma(200) },
            bottom: 0.4pt + luma(200),
        ),
        fill: (x, y) => if y == 0 { luma(238) },
        inset: (x: 6pt, y: 4pt),
    )
    // breathing room around figures and their captions
    show figure: set block(above: 1.6em, below: 1.6em)
    show figure.caption: set text(size: 0.9em)
    // let long tables in figures split across pages
    show figure.where(kind: table): set block(breakable: true)
    // italicize Latin abbreviations always
    show "i.e.": emph[i.e.]
    show "e.g.": emph[e.g.]
    if master { in-master.update(true) }
    context if target() == "html" and (master or not in-master.get()) {
        html.elem("style", read("manual.css"))
        html.elem("script", read("manual.js"))
    }
    body
}
