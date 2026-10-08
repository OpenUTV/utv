"""Sphinx extension for the Typst manuals (copied next to conf.py by
build-rtd.sh).

- ``multi-figure``: a numbered figure holding several images side by side.
  The content is the images followed by a paragraph that becomes the
  caption; sphinx-roles.lua writes it for Typst ``image-row`` figures.
- Numbering as in the Typst output: each chapter or appendix file numbers its
  own figures and tables (2.1, 2.2, ... / A.1, ...), and appendix files, which
  are under their own numbered toctree, get letters instead of numbers.
"""

import re

from docutils import nodes
from sphinx.util.docutils import SphinxDirective

APPENDIX_DOC = re.compile(r"\.[A-Z]$")


class MultiFigure(SphinxDirective):
    has_content = True

    def run(self):
        figure = nodes.figure(classes=["image-row"])
        self.state.nested_parse(self.content, self.content_offset, figure)
        last = figure.children[-1] if figure.children else None
        if isinstance(last, nodes.paragraph):
            figure.remove(last)
            figure += nodes.caption(last.rawsource, "", *last.children)
        return [figure]


def letter(n):
    return chr(ord("A") + n - 1)


def renumber(app, env):
    """Runs after Sphinx's own numbering (env-get-updated, priority 900)."""
    # Appendix section numbers: first part 1, 2, ... -> A, B, ...
    for doc, secnums in env.toc_secnumbers.items():
        if not APPENDIX_DOC.search(doc):
            continue
        for anchor, num in secnums.items():
            if num and isinstance(num[0], int):
                secnums[anchor] = (letter(num[0]),) + tuple(num[1:])
        # the copies Sphinx keeps for the sidebar and prev/next links
        for ref in env.tocs[doc].findall(nodes.reference):
            num = ref.get("secnumber")
            if num and isinstance(num[0], int):
                ref["secnumber"] = [letter(num[0])] + list(num[1:])
        title = env.titles.get(doc)
        num = title.get("secnumber") if title is not None else None
        if num and isinstance(num[0], int):
            title["secnumber"] = [letter(num[0])] + list(num[1:])

    # Figure/table numbers: Sphinx keeps one counter per chapter number
    # across the whole site, so the reference manual's chapter 2 carries on
    # from the user manual's. Restart them in every file, in document order.
    for doc, figtypes in env.toc_fignumbers.items():
        chapter = env.toc_secnumbers.get(doc, {}).get("")
        if not chapter:
            continue
        for numbers in figtypes.values():
            for i, fig_id in enumerate(numbers, 1):
                numbers[fig_id] = (chapter[0], i)

    return list(env.toc_fignumbers)


def setup(app):
    app.add_directive("multi-figure", MultiFigure)
    app.connect("env-get-updated", renumber, priority=900)
    return {"parallel_read_safe": True, "parallel_write_safe": True}
