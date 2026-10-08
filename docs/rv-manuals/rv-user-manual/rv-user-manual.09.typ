#import "../common/manual-lib.typ": *
#show: manual

= Using CDLs in #app <ch-cdls>

As discussed previously there are two default places to set ASC CDL
properties in the #app node graph. One is as a file CDL on the
`RVLinearize` node in the `RVLinearizePipelineGroup` and the other is as a
look CDL on the `RVColor` node in the `RVLookPipelineGroup`. In the case of
the `RVLinearize` node the CDL is applied before linearization occurs
whereas in the case of the `RVColor` node the CDL is applied after
linearization and linear color changes.

*To assign a CDL file to the source:* use the #menu(("File", "Import")) menu
to assign CDL files to either the source's Look or File pipelines.

== CDL File Formats

The types of files #app supports right now are Color Decision List
(#inline-shell(".cdl")), Color Correction (#inline-shell(".cc")) and Color
Correction Collection (#inline-shell(".ccc")) files. Color Correction
Collection files can include multiple Color Corrections tagged by ids. We do
not support reading the properties by id. Therefore the first Color
Correction found in the file will be read and used.
