// The complete reference manual. Build it with ../build-docs.sh -m reference
// (see -h), which holds the typst command-line details. Each chapter file can
// still be built on its own (../build-docs.sh -m reference -c 07).

#import "../common/manual-lib.typ": *
#show: manual.with(master: true)

#set document(title: app + " Reference Manual " + version)

#title-page[#app Reference Manual]

#outline(depth: 2)

#show: body-pages.with[#app Reference Manual]

#include "rv-reference-manual.01.typ"
#include "rv-reference-manual.02.typ"
#include "rv-reference-manual.03.typ"
#include "rv-reference-manual.04.typ"
#include "rv-reference-manual.05.typ"
#include "rv-reference-manual.06.typ"
#include "rv-reference-manual.07.typ"
#include "rv-reference-manual.08.typ"
#include "rv-reference-manual.09.typ"
#include "rv-reference-manual.10.typ"
#include "rv-reference-manual.11.typ"
#include "rv-reference-manual.12.typ"
#include "rv-reference-manual.13.typ"
#include "rv-reference-manual.14.typ"
#include "rv-reference-manual.15.typ"
#include "rv-reference-manual.16.typ"
#include "rv-reference-manual.17.typ"
