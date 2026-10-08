#import "../common/manual-lib.typ": *
#show: manual.with(appendix: true)

= Tuning Platform Audio for Linux <app-tuning-audio>

On Linux, #app's Platform Audio module is based on Qt's `QAudioOutput`,
which is implemented against ALSA's API. As such, we have added several
environment variables that allow us to better debug audio issues and which
also allow users to tune the audio data I/O performance between #app and
their chosen playback audio hardware device. Note these environment
variables are only supported on Linux.

The environment variables are as follows:

#figure(
    kind: table,
    table(
        columns: (auto, 1fr),
        align: left,
        table.header[*Environment Variable*][*Variable values*],
        `TWK_QTAUDIOOUTPUT_ENABLE_DEBUG`, [
            0 = No debugging messages (default) \
            1 = Standard debugging messages; displays the ALSA device hardware
            parameter values used to configure the audio device. It will also
            display errors like buffer underruns. \
            2 = Verbose debugging messages; use this value for tracing
            crashes. Messages are displayed with each audio period write to
            the ALSA audio device.],
        `TWK_QTAUDIOOUTPUT_BUFFER_TIME`, [value in microseconds e.g. 120000
            for 120 ms (default is 120000)],
        `TWK_QTAUDIOOUTPUT_PERIOD_TIME`, [value in microseconds e.g. 20000 for
            20 ms (default is 20000)],
    ),
    caption: [Platform Audio Environment Variables],
) <platform-audio-env>

#code-block(lang: none,
    "shell> setenv TWK_QTAUDIOOUTPUT_ENABLE_DEBUG 1",
    "shell> setenv RV_NO_CONSOLE_REDIRECT 1",
    "shell> " + appcmd + " myclip.mov",
    "",
    "INFO: myclip.mov",
    "DEBUG: Number of available audio devices  3",
    "DEBUG: Audio device =  \"default\"",
    "DEBUG: Audio device actual =  \"pulse\"",
    "DEBUG: ranges: pmin= 666 , pmax= 7281792 , bmin= 2000 , bmax= 21845334",
    "DEBUG: used: buffer_frames= 5760 , period_frames= 960     # in sample count",
    "DEBUG: used: buffer_size= 23040 , period_size= 3840       # in bytes",
    "DEBUG: used: buffer_time= 120000 , period_time= 20000     # in microsecs",
    "DEBUG: used: chunks= 6                                    # no of periods per buffer",
    "DEBUG: used: max write periods/chunks=0                   # 0 implies max possible.",
    "DEBUG: used: bytesAvailable= 23040                        # amount of free space in the audio buffer on device open().",
)

The environment variables `TWK_QTAUDIOOUTPUT_BUFFER_TIME` and
`TWK_QTAUDIOOUTPUT_PERIOD_TIME` can be used to set the buffer size and period
size of the audio device. The audio buffer size is always an integral number
of period sizes, in other words choose values such that
$"BUFFER_TIME" = N times "PERIOD_TIME"$, where $N$ is an integer.
Experimentally we have found $N = 6$ produced a measured audio-video sync
$< 10$ ms; while increasing or decreasing $N$ from this value seemed to
produce larger and increasingly worse AV sync lag numbers.

It is worth remembering that `TWK_QTAUDIOOUTPUT_BUFFER_TIME` determines the
overall size of the audio buffer. The audio device will not start playing
until the buffer is completely filled first. This means the buffer size can
influence the lag at the beginning when play first starts.

So for a given `TWK_QTAUDIOOUTPUT_BUFFER_TIME`,
`TWK_QTAUDIOOUTPUT_PERIOD_TIME` determines the number of period buffers
within the overall buffer size; this influences the average AV sync value
and if too small ($<= 3$) leads to buffer underrun errors and crackles in the
audio.

#code-block(lang: none,
    "shell> setenv TWK_QTAUDIOOUTPUT_ENABLE_DEBUG 1",
    "shell> setenv RV_NO_CONSOLE_REDIRECT 1",
    "shell> setenv TWK_QTAUDIOOUTPUT_BUFFER_TIME 60000",
    "shell> setenv TWK_QTAUDIOOUTPUT_PERIOD_TIME 20000",
    "shell> " + appcmd + " myclip.mov",
    "",
    "INFO: myclip.mov",
    "DEBUG: Number of available audio devices  3",
    "DEBUG: Audio device =  \"default\"",
    "DEBUG: Audio device actual =  \"pulse\"",
    "DEBUG: ranges: pmin= 666 , pmax= 7281792 , bmin= 2000 , bmax= 21845334",
    "DEBUG: used: buffer_frames= 2880 , period_frames= 960     # in sample count",
    "DEBUG: used: buffer_size= 11520 , period_size= 3840       # in bytes",
    "DEBUG: used: buffer_time= 60000 , period_time= 20000      # in microsecs",
    "DEBUG: used: chunks= 3                                    # no of periods per buffer",
    "DEBUG: used: max write periods/chunks=0                   # 0 implies max possible.",
    "DEBUG: used: bytesAvailable= 11520                        # amount of free space in the audio buffer on device open().",
    "DEBUG: *** Buffer underrun: -32",
    "DEBUG: *** Buffer underrun: -32",
    "DEBUG: *** Buffer underrun: -32",
    "DEBUG: *** Buffer underrun: -32",
    "DEBUG: *** Buffer underrun: -32",
)

