// The complete user manual. Build it with ./build-docs.sh (see -h), which
// holds the typst command-line details. Each chapter file can still be built
// on its own (./build-docs.sh -c 07).

#import "../common/manual-lib.typ": *
#show: manual.with(master: true)

#set document(title: app + " User Manual " + version)

#title-page[#app User Manual]

#outline(depth: 2)

#show: body-pages.with[#app User Manual]

#include "rv-user-manual.01.typ"
#include "rv-user-manual.02.typ"
#include "rv-user-manual.03.typ"
#include "rv-user-manual.04.typ"
#include "rv-user-manual.05.typ"
#include "rv-user-manual.06.typ"
#include "rv-user-manual.07.typ"
#include "rv-user-manual.08.typ"
#include "rv-user-manual.09.typ"
#include "rv-user-manual.10.typ"
#include "rv-user-manual.11.typ"
#include "rv-user-manual.12.typ"
#include "rv-user-manual.13.typ"
#include "rv-user-manual.14.typ"
#include "rv-user-manual.15.typ"
#include "rv-user-manual.16.typ"
#include "rv-user-manual.17.typ"
#include "rv-user-manual.18.typ"

// Appendices restart the heading counter so the first one is "A".
#counter(heading).update(0)

#include "rv-user-manual.A.typ"
#include "rv-user-manual.B.typ"
#include "rv-user-manual.C.typ"
#include "rv-user-manual.D.typ"
#include "rv-user-manual.E.typ"
#include "rv-user-manual.F.typ"
#include "rv-user-manual.G.typ"
#include "rv-user-manual.H.typ"
#include "rv-user-manual.I.typ"
#include "rv-user-manual.J.typ"
