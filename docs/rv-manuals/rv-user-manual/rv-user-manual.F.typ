#import "../common/manual-lib.typ": *
#show: manual.with(appendix: true)

= Troubleshooting Networking <app-networking>

== Configure #app's Network Settings

You can use the Network dialog under the #menu(app) menu to configure #app's
network syncing (as in between two or more instances of #app), set the name
you show up as in sync mode on other instances, and establish the port you
want to listen on for network connections. From this dialog you can initiate
a connection to another instance and manage your Contacts list (see
#xref(<ch-networking>)[Chapter 13]).

The Contacts tab gives a list of users you have established connections with
previously, but what is more important is the permission drop-down menu
immediately below the contacts list. This drop-down allows you to set the
default behavior for how to manage incoming connections. Once a user is added
to the contacts list, the permission can be set per contact. Lastly, the
Connections tab shows your active connections.

At the bottom are two important buttons: "Connect…" and "Start Network."
"Connect…" lets you type in another #app's network name and port. #app can
only connect by hostname or IP address. It is important that the #app
reaching out to connect can see the remote #app through any firewall. You
may have to set up port forwarding or some other DMZ configuration for this
to work. Please contact your network administrator for these types of
advanced setups.

Once you are satisfied with your settings, you can enable networking for
#app by pressing the "Start Network" button.

== Connections Only Work from One Direction or Are Always Refused

Some operating systems have a firewall on by default that may be blocking the
port #app is trying to use. When you start #app on the machine with the
firewall and start networking it appears to be functioning correctly, but no
one can connect to it. Check to see if the port that #app wants to use is
available through the firewall.

This is almost certainly the case when the connection works from one
direction but not the other. The side which can make the connection is
usually the one that has the firewall blocking #app (it won't let other
machines in).
