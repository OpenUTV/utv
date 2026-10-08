#import "../common/manual-lib.typ": *
#show: manual.with(appendix: true)

= Supported Multichannel Audio Layouts <app-multichannel-layouts>

Multichannel audio devices are supported by the #app audio output module
"Platform Audio". The "Platform Audio" choice is available on all #app
platforms i.e. macOS, Linux and Windows.

On macOS, you might need to enable the multichannel (e.g. 5.1) capability of
your audio device using the macOS utility "Audio MIDI Setup".

The list of possible channel layouts that #app recognizes is listed in
@multichannel-layouts. Speakers are abbreviated as follows:

#table(
    columns: 4,
    align: left,
    stroke: none,
    fill: none,
    `FL`, [Front Left], `BC`, [Back Center],
    `FR`, [Front Right], `SL`, [Side Left],
    `FC`, [Front Center], `SR`, [Side Right],
    `LF`, [Low Frequency (subwoofer)], `FLC`, [Front Left of Center],
    `BL`, [Back Left], `FRC`, [Front Right of Center],
    `BR`, [Back Right], `LH`, [Left Height],
    [], [], `RH`, [Right Height],
)

#figure(
    kind: table,
    table(
        columns: 2,
        align: left,
        table.header[*Channel Layout*][*Speaker Order*],
        [Mono], `FC`,
        [Stereo], `FL:FR`,
        [2.1], `FL:FR:LF`,
        [Quadrophonic], `FL:FR:BL:BR`,
        [4.1], `FL:FR:FC:LF:BC`,
        [4.1 (Swap)], `FL:FR:BL:BR:LF`,
        [5.1], `FL:FR:FC:LF:SL:SR`,
        [5.1 (Back)], `FL:FR:FC:LF:BL:BR`,
        [5.1 (Swap)], `FL:FR:BL:BR:FC:LF`,
        [5.1 (AC3)], `FL:FC:FR:SL:SR:LF`,
        [5.1 (DTS)], `FC:FL:FR:SL:SR:LF`,
        [5.1 (AIFF)], `FL:BL:FC:FR:BR:LF`,
        [6.1], `FL:FR:FC:LF:BL:BR:BC`,
        [7.1 (SDDS)], `FL:FR:FC:LF:SL:SR:FLC:FRC`,
        [7.1], `FL:FR:FC:LF:SL:SR:BL:BR`,
        [7.1 (Back)], `FL:FR:FC:LF:BL:BR:SL:SR`,
        [9.0 (Generic)], `FL:FR:FC:LF:BL:BR:SL:SR:BC`,
        [9.1], `FL:FR:FC:LF:BL:BR:SL:SR:LH:RH`,
        [11.0 -- 16.0 (Generic)], [Generic layouts with 11 to 16 channels],
    ),
    caption: [Supported Multichannel Layouts],
) <multichannel-layouts>

Note that #app will mix down, mix up or reorder channels for any given media
to match the intended output device channel layout format.

For example, playing back 5.1 media to a stereo audio device will see the 5.1
audio channels mixed down to two channels.

Similarly, playing back stereo media to a 5.1 device will see the media's
stereo FL and FR content mixed up to the 5.1 device's FL, FR and FC only.

For the case where the media and device have the same channel count and
speaker types but different layout e.g. for 5.1 media and a 5.1 (AC3)
device, the media's channel layout is reordered to match the device channel
layout when #app reads the media.

For the case where the media and device have the same channel count but
non-matching channel/speaker types, the channel layout of the media is passed
to the device as is; for example 5.1 (Back) media and a 5.1 device.

The audio channel layout for any given media can be determined from #app's
image info tool.