The tuning process steps:

+ Launch #app and set up the #menu(("Preferences", "Audio")) tab settings as
  follows:
  + Output Module: Platform Audio
  + Output Device: Default
  + Output Format: Stereo 32bit float 48000
  + Enable 'Keep Audio device open when playing'
  + Turn off 'Hardware Audio/Video Synchronization'
  + Enable 'Scrubbing on by default'
+ Determine the smallest `TWK_QTAUDIOOUTPUT_BUFFER_TIME` and
  `TWK_QTAUDIOOUTPUT_PERIOD_TIME` settings before buffer underruns occur.
  + Set Platform Audio debugging messages on:
    `TWK_QTAUDIOOUTPUT_ENABLE_DEBUG = 1`.
  + Set values for `TWK_QTAUDIOOUTPUT_BUFFER_TIME` and
    `TWK_QTAUDIOOUTPUT_PERIOD_TIME`.
  + Try the following combinations of buffer time / period time: 60000 /
    10000 and 36000 / 6000.
  + Launch #app with a 48 kHz video clip and enable lookahead/region
    caching. Either cache option would do as long as you size the video
    cache appropriately so the entire clip is cached. Play back and watch for
    buffer underrun messages. Note you should also stress test running
    multiple #app instances with the same config.
  + If no underrun errors occur, repeat the previous step, setting smaller
    values for `TWK_QTAUDIOOUTPUT_BUFFER_TIME` and
    `TWK_QTAUDIOOUTPUT_PERIOD_TIME` keeping in mind that the ratio of buffer
    time to period time must be greater than 3 and ideally around 6.
+ Once you have found the smallest value of `TWK_QTAUDIOOUTPUT_BUFFER_TIME`,
  use an AV sync meter to measure the average AV sync lag playing back
  #app's movieproc syncflash clip.
  + With `TWK_QTAUDIOOUTPUT_BUFFER_TIME` fixed to the value determined in
    the previous step, increase and decrease `TWK_QTAUDIOOUTPUT_PERIOD_TIME`,
    bearing in mind `TWK_QTAUDIOOUTPUT_BUFFER_TIME` must be an integer
    multiple of `TWK_QTAUDIOOUTPUT_PERIOD_TIME`. Find the multiple with the
    lowest measured average AV sync values (i.e. the average of at least 25
    AV sync measurements).

@tuned-audio-configs provides the smallest values of
`TWK_QTAUDIOOUTPUT_BUFFER_TIME` and `TWK_QTAUDIOOUTPUT_PERIOD_TIME` that
prevent buffer underruns (i.e. audio corruption/static issues), and minimize
the lag at play-start and average AV sync. Note the default value for buffer
time is 120000 and period time is 20000.

#figure(
    kind: table,
    table(
        columns: 6,
        align: left,
        table.header[*Hardware class*][*Audio Hardware*][*OS / Machine Specs*][*BUFFER_TIME*][*PERIOD_TIME*][*Avg AV sync*],
        [Gaming machine], [onboard Intel HDA/Realtek 7.1ch], [CentOS 7.2, Asus Rampage Gene IV, Core i7 3.5 GHz, 32 GB 2400 MHz RAM, SSD, Quadro K2200 (nv drv 352.55)], [36000], [6000], [\~3 ms],
        [HP workstation], [onboard Intel HDA/Realtek 2ch], [CentOS 6.6, HP Z820, Xeon 12 core, 48 GB RAM, SSD, Quadro K6000 (nv 352.63)], [TBD], [TBD], [TBD],
        [Dell workstation], [onboard Intel HDA/Realtek 2ch], [CentOS 7.2], [TBD], [TBD], [TBD],
        [Any], [USB Soundblaster XiFi], [CentOS 7.2, Asus Rampage Gene IV, Core i7 3.5 GHz, 32 GB 2400 MHz RAM, SSD, Quadro K2200 (nv drv 352.55)], [120000], [20000], [TBD],
    ),
    caption: [Some tuned configurations for 24 fps on a 60 Hz monitor],
) <tuned-audio-configs>

== Suggestions for Resolving Audio Static Issues with PulseAudio for Linux

In this section, we outline some suggestions for configuring your Linux
distribution's PulseAudio to address the issue of audio static during
playback when #app sees heavy and continuous use within the context of a
production environment. While this issue is intermittent and hard to
reproduce, it can occur with sufficient frequency to become a support
burden. Please note the suggestions here should be validated by your
systems/video engineering department before you adopt them.

Settings for `/etc/pulse/default.pa`:

#code-block(lang: none, ```
# For RHEL7 equivalent systems
#
# fragments=2 (prevents problems on kvm and teradici host)
# fixed_latency_range=1 (fixes static problem when system is heavily loaded or in swap)
#
load-module module-alsa-card device_id=PCH format=s16le rate=48000 fragments=2 fixed_latency_range=1
```)

Many thanks to Jay Hillard and Chris Mihaly at WDAS for sharing these
settings with us.
