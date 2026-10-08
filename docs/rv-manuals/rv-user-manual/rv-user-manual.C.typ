#import "../common/manual-lib.typ": *
#show: manual.with(appendix: true)

= The RVLINK Protocol: Using #app as a URL Handler <app-rvlink>

#app can act as a protocol handler for URLs using the "rvlink" protocol.
These URLs have the form:

#code-block(lang: none, "rvlink://<" + app + " command line>")

for example,

#code-block(lang: none, "rvlink:// -l -play /path/to/my/movie.mov")

Will start #app (or on the Mac, create a new session or replace the current
session), load `movie.mov`, turn on the look-ahead cache, and start playback.

== Using rvlink URLs

You can insert rvlinks into web pages, chat sessions, emails, etc. Of course
it is up to each individual application whether it recognizes the protocol.
Some applications can be taught to treat anything of the form `name://` as a
link to the _name_ protocol, but others are hard-coded to only recognize
`http://`, `ftp://`, etc. Some examples of apps that will recognize rvlinks
are:

- Firefox
- Safari
- Chrome
- Internet Explorer
- Thunderbird
- Mac Mail
- iChat

One example of an app that will only recognize a hard-coded set of protocol
types is Pidgin.

To use an rvlink in HTML, this kind of thing should work:

#code-block(lang: "html", "<a href=\"rvlink: -l -play /path/to/my/movie.mov\">play movie</a>")

*Note* the quotation marks.

In other settings (like pasting into an email, for example) you may want a
"web-encoded" URL, since #a-app command line can contain arbitrary
characters. #app will do the web-encoding for you, if you ask it to do so on
the command line. For example, if you run:

#appshell("-l -play /path/to/my/movie.mov -encodeURL")

#app will print the encoded URL to the terminal:

#code-block(lang: none, "rvlink://%20-l%20-play%20%2Fpath%2Fto%2Fmy%2Fmovie.mov")

Some browsers, however, like IE and Konqueror, seem to modify even encoded
URLs before they get to the protocol handler. If the rvlink URL contains
interesting characters, even an encoded URL will not work with these
browsers. To address this issue, #app also supports _fully-baked_ URLs, that
look like this:

#code-block(lang: none, "rvlink://baked/202d6c202d706c6179202f706174682f746f2f6d792f6d6f7669652e6d6f76")

This form of URL has the disadvantage of being totally illegible to humans,
but as a last resort, it should ensure that the URL reaches the protocol
handler without interference. As with encoded URLs, baked URLs can be
generated from command-lines by giving #app the #inline-shell("-bakeURL")
command-line option. Note that the "baked" URL is just a hex-encoded version
of the command line, so in addition to using #app itself, you can do it
programmatically. For example, in Python, something like

#code-block(lang: "python", "\" -play /path/to/file.exr\".encode().hex()")

should do the trick.

=== A Note on Spaces

In general, #app will treat spaces within the URL as delimiting arguments on
the command line. If you want to include an argument with spaces (a movie
name containing a space, for example) that argument must be enclosed in
single quotes ('). For example, if the name of your media is
`my movie.mov`, the encoded rvlink URL to play it would look like:

#code-block(lang: none, "rvlink://%20'my%20movie.mov'")

== Installing the Protocol Handler

#app itself is the program that handles the rvlink protocol, so all that is
necessary is to register #app as the designated rvlink handler with the OS
or desktop environment. This is a different process on each of the platforms
that #app supports.

=== Windows

On Windows the rvlink protocol needs to be added to the registry. If you are
using the #app installer for Windows this will happen automatically. If not,
you need to edit the `rvlink.reg` file in the `etc` directory of the install
to point at the install location, then just double click on this file to
edit the registry.

=== Mac

Run #app once with the #inline-shell("-registerHandler") command-line option
in order to register that executable as the default rvlink protocol handler
(this prevents confusion when more than one copy of #app is installed).

=== Linux

Unlike Windows and Mac, Linux protocols are registered at the desktop
environment level, not the OS level. After you've installed #app on your
machine, you can run the #inline-shell("rv.install_handler_linux") script in
the install's `bin` directory. This script will register #app with both the
KDE and Gnome desktop environments.

Some application-specific notes:

/ Firefox: may or may not respect the Gnome settings. In general, if there is
  enough of the Gnome environment installed that `gconfd` is running (even if
  you're using KDE or some other desktop environment), Firefox will pick up
  the Gnome settings. If you can't get this to work, you can register the
  rvlink protocol with Firefox directly.

/ Konqueror: sadly seems to munge URLs before giving them to the protocol
  handler. For example by swapping upper for lowercase letters. And
  sometimes it does not pass them on at all. This means some rvlink URLs
  will work and some won't, so we recommend only "baked" rvlink URLs with
  Konqueror at the moment.

/ Chrome: uses the underlying system defaults to handle protocols. In most
  cases this means whatever #inline-shell("xdg-open") is configured to use.
  Running #inline-shell("rv.install_handler_linux") should be sufficient.

== Custom Environment Variables

Depending on the browser and desktop environment, *environment variables*
set in a user environment may not be available to #app when started from a
URL. If #app in your setup requires these environment variables
(`RV_SUPPORT_PATH`, for example), it may have problems or not run at all
when started from a URL. In order to ensure a consistent environment, you
must ensure that these environment variables are set at a system-wide (or at
least user-independent) level. On Linux, setting this up varies from
distribution to distribution. You will want to research the appropriate
steps for your distribution. On Windows, the usual environment variable
techniques should work. macOS has lately made this harder, but if you set
the environment variables in `/etc/launchd.conf` (and reboot after setting),
then the values should be picked up by all processes on the system.

== Testing the Protocol Handler

Once #app is properly configured as your `rvlink:` protocol handler, copy
and paste the following URL into your browser window:
`rvlink://smptebars.movieproc`. This should launch #app and display a
standard SMPTE colorbar image.

You can also test #app's "one-click sync" with these links (*only* on Linux
and Windows).

- First copy and paste the following link into your browser to start your
  "sync target" #app (make sure no other #app instances are running before
  you paste this link into your browser):
  `rvlink:// -reuse 0 -networkPort 45128 -network smptebars,start=1,end=100,fps=24.movieproc`.
- Then copy and paste the following link into your browser to sync with the
  previously started sync target:
  `rvlink:// -networkPort 45129 -network -networkConnect 127.0.0.1 45128 -flags syncPullFirst`.

Here's an example of a "fully baked" URL, which is much more resistant to
munging by browsers:
`rvlink://baked/20736d707465626172732e6d6f76696570726f63202d6576616c20277072696e74282532326e6f2070726f626c656d2535436e253232293b27`.

== One-Click Sync

The rvlink protocol allows you to build URLs that start and run #app. You
can also set up a network connection to a remote #app from the command line
and hence from an rvlink URL. Furthermore, you can direct that after the
network connection is established, Sync should be activated, and the remote
session information should be pulled over the network so that you'll both be
looking at the same media.

To create such a link, use #menu(("Edit", "Copy Sync Session URL")). It
copies the link to the clipboard so you can share it with others.

Imagine this scenario: You're using #app, have some media loaded, when you
decide you want your friend to look at it with you. They're in the next
building, so rather than walk over there you want to start #a-app Sync
session with them.

To get connected, you can send them by email the URL from *Copy Sync Session
URL*.

So they can click the link, or copy and paste it in a browser, to open the
linked session in #app. When they click on this link, #app will start on
their machine, connect to your running #app, pull the session information
(so your media will match), and start Sync. So there you have it: One-Click
Sync!
