#import "../common/manual-lib.typ": *
#show: manual

= Network Communication <ref-ch-network>

#app can communicate with multiple external programs via its network
protocol. The mechanism is designed to function like a “chat” client. Once a
connection is established, messages can be sent and received including
arbitrary binary data.

There are a number of applications which this enables:

- *Controlling #app remotely.* E.g., a program which takes input from a dial
  and button board or a mobile device and converts the input into commands
  to start/stop playback or scrubbing in #app\.
- *Synchronizing #app sessions across a network*. This is how #app's sync
  mode is implemented: each #app serves as a controller for the other.
- *Monitoring a Running #app*. For VFX theater dailies the #app session
  driving the dailies could be monitored by an external program. This
  program could then indicate to others in the facility when their shots are
  coming up.
- *A Display Driver for a Renderer*. Renderers like Pixar's RenderMan have a
  plug-in called a display driver which is normally used to write out
  rendered frames as files. Frequently this type of plug-in is also used to
  send pixels to an external frame buffer (like #app) to monitor the
  renderer's progress in real time. It's possible to write a display driver
  that talks to #app using the network protocol and send it pixels as they
  are rendered. A more advanced version might receive feedback from #app
  (e.g. a selected rectangle on the image) in order to recommend areas the
  renderer should render sooner.

Any number of network connections can be established simultaneously, so for
example it's possible to have a synchronized #app session with a remote #app
and drive it with an external hardware device at the same time.

== Example Code

There are two working examples that come with #app: the rvshell program and
the `rvNetwork.py` Python module. The rvshell program uses a C++ library
included with the distribution called TwkQtChat which you can use to make
interfacing easier — especially if your program will use Qt. We highly
recommend using this library since this is code which #app uses internally
so it will always be up-to-date. The library is only dependent on the QtCore
and QtNetwork modules.

The `rvNetwork.py` module
(in the `network` Python package that ships with #app) implements the
network protocol using only native Python code. You can use it directly in
python programs.

=== Using rvshell

To use rvshell, start #app from the command line with the network started
and a default port of 45000
(to make sure it doesn't interfere with existing #app sessions):

#appshell("-network -networkPort 45000")

Next start the rvshell program from a different shell:

#code-block(lang: "bash", ```
shell> rvshell user localhost 45000
```)

Assuming all went well, this will start rvshell connected to the running
#app\. There are three things you can experiment with using rvshell: a very
simple controller interface, a script editor to send portions of script or
messages to #app manually, and a display driver simulator that sends stereo
frames to #app\.Start by loading a sequence of images or a quicktime movie
into #app\. In rvshell switch to the “Playback Control” tab. You should be
able to play, stop, change frames and toggle full screen mode using the
buttons on the interface. This example sends simple Mu commands to #app to
control it. The feedback section of the interface shows the RETURN message
send back from #app\. This shows whatever result was obtained from the
command.

The “Raw Event” section of the interface lets you assemble event messages to
send to #app manually. The default event message type is remote-eval which
will cause the message data to be treated like a Mu script to execute. There
is also a remote-pyeval event which does the same with Python
(in which case you should type in Python code instead of Mu code). Messages
sent this way to #app are translated into UI events. In order for the
interface code to respond to the event something must have bound a function
to the event type. By default #app can handle remote-eval and remote-pyeval
events, but you can add new ones yourself.

When #app receives a remote-eval event it executes the code and looks for a
return value. If a return value exists, it converts it to a string and sends
it back. So using remote-eval it's possible to query #app's current state.
For example if you load an image into #app and then send it the command
renderedImages() it will return a Mu struct as a string with information
about the rendered image. Similarily, sending a remote-pyeval with the same
command will return a Python dictionary as a string with the same
information.

The last tab “Pixels” can be used to emulate a display driver. Load a JPEG
image into rvshell's viewer
(don't try something over 2k — rvshell is using Qt's image reader). Set the
number of tiles you want to send in X and Y, for example 10 in each. In #app
clear the session. In rvshell hit the Send Image button. rvshell will create
a new stereo image source in #app and send the image one tile at a time to
it. The left eye will be the original image and the right eye will be its
inverse. Try View → Stereo → Side by Side to see the results.

=== Using rvNetwork.py

This section has not been written yet. See the source of `rvNetwork.py` in
the `network` Python package, which implements the protocol described below
in pure Python.

== TwkQtChat Library

The TwkQtChat library is composed of three classes: Client, Connection, and
Server.

#figure(
    kind: table,
    table(
        columns: (auto, 1fr),
        align: left,
        table.header[*Function*][*Description*],
        [sendMessage], [Generic method to send a standard UTF-8 text message to a specific contact],
        [sendData], [Generic method to send a data message to a specific contact],
        [broadcastMessage], [Send a standard UTF-8 message to all contacts],
        [sendEvent], [Send an EVENT or RETURNEVENT message to a contact (calls sendMessage)],
        [broadcastEvent], [Send an EVENT or RETURNEVENT message to all contacts],
        [connectTo], [Initiate a connection to a specific contact],
        [hasConnection], [Query connection status to a contact],
        [disconnectFrom], [Force the shutdown of connection],
        [waitForMessage], [Block until a message is received from a specific contact],
        [waitForSend], [Block until a message is actually sent],
        [signOff], [Send a DISCONNECT message to a contact to shutdown gracefully],
        [online], [Returns true if the Server is running and listening on the port],
    ),
    caption: [Important Client Member Functions],
) <ref-important-client-member-functions>

#figure(
    kind: table,
    table(
        columns: (auto, 1fr),
        align: left,
        table.header[*Signal*][*Description*],
        [newMessage], [A new message has been received on an existing connection],
        [newData], [A new data message has been received on an existing connection],
        [newContact], [A new contact (and associated connection) has been established],
        [contactLeft], [A previously established connection has been shutdown],
        [requestConnection], [A remote program is requesting a connection],
        [connectionFailed], [An attempted connection failed],
        [contactError], [An error occurred on an existing connection],
    ),
    caption: [Client Signals],
)

A single Client instance is required to represent your process and to manage
the Connections and Server instances. The Connection and Server classes are
derived from the Qt QTcpSocket and QTcpServer classes which do the lower
level work. Once the Client instance exists you can get pointer to the
Server and existing Connections to directly manipulate them or connect their
signals to slots in other QObject derived classes if needed.

The application should start by creating a Client instance with its contact
name (usually a user name), application name, and port on which to create
the server. The Client class uses standard Qt signals and slots to
communicate with other code. It's not necessary to inherit from it.

The most important functions on the Client class are listed in
@ref-important-client-member-functions.

== The Protocol

There are two types of messages that #app can receive and send over its
network socket: a standard message and a data message. Data messages can
send arbitrary binary data while standard messages are used to send UTF-8
string data.

The greeting is used only once on initial contact. The standard message is
used in most cases. The data message is used primarily to send binary files
or blocks of pixels to/from #app\.

=== Standard Messages

#app recognizes these types of standard messages:

#figure(
    kind: table,
    table(
        columns: (auto, 1fr),
        align: left,
        table.header[*Type*][*Description*],
        [MESSAGE], [The string payload is subdivided into multiple parts the first of which indicates the sub-type of the message. The rest of the message is interpreted according to its sub-type.],
        [GREETING], [Sent by #app to a synced #app when negotiating the initial contact.],
        [NEWGREETING], [Sent by external controlling programs to #app during initial contact.],
        [PINGPONGCONTROL], [Used to negotiate whether or not #app and the connected process should exchange PING and PONG messages on a regular basis.],
        [PING], [Query the state of the other end of the connection — i.e. check and see if the other process is still alive and functioning.],
        [PONG], [Returned when a PING message is received to indicate state.],
    ),
    caption: [Message Types],
)

When an application first connects to #app over its TCP port, a greeting
message is exchanged. This consists of an UTF-8 byte string composed of:

#figure(
    kind: table,
    table(
        columns: (3fr, 1fr),
        align: left,
        table.header[*Content*][*Size*],
        [The string “NEWGREETING”], [1st word],
        [The UTF-8 value 32 (space)], [-],
        [A UTF-8 integer composed of the characters \[0-9\] with the value *N* + *M* + 1 indicating the number of bytes remaining in the message], [2nd word],
        [The UTF-8 value 32 (space)], [-],
        [Contact name UTF-8 string (non-whitespace)], [*N* bytes],
        [The UTF-8 value 32 (space)], [1 byte],
        [Application name UTF-8 string (non-whitespace)], [*M* bytes],
    ),
    caption: [Greeting Message],
)

In response, the application should receive a NEWGREETING message back. At
this point the application will be connected to #app.

A standard message is a single UTF-8 string which has the form:

#figure(
    kind: table,
    table(
        columns: (3fr, 1fr),
        align: left,
        table.header[*Content*][*Size*],
        [The string “MESSAGE”], [1st word],
        [The UTF-8 value 32 (space)], [-],
        [A UTF-8 integer composed of the characters \[0-9\] the value of which is *N* indicating the size of the remaining message], [2nd word],
        [The UTF-8 value 32 (space)], [-],
        [The message payload (remaining UTF-8 string)], [*N* bytes],
    ),
    caption: [Standard Message],
)

When #app receives a standard message (MESSAGE type) it will assume the
payload is a UTF-8 string and try to interpret it. The first word of the
string is considered the sub-message type and is used to decide how to
respond:

#figure(
    kind: table,
    table(
        columns: (auto, 1fr),
        align: left,
        table.header[*Sub-type*][*Description*],
        [EVENT], [Send the rest of the payload as a UI event (see below)],
        [RETURNEVENT], [Same as EVENT but will result in a response RETURN message],
        [RETURN], [The message is a response to a recently received RETURNEVENT message],
        [DISCONNECT], [The connection should be disconnected],
    ),
    caption: [Sub-Message Types],
)

The EVENT and RETURNEVENT messages are the most common. When #app receives
an EVENT or RETURNEVENT message it will translate it into a user interface
event. The additional part of the string (after EVENT or RETURNEVENT) is
composed of:

#figure(
    kind: table,
    table(
        columns: (auto, 1fr),
        align: left,
        table.header[*Part*][*Description*],
        [EVENT or RETURNEVENT], [UTF-8 string identifying the message as an EVENT or RETURNEVENT message.],
        [space character], [-],
        [non-whitespace-event-name], [The event that will be sent to the UI as a string event (e.g. remote-eval). This can be obtained from the event by calling event.name() in Mu or Python],
        [space character], [-],
        [non-whitespace-target-name], [Present for backwards compatibility only. We recommend you use a single “\*” character to fill this slot.],
        [space character], [-],
        [UTF-8 string], [The string event contents. Retrievable with event.contents() in Mu or Python.],
    ),
    caption: [EVENT Messages],
)

For example the full contents of an EVENT message might look like:

#code-block(lang: none, ```
MESSAGE 34 EVENT my-event-name red green blue
```)

The first word indicates a standard message. The next word (34) indicates
the length of the rest of the data. EVENT is the message sub-type which
further specifies that the next word (my-event-name) is the event to send to
the UI with the rest of the string (red green blue) as the event contents.

If a UI function that receives the event sets the return value and the
message was a RETURNEVENT, then a RETURN will be sent back. A RETURN will
have a single string that is the return value. An EVENT message will not
result in a RETURN message.

#figure(
    kind: table,
    table(
        columns: (auto, 1fr),
        align: left,
        table.header[*Part*][*Description*],
        [RETURN], [UTF-8 string identifying the message as an RETURN message.],
        [space character], [-],
        [UTF-8 string], [The string event returnContents(). This is the value set by setReturnContents() on the event object in Mu or Python.],
    ),
    caption: [RETURN Message],
)

Generally, when a RETURNEVENT is sent to your application, a RETURN should
be sent back because the other side may be blocked waiting. It's ok to send
an empty RETURN. Normally, #app will not send EVENT or RETURNEVENT messages
to other non-#app\.applications. However, it's possible that this could
happen while connected to #a-app that is also engaged in a sync session with
another #app.

Finally a DISCONNECT message comes with no additional data and signals that
the connection should be closed.

==== Ping and Pong Messages

There are three lower level messages used to keep the status of the
connection up to date. This scheme relies on each side of the connection
returning a PONG message if it ever receives a PING message whenever ping
pong messages are active.

Whether or not it's active is controlled by sending the PINGPONGCONTROL
message: when received, if the payload is the UTF-8 value “1” then PING
messages should be expected and responded to. If the value is “0” then
responding to a PING message is not mandatory.

For some applications especially those that require a lot of computation
(e.g. a display driver for a renderer) it can be a good idea to shut down
the ping pong notification. When off, both sides of the connection should
assume the other side is busy but not dead in the absence of network
activity.

#figure(
    kind: table,
    table(
        columns: (auto, 2fr, 1fr),
        align: left,
        table.header[*Message*][*Description*][*Full message value*],
        [PINGPONGCONTROL], [A payload value of “1” indicates that PING and PONG messages should be used], [PINGPONGCONTROL 1 (1 or 0)],
        [PING], [The payload is always the character “p”. Should result in a PONG response], [PING 1 p],
        [PONG], [The payload is always “p”. Should be sent in response to a PING message], [PONG 1 p],
    ),
    caption: [PING and PONG Messages],
)

=== Data Messages

The data messages come in two types: PIXELTILE and DATAEVENT. These take the
form:

#figure(
    kind: table,
    table(
        columns: (3fr, 1fr),
        align: left,
        table.header[*Content*][*Size*],
        [PIXELTILE(parameters) -or- DATAEVENT(parameters)], [1st word],
        [space character], [-],
        [A UTF-8 integer composed of the characters \[0-9\] the value of which is *N* indicating the size of the remaining message], [2nd word],
        [space character], [-],
        [Data of size *N*], [*N* bytes],
    ),
    caption: [PIXELTILE and DATAEVENT],
)

The PIXELTILE message is used to send a block of pixels to or from #app\.
When received by #app the PIXELTILE message is translated into a pixel-block
event (unless another event name is specified) which is sent to the user
interface. This message takes a number of parameters which should have no
whitespace characters and separated by commas (“,”):

#figure(
    kind: table,
    table(
        columns: (auto, 1fr),
        align: left,
        table.header[*Parameter*][*Description*],
        [w], [Width of data in pixels.],
        [h], [Height of the data in pixels. (If the height of the block of pixels is 1 and the width is the width of the image, the block is equivalent to a scanline.)],
        [x], [The horizontal offset of the pixel block relative to the image origin],
        [y], [The vertical offset of the pixel block relative to the image origin],
        [f], [The frame number],
        [event-name], [Alternate event name (instead of pixel-block). #app will only recognize pixel-block event by default. You can bind to other events however.],
        [media], [The name of the media associated with data.],
        [layer], [The name of the layer associated with the media. This is analogous to an EXR layer],
        [view], [The name of the view associated with the media. This is analogous to an EXR view],
    ),
    caption: [PIXELTILE Message],
)

For example, the PIXELTILE header to the data message might appear as:

#code-block(lang: none, ```
PIXELTILE(media=out.9.exr,layer=diffuse,view=left,w=16,h=16,x=160,y=240,f=9)
```)

Which would be parsed and used to fill fields in the Event type. This data
becomes available to Mu and Python functions binding to the event. By
default the Event object is sent to the insertCreatePixelBlock() function
which finds the image source associated with the media and inserts the data
into the correct layer and view of the image. Each of the keywords in the
PIXELTILE header is optional.

The DATAEVENT message is similar to the PIXELTILE but is intended to be
implemented by the user. The message header takes at least three parameters
which are ordered (no keywords like PIXELTILE). #app will use only the first
three parameters:

#figure(
    kind: table,
    table(
        columns: (auto, 1fr),
        align: left,
        table.header[*Parameter*][*Description*],
        [event-name], [#app will send a raw data event with this name],
        [target], [Required but not currently used],
        [content type string], [An arbitrary string indicating the type of the content. This is available to the UI from the Event.contentType() function.],
    ),
    caption: [DATAEVENT Message],
)

For example, the DATAEVENT header might appear as:

#code-block(lang: none, ```
DATAEVENT(my-data-event,unused,special-data)
```)

Which would be sent to the user interface as a my-data-event with the
content type “special-data”. The content type is retrievable with
Event.contentType(). The data payload is available via Event.dataContents()
method.
