// Pandoc version of the helpers in a manual's manual-lib.typ.
//
// build-rtd.sh prepends the `products` table taken from the real
// manual-lib.typ, fills in PRODUCT_PLACEHOLDER and VERSION_PLACEHOLDER, and
// uses the result in place of manual-lib.typ when running `pandoc -f typst`.
//
// Same names and arguments as manual-lib.typ, but plain implementations:
// Pandoc's Typst reader has no context, target(), html.elem, measure,
// layout, state, query or sys.inputs. Things Sphinx needs to see (keys,
// menus, cross-chapter refs) are passed as links with fake schemes that
// sphinx-roles.lua turns into RST roles.
//
// Keep this in step with manual-lib.typ: every helper a chapter can use must
// exist here too.

#let product = "PRODUCT_PLACEHOLDER"
#let version = "VERSION_PLACEHOLDER"
#let names = products.at(product)
#let app = names.app
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
#let only-for(..prods, body) = if product in prods.pos() { body }
#let if-feature(name, body) = if name in names.features { body }

// Image sizing (the shared pixel scale) is done in sphinx-roles.lua.
#let image-dir = "../../images-web/"
#let img(name, ..args) = image(image-dir + name)
#let image-row(..imgs) = imgs.pos().join()

// Cross-chapter labels are unknown when converting one chapter at a time,
// so pass the label through as a link the filter turns into :ref:.
#let xref(target, fallback) = link("ref:" + str(target))[#fallback]

#let code-block(lang: "bash", ..lines) = {
    let text = lines.pos().map(l => if type(l) == content { l.text } else { l }).join("\n")
    raw(text, block: true, lang: lang)
}
#let shell(bin, ..cmds) = code-block(..cmds.pos().map(cmd =>
    if cmd.starts-with(" ") { cmd } else { "shell> " + bin + " " + cmd }))
#let inline-shell(cmd) = raw(cmd)
#let appshell(..cmds) = shell(appcmd, ..cmds)
#let ioshell(..cmds) = shell(iocmd, ..cmds)
#let lsshell(..cmds) = shell(lscmd, ..cmds)

// Pandoc drops raw() language tags, so keys and menus are marked as links
// with fake schemes; the filter turns them into :kbd: / :menuselection:.
#let menu(parts) = {
    let t = if type(parts) == array { parts.join(" --> ") } else { parts }
    link("menu:" + t)[#t]
}
#let key(k) = link("kbd:" + k)[#k]
#let key-table(compact: false, ..stuff) = table(columns: 2, table.header[Key][Action], ..stuff)

#let manual(appendix: false, master: false, body) = body
