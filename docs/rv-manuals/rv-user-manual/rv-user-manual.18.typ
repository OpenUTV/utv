#import "../common/manual-lib.typ": *
#show: manual

= #pushapp <ch-rvpush>

The #pushapp command-line utility allows you to communicate with a running
#app (you can designate a "target" #app with the #inline-shell("-tag")
option). The help output from the command is as follows:

#let p = pushcmd
#code-block(lang: none,
    "usage: " + p + " [-tag <tag>] <command> <commandArgs>",
    "       " + p + " set <mediaArgs>",
    "       " + p + " merge <mediaArgs>",
    "       " + p + " mu-eval <mu>",
    "       " + p + " mu-eval-return <mu>",
    "       " + p + " py-eval <python>",
    "       " + p + " py-eval-return <python>",
    "       " + p + " py-exec <python>",
    "       " + p + " url rvlink://<rv-command-line>",
    "",
    "       Examples:",
    "",
    "       To set the media contents of the currently running " + app + ":",
    "           " + p + " set [ foo.mov -in 101 -out 120 ]",
    "",
    "       To add to the media contents of the currently running " + app + " with tag \"myrv\":",
    "           " + p + " -tag myrv merge [ fooLeft.mov fooRight.mov ]",
    "",
    "       To execute arbitrary Mu code in the currently running " + app + ":",
    "           " + p + " mu-eval 'play()'",
    "",
    "       To execute arbitrary Mu code in the currently running " + app + ", and print the result:",
    "           " + p + " mu-eval-return 'frame()'",
    "",
    "       To evaluate an arbitrary Python expression in the currently running " + app + ":",
    "           " + p + " py-eval 'rv.commands.play()'",
    "",
    "       To evaluate an arbitrary Python expression in the currently running " + app + ", and print the result:",
    "           " + p + " py-eval-return 'rv.commands.frame()'",
    "",
    "       To execute arbitrary Python statements in the currently running " + app + ":",
    "           " + p + " py-exec 'from rv import commands; commands.play()'",
    "",
    "       To process an rvlink url in the currently running " + app + ", loading a movie into the current session:",
    "           " + p + " url 'rvlink:// -reuse 1 foo.mov'",
    "",
    "       To process an rvlink url in the currently running " + app + ", loading a movie into a new session:",
    "           " + p + " url 'rvlink:// -reuse 0 foo.mov'",
    "",
    "       Set environment variable RVPUSH_RV_EXECUTABLE_PATH if you want " + p + " to",
    "       start something other than the default " + app + " when it cannot find a running",
    "       " + app + ".  Set to 'none' if you want no " + app + " to be started.",
    "",
    "       Exit status:",
    "           4: Connection to running " + app + " failed",
    "          11: Could not connect to running " + app + ", and could not start new " + app,
    "          15: Could not connect to running " + app + ", started new one.",
)

Any number of media sources and associated per-source options can be
specified for the `set` and `merge` commands. For the `mu-eval` command, it's
probably best to put all your Mu code in a single quoted string.

If #pushapp cannot find a running #app to talk to, it'll start one with the
appropriate command-line options. Any later #raw(pushcmd) commands will use
this #app until it exits. Note that the #app that #pushapp starts will by
default be the one in the same `bin` directory. If you'd rather start a
different #app, or start a wrapper, etc, you can set the environment variable
`RVPUSH_RV_EXECUTABLE_PATH` to point to the one you'd prefer. If you want
#pushapp to never start #app, you can set this environment variable to
"none".
