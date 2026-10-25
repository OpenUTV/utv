#
# Copyright (C) 2023  Autodesk, Inc. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#
from rv import rvtypes, commands, extra_commands
import os
import sys
import urllib.request
import PyOpenColorIO as OCIO
from PySide6.QtCore import QTimer

#
#   Default implementations of helper methods
#
#

DEFAULT_PIPE = {}

DEFAULT_RV_PIPE = {
    "RVLinearizePipelineGroup": ["RVLinearize", "RVLensWarp"],
    "RVLookPipelineGroup": ["RVLookLUT"],
    "RVDisplayPipelineGroup": ["RVDisplayColor"],
}

OCIO_ROLES = {"OCIOFile": "RVLinearizePipelineGroup", "OCIOLook": "RVLookPipelineGroup"}

OCIO_DEFAULTS = {}

METHODS = ["ocio_config_from_media", "ocio_node_from_media"]

DEFAULT_ACES_CONFIG_FILENAME = "studio-config-all-views-v4.0.0_aces-v2.0_ocio-v2.5.ocio"
DEFAULT_ACES_CONFIG_URL = (
    "https://github.com/AcademySoftwareFoundation/OpenColorIO-Config-ACES/releases/download/v4.0.0/"
    + DEFAULT_ACES_CONFIG_FILENAME
)


def ensure_ocio_config():
    """
    Ensure an OCIO config is active:
    1. If $OCIO is already set in the environment and file exists, return it.
    2. Check if a valid config path is stored in settings.
    3. Check local candidate paths (package dir, SupportFiles, ~/.openutv/ocio).
    4. If not found locally, download the latest ACES 2.0 config from GitHub releases.
    5. Set os.environ["OCIO"], update settings, and return the resolved config path.
    """
    env_config = os.getenv("OCIO")
    if env_config and os.path.isfile(env_config):
        return env_config

    try:
        saved_config = commands.readSettings("ocio_source_setup", "ocio_config", "")
        if saved_config and os.path.isfile(saved_config):
            os.environ["OCIO"] = saved_config
            return saved_config
    except Exception:
        pass

    this_dir = os.path.dirname(os.path.abspath(__file__))
    candidate_paths = [
        os.path.join(this_dir, DEFAULT_ACES_CONFIG_FILENAME),
        os.path.join(this_dir, "..", "SupportFiles", "ocio_source_setup", DEFAULT_ACES_CONFIG_FILENAME),
        os.path.join(
            this_dir, "..", "..", "PlugIns", "SupportFiles", "ocio_source_setup", DEFAULT_ACES_CONFIG_FILENAME
        ),
        os.path.join(this_dir, "..", "PlugIns", "SupportFiles", "ocio_source_setup", DEFAULT_ACES_CONFIG_FILENAME),
        os.path.expanduser(f"~/.openutv/ocio/{DEFAULT_ACES_CONFIG_FILENAME}"),
        os.path.expanduser(f"~/Library/Application Support/OpenUTV/ocio/{DEFAULT_ACES_CONFIG_FILENAME}"),
    ]
    for p in candidate_paths:
        p_abs = os.path.abspath(p)
        if os.path.isfile(p_abs):
            os.environ["OCIO"] = p_abs
            try:
                commands.writeSettings("ocio_source_setup", "ocio_config", p_abs)
            except Exception:
                pass
            return p_abs

    target_dir = os.path.expanduser("~/.openutv/ocio")
    target_path = os.path.join(target_dir, DEFAULT_ACES_CONFIG_FILENAME)
    try:
        os.makedirs(target_dir, exist_ok=True)
        print(f"INFO: Downloading latest ACES 2.0 OCIO config from {DEFAULT_ACES_CONFIG_URL}...")
        urllib.request.urlretrieve(DEFAULT_ACES_CONFIG_URL, target_path)
        if os.path.isfile(target_path):
            print(f"INFO: Successfully downloaded ACES config to {target_path}")
            os.environ["OCIO"] = target_path
            try:
                commands.writeSettings("ocio_source_setup", "ocio_config", target_path)
            except Exception:
                pass
            return target_path
    except Exception as e:
        print(f"WARNING: Could not download default ACES config from GitHub: {e}")

    return None


#
#   Source metadata (the ColorSpace/Transfer and ColorSpace/Primaries
#   attributes the readers set) -> OCIO color spaces to try, in order. The
#   names and aliases are those of the ACES studio configs; a config without
#   any of them falls back to its file rules.
#

METADATA_COLORSPACES = {
    ("SMPTE-2084", "Rec2020"): ["Rec.2100-PQ - Display", "rec2100_pq_display", "pq_rec2020_display"],
    ("SMPTE-2084", "P3"): ["ST2084-P3-D65 - Display", "st2084_p3d65_display", "pq_p3d65_display"],
    ("Hybrid Log-Gamma", "Rec2020"): ["Rec.2100-HLG - Display", "rec2100_hlg_display", "hlg_rec2020_display"],
    ("Rec709", "Rec709"): ["Rec.1886 Rec.709 - Display", "rec1886_rec709_display", "g24_rec709_display"],
    ("sRGB", "Rec709"): ["sRGB - Display", "srgb_display"],
    ("sRGB", "sRGB"): ["sRGB - Display", "srgb_display"],
    ("Linear", "Rec709"): ["Linear Rec.709 (sRGB)", "lin_rec709"],
    ("Linear", "Rec2020"): ["Linear Rec.2020", "lin_rec2020"],
    ("Linear", "P3"): ["Linear P3-D65", "lin_p3d65"],
}


def ocio_colorspace_from_metadata(config, attributes):
    "The config's color space for the source's transfer function and primaries, or \"\"."
    key = (attributes.get("ColorSpace/Transfer", ""), attributes.get("ColorSpace/Primaries", ""))
    for name in METADATA_COLORSPACES.get(key, []):
        try:
            colorspace = config.getColorSpace(name)
        except Exception:
            colorspace = None
        if colorspace:
            return colorspace.getName()
    return ""


#
#   The macOS view presents through a surface tagged with the color space
#   of its presentation mode (MetalPresentationFormat.mm), so the OCIO
#   display has to encode that color space. The EDR surface is extended
#   sRGB, with sRGB primaries, so EDR uses the sRGB display and not
#   Display P3 HDR.
#

PRESENTATION_DISPLAYS = {
    "sdr": "sRGB - Display",
    "edr": "sRGB - Display",
    "pq": "Rec.2100-PQ - Display",
    "hlg": "Rec.2100-HLG - Display",
}

#
#   Display-referred video is already graded for a display: show it as it
#   is. Scene-referred and log media go through an ACES output transform,
#   tone-mapped for the presentation's range.
#

VIDEO_ENCODINGS = ("sdr-video", "hdr-video", "edr-video", "display-linear")
VIDEO_VIEWS = ["Video (colorimetric)"]
SDR_SCENE_VIEWS = ["ACES 2.0 - SDR 100 nits (Rec.709)"]
HDR_SCENE_VIEWS = ["ACES 2.0 - HDR 1000 nits (P3 D65)"]


def read_presentation_mode():
    'The macOS presentation mode (sdr, edr, pq or hlg) as MetalView reads it, or "" off macOS.'
    if sys.platform != "darwin" or os.getenv("RV_DISABLE_METAL_VIEW"):
        return ""
    mode = os.getenv("UTV_MACOS_PRESENTATION")
    if mode is None:
        try:
            mode = commands.readSettings("Display", "macosPresentation", "sdr")
        except Exception:
            mode = "sdr"
    mode = str(mode).lower()
    return mode if mode in PRESENTATION_DISPLAYS else "sdr"


#
#   The ACES config displays that show right in each presentation mode.
#   The SDR and EDR surfaces have sRGB primaries, so P3 displays come out
#   desaturated there, and the PQ and HLG surfaces are Rec.2100, so only
#   the matching Rec.2100 display fits. Displays not named here (studio
#   configs) are never warned about.
#

SDR_DISPLAYS = ["sRGB - Display", "Gamma 2.2 Rec.709 - Display", "Rec.1886 Rec.709 - Display"]
PRESENTATION_COMPATIBLE_DISPLAYS = {
    "sdr": SDR_DISPLAYS,
    "edr": SDR_DISPLAYS,
    "pq": ["Rec.2100-PQ - Display"],
    "hlg": ["Rec.2100-HLG - Display"],
}
KNOWN_DISPLAYS = SDR_DISPLAYS + [
    "Display P3 - Display",
    "Display P3 HDR - Display",
    "P3-D65 - Display",
    "Rec.2100-PQ - Display",
    "Rec.2100-HLG - Display",
    "ST2084-P3-D65 - Display",
]
PRESENTATION_NAMES = {"sdr": "SDR", "edr": "EDR", "pq": "HDR PQ (Rec.2100)", "hlg": "HDR HLG (Rec.2100)"}


def display_warning(config, mode, display):
    'Why the display won\'t show right in the macOS presentation mode, or "".'
    if not mode or config is None or display not in KNOWN_DISPLAYS:
        return ""
    if display in PRESENTATION_COMPATIBLE_DISPLAYS[mode]:
        return ""
    expected = PRESENTATION_DISPLAYS[mode]
    if expected not in config.getDisplays():
        return ""
    return "%s doesn't match the %s presentation: colors or levels will be wrong. Use %s." % (
        display,
        PRESENTATION_NAMES[mode],
        expected,
    )


def warnAboutDisplay(config, display):
    warning = display_warning(config, PRESENTATION_MODE, display)
    if warning:
        print("WARNING: OCIO: " + warning)
        extra_commands.displayFeedback("OCIO: " + warning, 6.0)


#   The view reads the mode once at startup, so a changed preference only
#   applies after a restart. Read it here at the same time.
PRESENTATION_MODE = read_presentation_mode()


def auto_display_view(config, mode, colorspace):
    """
    The OCIO display for the presentation mode and the view for a source
    in the given color space. Falls back to the config's defaults for
    anything the config doesn't have.
    """
    display = PRESENTATION_DISPLAYS.get(mode, "")
    if display not in config.getDisplays():
        display = config.getDefaultDisplay()

    try:
        encoding = config.getColorSpace(colorspace).getEncoding() if colorspace else ""
    except Exception:
        encoding = ""
    if encoding in VIDEO_ENCODINGS:
        candidates = VIDEO_VIEWS
    elif mode in ("pq", "hlg"):
        candidates = HDR_SCENE_VIEWS
    else:
        candidates = SDR_SCENE_VIEWS

    views = config.getViews(display)
    view = next((v for v in candidates if v in views), config.getDefaultView(display))
    return display, view


def ocio_config_from_media(media, attributes):
    cfg_path = ensure_ocio_config()
    if cfg_path and os.path.isfile(cfg_path):
        return OCIO.Config.CreateFromFile(cfg_path)
    if os.getenv("OCIO") is not None:
        return OCIO.GetCurrentConfig()
    raise Exception("No OCIO config available")


def ocio_node_from_media(config, node, default, media=None, attributes={}):
    result = [{"nodeType": d, "context": {}, "properties": {}} for d in default]

    nodeType = commands.nodeType(node)

    if nodeType == "RVDisplayPipelineGroup":
        display, view = auto_display_view(config, PRESENTATION_MODE, attributes.get("input_colorspace", ""))

        result = [
            {
                "nodeType": "OCIODisplay",
                "context": {},
                "properties": {
                    "ocio.function": "display",
                    "ocio.inColorSpace": OCIO.ROLE_SCENE_LINEAR,
                    "ocio_display.view": view,
                    "ocio_display.display": display,
                },
            }
        ]

    elif nodeType == "RVLinearizePipelineGroup":
        inspace = config.parseColorSpaceFromString(media)
        if inspace == "":
            inspace = attributes.get("default_setting", "")
        if inspace != "":
            result = [
                {
                    "nodeType": "OCIOFile",
                    "context": {},
                    "properties": {
                        "ocio.function": "color",
                        "ocio.inColorSpace": inspace,
                        "ocio_color.outColorSpace": OCIO.ROLE_SCENE_LINEAR,
                    },
                },
                {"nodeType": "RVLensWarp", "context": {}, "properties": {}},
            ]

    elif nodeType == "RVLookPipelineGroup":
        look = attributes.get("default_setting", "")
        if look != "":
            result = [
                {
                    "nodeType": "OCIOLook",
                    "context": {},
                    "properties": {"ocio.function": "look", "ocio_look.look": look},
                }
            ]

    return result


#
#   A couple of convenience functions
#


def isOCIOManaged(nodeType):
    def F():
        try:
            managed = commands.getIntProperty("#" + nodeType + ".ocio.active")[0] != 0
            return commands.CheckedMenuState if managed else commands.UncheckedMenuState
        except Exception:
            return commands.UncheckedMenuState

    return F


def isOCIODisplayManaged(group):
    def F():
        try:
            groupName = "RVDisplayPipelineGroup"
            dpipeline = groupMemberOfType(group, groupName)
            dOCIO = groupMemberOfType(dpipeline, "OCIODisplay")
            managed = commands.getIntProperty(dOCIO + ".ocio.active")[0] != 0
            return commands.CheckedMenuState if managed else commands.UncheckedMenuState
        except Exception:
            return commands.UncheckedMenuState

    return F


#
#   What the OCIO menu shows next to each submenu: the value OCIO is
#   applying, or "Built-in" when UTV's own color pipeline handles that
#   step.
#

BUILT_IN = "Built-in"
NO_LOOK = "None"

#   Property changes that alter what the OCIO menu shows.
MENU_PROPERTIES = (
    ".ocio.active",
    ".ocio.inColorSpace",
    ".ocio_display.display",
    ".ocio_display.view",
    ".ocio_look.look",
)
DISPLAY_PROPERTIES = (".ocio.active", ".ocio_display.display", ".ocio_display.view")


def displayValue(node):
    "(display, view) of an OCIO node."
    return (
        commands.getStringProperty(node + ".ocio_display.display")[0],
        commands.getStringProperty(node + ".ocio_display.view")[0],
    )


def currentSourceOCIOValue(nodeType, prop, unmanaged=BUILT_IN):
    "The value of prop on the current source's nodeType node, or unmanaged when OCIO isn't managing it."
    try:
        if commands.getIntProperty("#" + nodeType + ".ocio.active")[0] == 0:
            return unmanaged
        return commands.getStringProperty("#" + nodeType + "." + prop)[0]
    except Exception:
        return unmanaged


def allSourcesOCIOValue(nodeType, prop, unmanaged=BUILT_IN):
    'The value of prop shared by every nodeType node, unmanaged when none is active, or "Mixed".'
    values = set()
    for node in commands.nodesOfType(nodeType):
        try:
            if commands.getIntProperty(node + ".ocio.active")[0] != 0:
                values.add(commands.getStringProperty(node + "." + prop)[0])
        except Exception:
            pass
    if not values:
        return unmanaged
    return values.pop() if len(values) == 1 else "Mixed"


def displayOCIOValue(group):
    "\"display · view\" of the display group's OCIODisplay, or BUILT_IN when OCIO isn't managing it."
    try:
        dpipeline = groupMemberOfType(group, "RVDisplayPipelineGroup")
        dOCIO = groupMemberOfType(dpipeline, "OCIODisplay")
        if dOCIO is None or commands.getIntProperty(dOCIO + ".ocio.active")[0] == 0:
            return BUILT_IN
        display = commands.getStringProperty(dOCIO + ".ocio_display.display")[0]
        view = commands.getStringProperty(dOCIO + ".ocio_display.view")[0]
        return display + " \u00b7 " + view
    except Exception:
        return BUILT_IN


def ocioMenuCheck(nodeType, prop, value):
    def F():
        try:
            current = commands.getStringProperty("#" + nodeType + "." + prop)[0]
            managed = isOCIOManaged(nodeType)() == commands.CheckedMenuState
            checked = current == value and managed
            return commands.CheckedMenuState if checked else commands.NeutralMenuState
        except Exception:
            return commands.DisabledMenuState

    return F


def ocioDisplayMenuCheck(group, display, view):
    def F():
        try:
            groupName = "RVDisplayPipelineGroup"
            dpipeline = groupMemberOfType(group, groupName)
            dOCIO = groupMemberOfType(dpipeline, "OCIODisplay")
            d = commands.getStringProperty(dOCIO + ".ocio_display.display")[0]
            v = commands.getStringProperty(dOCIO + ".ocio_display.view")[0]
            if d == display and v == view:
                return commands.CheckedMenuState
            return commands.UncheckedMenuState
        except Exception:
            return commands.DisabledMenuState

    return F


def ocioEvent(nodeType, prop, value):
    "This function will apply its change on the current node of nodeType in the evaluation path"

    def F(event):
        commands.setStringProperty("#" + nodeType + "." + prop, [value], True)
        commands.redraw()

    return F


def ocioEventOnAllOfType(nodeType, prop, value):
    "This function will apply its change on all nodes of nodeType"

    def F(event):
        for node in commands.nodesOfType(nodeType):
            commands.setStringProperty(node + "." + prop, [value], True)
        commands.redraw()

    return F


def ocioDisplayEvent(group, display, view):
    def F(event):
        groupName = "RVDisplayPipelineGroup"
        dpipeline = groupMemberOfType(group, groupName)
        dOCIO = groupMemberOfType(dpipeline, "OCIODisplay")
        # Both 'display' and 'view' must be set together.
        # Disable the OCIONode during display/view propety changes.
        # Prevents node from rebuilding shaders while it may be in an invalid state.
        commands.setIntProperty(dOCIO + ".ocio.active", [0], True)
        commands.setStringProperty(dOCIO + ".ocio_display.display", [display], True)
        commands.setStringProperty(dOCIO + ".ocio_display.view", [view], True)
        commands.setIntProperty(dOCIO + ".ocio.active", [1], True)
        warnAboutDisplay(theMode().config, display)
        commands.redraw()

    return F


#
#   Switching a pipeline to OCIO and back replaces its nodes, and the new
#   built-in nodes start with default properties: the display loses its
#   sRGB (or profile) transform and the source its file transfer function.
#   Save the built-in nodes' properties before switching to OCIO and put
#   them back after switching back.
#

PROPERTY_ACCESSORS = {
    commands.IntType: (commands.getIntProperty, commands.setIntProperty),
    commands.FloatType: (commands.getFloatProperty, commands.setFloatProperty),
    commands.StringType: (commands.getStringProperty, commands.setStringProperty),
    commands.HalfType: (commands.getHalfProperty, commands.setHalfProperty),
    commands.ByteType: (commands.getByteProperty, commands.setByteProperty),
}


def savePipelineProperties(pipeline):
    "{nodeType: {property: (type, values)}} for the nodes of a pipeline group."
    saved = {}
    for node in commands.nodesInGroup(pipeline):
        values = {}
        for prop in commands.properties(node):
            try:
                kind = commands.propertyInfo(prop)["type"]
                if kind in PROPERTY_ACCESSORS:
                    values[prop[len(node) :]] = (kind, PROPERTY_ACCESSORS[kind][0](prop))
            except Exception:
                pass
        saved[commands.nodeType(node)] = values
    return saved


def restorePipelineProperties(pipeline, saved):
    for node in commands.nodesInGroup(pipeline):
        for suffix, (kind, values) in saved.get(commands.nodeType(node), {}).items():
            try:
                PROPERTY_ACCESSORS[kind][1](node + suffix, values, True)
            except Exception:
                pass


def allSources():
    return commands.nodesOfType("RVFileSource") + commands.nodesOfType("RVImageSource")


def sourceOCIOFile(source):
    srcPipeline = groupMemberOfType(commands.nodeGroup(source), OCIO_ROLES["OCIOFile"])
    return groupMemberOfType(srcPipeline, "OCIOFile")


def displayOCIONode(group):
    return groupMemberOfType(groupMemberOfType(group, "RVDisplayPipelineGroup"), "OCIODisplay")


def isVideoColorSpace(config, colorspace):
    "True for a display-referred (graded video) color space."
    try:
        return config.getColorSpace(colorspace).getEncoding() in VIDEO_ENCODINGS
    except Exception:
        return False


def currentSource():
    "The file or image source at the current frame, else the first one, else None."
    for sourceType in ("RVFileSource", "RVImageSource"):
        try:
            evalInfo = commands.metaEvaluateClosestByType(commands.frame(), sourceType, None)
        except Exception:
            evalInfo = []
        if evalInfo:
            return evalInfo[0]["node"]
    sources = commands.nodesOfType("RVFileSource") + commands.nodesOfType("RVImageSource")
    return sources[0] if sources else None


def groupMemberOfType(node, memberType):
    for n in commands.nodesInGroup(node):
        if commands.nodeType(n) == memberType:
            return n
    return None


def applyProps(node, contextProps, propertiesProps):
    for pprop, avalue in propertiesProps.items():
        commands.setStringProperty(node + "." + pprop, [avalue], True)
    for cprop, cvalue in contextProps.items():
        prop = node + ".ocio_context." + cprop
        if not commands.propertyExists(prop):
            commands.newProperty(prop, commands.StringType, 1)
        commands.setStringProperty(prop, [cvalue], True)


#
#   OCIOSourceSetupMode
#


class OCIOSourceSetupMode(rvtypes.MinorMode):
    """
    This mode integrates both with the base RV source_setup package and
    OCIO. The idea is that incoming source media is first examined by the
    base setup package then when appropriate, this package will switch the
    source to use OCIO. If any source uses OCIO, the display is also
    switched over to OCIO control.

    There are many assumptions here. First and foremost is that your OCIO
    worflow uses parseColorSpaceFromString() to determine incoming color
    space.

    ORDERING: this mode uses a sort key of "source_setup" with an
    ordering value of 10 which is after the default source_setup
    mode's ordering value of 0. This ensures that the default
    source_setup is run first and is then followed by the
    ocio_source_setup. If you are using this as an example for a
    different source_setup mode which you wish to have interoperate
    with the default and ocio modes use the same key of "source_setup"
    but with an ordering number that places it relative to the default
    and ocio modes. So for example if you want yours to come before
    the ocio mode, but after the default source_setup use 5 (since its
    between 0 and 10).
    """

    def useSourceOCIO(self, source, nodeType, defaultSetting=""):
        """
        This tells the source group to use OCIO instead of the RV
        linearize node. There is also ocio.look and ocio.preCache
        which can be activated in this way. For this code we're
        only assuming that OCIO is going to be used to linearize
        the source.
        """

        medias = commands.getStringProperty("%s.media.movie" % source)
        media = medias[0]

        try:
            srcAttrs = commands.sourceAttributes(source, media)
            attrDict = dict(zip([i[0] for i in srcAttrs], [j[1] for j in srcAttrs]))
            attrDict["source_node"] = source
            attrDict["default_setting"] = defaultSetting
        except Exception:
            attrDict = {}

        if self.config is None:
            try:
                self.config = ocio_config_from_media(media, attrDict)
                OCIO.SetCurrentConfig(self.config)
                commands.defineModeMenu("OCIO Source Setup", self.buildOCIOMenu(), True)
            except Exception:
                return

        #
        # If we already have this OCIO node and we are reading a session,
        # then use the one we have and return
        #

        pipeSlot = OCIO_ROLES[nodeType]
        srcPipeline = groupMemberOfType(commands.nodeGroup(source), pipeSlot)
        ocioNode = groupMemberOfType(srcPipeline, nodeType)
        if ocioNode is not None and self.readingSession:
            for pNode in commands.nodesInGroup(srcPipeline):
                if commands.nodeType(pNode).startswith("OCIO"):
                    commands.ocioUpdateConfig(pNode)

            print(("INFO: using %s node for %s %s" % (nodeType, source, pipeSlot)))
            return

        #
        #   Anywhere in RV there is a pipeline "slot" (File, Linearize,
        #   Look, Display, View) you can use an OCIO node.  Each OCIO node
        #   can futher be configured to act in a manner similar to the nuke
        #   OCIO color, look, or display nodes. In this case we want it to
        #   act as an OCIO color node so we can transform from the incoming
        #   file space to the ROLE_SCENE_LINEAR space (the working space)
        #
        #   You can only get the OCIO node *after* the source group has
        #   been configured to use it. Otherwise the pipelines will not
        #   have been created yet.
        #
        #   Under the hood, an RV "color" OCIO node builds a ColorSpace for
        #   inspace and outspace and uses the processor which converts from
        #   one to the other.
        #

        try:
            if pipeSlot not in DEFAULT_PIPE:
                currentPipelineNodes = commands.getStringProperty(srcPipeline + ".pipeline.nodes")

                # We need to handle the following special case here:
                # We might be in the process of reloading an RV session that
                # is already OCIO color corrected in which case we do not
                # want this pipeline to be considered the default (non OCIO).
                # Example: srcPipelineNodes = [ "OCIOFile" "RVLensWarp" ]
                # We will use the RV default instead in that special case.
                if nodeType in currentPipelineNodes and pipeSlot in DEFAULT_RV_PIPE:
                    DEFAULT_PIPE[pipeSlot] = DEFAULT_RV_PIPE[pipeSlot]
                else:
                    DEFAULT_PIPE[pipeSlot] = currentPipelineNodes
            pipelineList = ocio_node_from_media(self.config, srcPipeline, DEFAULT_PIPE[pipeSlot], media, attrDict)
        except Exception as inst:
            print(("ERROR: Problem occurred while loading OCIO settings for %s: %s" % (nodeType, inst)))
            return

        try:
            pipeline = [p["nodeType"] for p in pipelineList]
        except KeyError as inst:
            print(("ERROR: Unable to make use of ocio_node_from_media return: %s" % inst))
        if pipeline == DEFAULT_PIPE[pipeSlot]:
            return

        print(("INFO: using %s node for %s %s" % (nodeType, source, pipeSlot)))

        if commands.getStringProperty(srcPipeline + ".pipeline.nodes") == DEFAULT_PIPE[pipeSlot]:
            self.builtInProperties[srcPipeline] = savePipelineProperties(srcPipeline)
        commands.setStringProperty(srcPipeline + ".pipeline.nodes", pipeline, True)
        pipeNodes = commands.nodesInGroup(srcPipeline)
        pipeNodes.sort()
        for index, pNode in enumerate(pipelineList):
            stageOCIO = pipeNodes[index]
            try:
                applyProps(stageOCIO, pNode["context"], pNode["properties"])
            except KeyError as inst:
                print(("ERROR: Unable to apply properties to %s: %s" % (stageOCIO, inst)))

        commands.redraw()

    def disableSourceOCIO(self, source, nodeType):
        """
        This reverts the source group's linearize node back to using
        a native RVLinearize node.
        """

        pipeSlot = OCIO_ROLES[nodeType]
        srcPipeline = groupMemberOfType(commands.nodeGroup(source), pipeSlot)
        nodesProp = srcPipeline + ".pipeline.nodes"
        current = commands.getStringProperty(nodesProp)

        if pipeSlot not in DEFAULT_PIPE or current == DEFAULT_PIPE[pipeSlot]:
            return

        print(("INFO: resetting %s for %s" % (pipeSlot, source)))

        commands.setStringProperty(srcPipeline + ".pipeline.nodes", DEFAULT_PIPE[pipeSlot], True)
        restorePipelineProperties(srcPipeline, self.builtInProperties.pop(srcPipeline, {}))
        commands.redraw()

    def useDisplayOCIO(self, group, source=None):
        """
        This installs the OCIODisplay node in the DisplayGroup's display pipeline
        in place of RV's RVDisplayColor node. The display and view are chosen
        for the presentation mode and for source (default: the current one).

        NOTE: in RV4 all display devices are separate
        DisplayGroups. So each one can have a completely different
        view and display transform.
        """

        if self.usingOCIOForDisplay.get(group, False) or self.config is None:
            return

        groupName = "RVDisplayPipelineGroup"
        try:
            dpipeline = groupMemberOfType(group, groupName)
            if groupName not in DEFAULT_PIPE:
                currentPipelineNodes = commands.getStringProperty(dpipeline + ".pipeline.nodes")

                # We need to handle the following special case here:
                # We might be in the process of reloading an RV session that
                # is already OCIO color corrected in which case we do not
                # want this pipeline to be considered the default (non OCIO).
                # We will use the RV default instead in that special case.
                if "OCIODisplay" in currentPipelineNodes and groupName in DEFAULT_RV_PIPE:
                    DEFAULT_PIPE[groupName] = DEFAULT_RV_PIPE[groupName]
                else:
                    DEFAULT_PIPE[groupName] = currentPipelineNodes
            pipelineList = self.displayPipeline(dpipeline, source)
        except Exception as inst:
            print(("ERROR: Problem occurred while loading OCIO settings for OCIODisplay: %s" % inst))
            return

        try:
            pipeline = [p["nodeType"] for p in pipelineList]
        except KeyError as inst:
            print(("ERROR: Unable to make use of ocio_node_from_media return: %s" % inst))
        if pipeline == DEFAULT_PIPE[groupName]:
            return

        device = commands.getStringProperty(group + ".device.name")[0]
        print(("INFO: using OCIODisplay for display: %s" % device))

        dpipeline = groupMemberOfType(group, groupName)
        if commands.getStringProperty(dpipeline + ".pipeline.nodes") == DEFAULT_PIPE[groupName]:
            self.builtInProperties[dpipeline] = savePipelineProperties(dpipeline)
        commands.setStringProperty(dpipeline + ".pipeline.nodes", pipeline, True)

        pipeNodes = commands.nodesInGroup(dpipeline)
        pipeNodes.sort()
        for index, pNode in enumerate(pipelineList):
            stageOCIO = pipeNodes[index]
            # As in ocioDisplayEvent: keep the node off until display and view
            # are both set, or it builds a transform from a view the display
            # doesn't have.
            activeProp = stageOCIO + ".ocio.active"
            hasActive = commands.propertyExists(activeProp)
            if hasActive:
                commands.setIntProperty(activeProp, [0], True)
            try:
                applyProps(stageOCIO, pNode["context"], pNode["properties"])
            except KeyError as inst:
                print(("ERROR: Unable to apply properties to %s: %s" % (stageOCIO, inst)))
            if hasActive:
                commands.setIntProperty(activeProp, [1], True)

        self.usingOCIOForDisplay[group] = True
        dOCIO = groupMemberOfType(dpipeline, "OCIODisplay")
        if dOCIO is not None:
            self.autoViews[group] = displayValue(dOCIO)
            warnAboutDisplay(self.config, self.autoViews[group][0])
        self.useSourceOCIOInputs()
        commands.redraw()

    def displayPipeline(self, dpipeline, source=None):
        attributes = {"input_colorspace": self.viewColorSpace(source)}
        return ocio_node_from_media(self.config, dpipeline, DEFAULT_PIPE["RVDisplayPipelineGroup"], None, attributes)

    def viewColorSpace(self, source=None):
        """
        The input color space to choose the view for. Graded video comes
        through any view unchanged (see syncVideoInputs), so a scene-referred
        source anywhere in the session decides; otherwise source, or the
        current one.
        """
        for s in allSources():
            colorspace = self.inputColorSpace(s)
            if colorspace and not isVideoColorSpace(self.config, colorspace):
                return colorspace
        return self.inputColorSpace(source)

    def updateAutoViews(self):
        """
        A source added later can change the view to choose: switch the
        displays whose view UTV chose and the user hasn't changed since.
        """
        for group, chosen in list(self.autoViews.items()):
            dOCIO = displayOCIONode(group) if self.usingOCIOForDisplay.get(group, False) else None
            if dOCIO is None or displayValue(dOCIO) != chosen:
                del self.autoViews[group]
                continue
            try:
                properties = self.displayPipeline(groupMemberOfType(group, "RVDisplayPipelineGroup"))[0]["properties"]
                wanted = (properties["ocio_display.display"], properties["ocio_display.view"])
            except Exception:
                continue
            if wanted != chosen:
                print("INFO: OCIO display view is now %s · %s" % wanted)
                self.autoViews[group] = wanted
                ocioDisplayEvent(group, wanted[0], wanted[1])(None)

    def disableDisplayOCIO(self, group):
        """
        This reverts the DisplayGroup's display pipeline back to using
        RV's native RVDisplayColor node.
        """

        groupName = "RVDisplayPipelineGroup"
        dpipeline = groupMemberOfType(group, groupName)
        nodesProp = dpipeline + ".pipeline.nodes"
        current = commands.getStringProperty(nodesProp)

        if groupName not in DEFAULT_PIPE or current == DEFAULT_PIPE[groupName]:
            return

        commands.setStringProperty(dpipeline + ".pipeline.nodes", DEFAULT_PIPE[groupName], True)
        restorePipelineProperties(dpipeline, self.builtInProperties.pop(dpipeline, {}))

        device = commands.getStringProperty(group + ".device.name")[0]
        print(("INFO: using RVDisplayColor for display: %s" % device))

        self.usingOCIOForDisplay[group] = False
        self.autoViews.pop(group, None)
        if not any(self.usingOCIOForDisplay.values()):
            self.disableSourceOCIOInputs()
        else:
            self.syncVideoInputs()
        commands.redraw()

    def sourceUsesOCIOInput(self, source):
        srcPipeline = groupMemberOfType(commands.nodeGroup(source), OCIO_ROLES["OCIOFile"])
        ocioFile = groupMemberOfType(srcPipeline, "OCIOFile")
        try:
            return ocioFile is not None and commands.getIntProperty(ocioFile + ".ocio.active")[0] != 0
        except Exception:
            return False

    def sourceInputColorSpace(self, source):
        """
        The OCIO color space a source's pixels are in: from the file's
        metadata, else the config's file rules for its path.
        """
        media = commands.getStringProperty(source + ".media.movie")[0]
        try:
            attributes = dict(commands.sourceAttributes(source, media))
        except Exception:
            attributes = {}
        colorspace = ocio_colorspace_from_metadata(self.config, attributes)
        if not colorspace:
            try:
                colorspace = self.config.getColorSpaceFromFilepath(media)
            except Exception:
                colorspace = ""
        return colorspace

    def inputColorSpace(self, source=None):
        'The OCIO color space of source, or of the source at the current frame, or "".'
        if source is None:
            source = currentSource()
        if source is None:
            return ""
        if self.sourceUsesOCIOInput(source):
            srcPipeline = groupMemberOfType(commands.nodeGroup(source), OCIO_ROLES["OCIOFile"])
            return commands.getStringProperty(groupMemberOfType(srcPipeline, "OCIOFile") + ".ocio.inColorSpace")[0]
        return self.sourceInputColorSpace(source)

    def useSourceOCIOInputs(self, sources=None):
        """
        The OCIO display expects the working space (scene_linear) from
        every source, but UTV's built-in linearize outputs linear Rec.709.
        So while an OCIO display is in use, give each source that OCIO
        isn't linearizing an OCIO input color space from its metadata or
        the config's file rules. Sources set up this way are switched back
        when no display uses OCIO any more; ones the user set are left.
        """
        if self.config is None or self.readingSession:
            return
        if sources is None:
            sources = commands.nodesOfType("RVFileSource") + commands.nodesOfType("RVImageSource")
        for source in sources:
            if self.sourceUsesOCIOInput(source):
                continue
            colorspace = self.sourceInputColorSpace(source)
            if not colorspace:
                media = os.path.basename(commands.getStringProperty(source + ".media.movie")[0])
                warning = "no input color space for %s, so the OCIO display may show it wrongly." % media
                print("WARNING: OCIO: " + warning)
                extra_commands.displayFeedback("OCIO: " + warning, 6.0)
                continue
            self.useSourceOCIO(source, "OCIOFile", colorspace)
            if self.sourceUsesOCIOInput(source):
                self.autoInputSources[source] = colorspace
                print("INFO: %s is %s for the OCIO display" % (source, colorspace))
        self.syncVideoInputs()

    def disableSourceOCIOInputs(self):
        for source in self.autoInputSources:
            if source in allSources():
                self.disableSourceOCIO(source, "OCIOFile")
        self.autoInputSources.clear()

    def mainDisplayView(self):
        "The display and view of the main window's OCIO display (else any OCIO display's), or None."
        groups = [g for g in commands.nodesOfType("RVDisplayGroup") if self.usingOCIOForDisplay.get(g, False)]
        groups.sort(key=lambda g: commands.getStringProperty(g + ".device.moduleName")[0] != "Desktop")
        for group in groups:
            dOCIO = displayOCIONode(group)
            if dOCIO is not None:
                return displayValue(dOCIO)
        return None

    def syncVideoInputs(self):
        """
        Show graded video as graded whatever the view. Each display-referred
        source UTV gave an input color space goes through the inverse of
        the main display's view (the OCIO node's ocio_color.invertView), so
        the view gives the video back unchanged where it can show it, and
        only scene-referred media gets the view's tone mapping. A source
        whose input the user has changed since is theirs and left alone.
        """
        if self.config is None:
            return
        displayView = self.mainDisplayView()
        for source, colorspace in list(self.autoInputSources.items()):
            ocioFile = sourceOCIOFile(source) if source in allSources() else None
            invertProp = None if ocioFile is None else ocioFile + ".ocio_color.invertView"
            if invertProp is None or not commands.propertyExists(invertProp):
                del self.autoInputSources[source]
                continue
            if commands.getStringProperty(ocioFile + ".ocio.inColorSpace")[0] != colorspace:
                del self.autoInputSources[source]
                commands.setIntProperty(invertProp, [0], True)
                continue
            if displayView is not None and isVideoColorSpace(self.config, colorspace):
                wanted = (1,) + displayView
            else:
                wanted = (0,) + displayValue(ocioFile)
            if (commands.getIntProperty(invertProp)[0],) + displayValue(ocioFile) == wanted:
                continue
            commands.setIntProperty(ocioFile + ".ocio.active", [0], True)
            commands.setStringProperty(ocioFile + ".ocio_display.display", [wanted[1]], True)
            commands.setStringProperty(ocioFile + ".ocio_display.view", [wanted[2]], True)
            commands.setIntProperty(invertProp, [wanted[0]], True)
            commands.setIntProperty(ocioFile + ".ocio.active", [1], True)

    def scheduleVideoSync(self):
        if not self.videoSyncPending:
            self.videoSyncPending = True
            QTimer.singleShot(0, self.runVideoSync)

    def runVideoSync(self):
        self.videoSyncPending = False
        self.syncVideoInputs()

    def sourceSetup(self, event):
        """
        This function should be bound to the "source-group-complete" event. It
        will attempt to use OCIO to infer the incoming file space. If
        it succeeds, the OCIOFile node of the source group is
        activated and used to convert to the ROLE_SCENE_LINEAR space.
        """

        event.reject()  # don't eat this event -- allow others to get it too

        args = event.contents().split(";;")
        group = args[0]
        fileSource = groupMemberOfType(group, "RVFileSource")
        imageSource = groupMemberOfType(group, "RVImageSource")
        source = fileSource if imageSource is None else imageSource

        for nodeType in OCIO_ROLES.keys():
            self.useSourceOCIO(source, nodeType)

        if any(self.usingOCIOForDisplay.values()):
            self.useSourceOCIOInputs([source])
            self.updateAutoViews()

        #
        #   If this is the first OCIO color pipeline for a source assume
        #   that we also want to use OCIO for display. In this case we're
        #   just going to assume the defaults
        #

        if len(commands.nodesOfType("OCIOFile")) >= 1:
            for group in commands.nodesOfType("RVDisplayGroup"):
                if not self.usingOCIOForDisplay.get(group, False):
                    self.useDisplayOCIO(group, source)

    def beforeSessionRead(self, event):
        event.reject()
        self.readingSession = True

    def afterSessionRead(self, event):
        event.reject()
        self.readingSession = False
        if len(commands.nodesOfType("OCIOFile")) > 1:
            for group in commands.nodesOfType("RVDisplayGroup"):
                if not self.usingOCIOForDisplay.get(group, False):
                    self.useDisplayOCIO(group)

    def ocioActiveEvent(self, nodeType):
        def F(event):
            if nodeType not in ["OCIOFile", "OCIOLook"]:
                if isOCIODisplayManaged(nodeType)() == commands.CheckedMenuState:
                    self.disableDisplayOCIO(nodeType)
                else:
                    self.useDisplayOCIO(nodeType)
                return

            evalInfo = commands.metaEvaluateClosestByType(commands.frame(), "RVFileSource", None)
            if len(evalInfo) == 0:
                evalInfo = commands.metaEvaluateClosestByType(commands.frame(), "RVImageSource", None)
            if len(evalInfo) == 0:
                return
            source = evalInfo[0]["node"]

            if isOCIOManaged(nodeType)() == commands.CheckedMenuState:
                self.disableSourceOCIO(source, nodeType)
            else:
                self.useSourceOCIO(source, nodeType, OCIO_DEFAULTS[nodeType])

        return F

    def checkForDisplayGroup(self, event):
        event.reject()
        try:
            node = event.contents()
            if commands.nodeType(node) == "RVDisplayGroup":
                self.usingOCIOForDisplay[node] = False
                commands.defineModeMenu("OCIO Source Setup", self.buildOCIOMenu(), True)
        except Exception as inst:
            print((str(inst), node))

    def maybeUpdateViews(self, event):
        event.reject()
        if event.contents().endswith(MENU_PROPERTIES):
            self.scheduleMenuUpdate()
        if (
            event.contents().endswith(DISPLAY_PROPERTIES)
            and commands.nodeType(event.contents().split(".")[0]) == "OCIODisplay"
        ):
            self.scheduleVideoSync()

    def updateMenuForCurrentSource(self, event):
        event.reject()
        if commands.isPlaying():
            return
        state = (
            currentSourceOCIOValue("OCIOFile", "ocio.inColorSpace"),
            currentSourceOCIOValue("OCIOLook", "ocio_look.look", NO_LOOK),
        )
        if state != self.menuSourceState:
            self.scheduleMenuUpdate()

    def scheduleMenuUpdate(self, event=None):
        """
        Rebuild the menu once the current event is handled, so that a
        burst of property changes (display and view are set together)
        rebuilds it once.
        """
        if event is not None:
            event.reject()
        if not self.menuUpdatePending:
            self.menuUpdatePending = True
            QTimer.singleShot(0, self.updateMenu)

    def updateMenu(self):
        self.menuUpdatePending = False
        commands.defineModeMenu("OCIO Source Setup", self.buildOCIOMenu(), True)

    def selectConfig(self, event):
        try:
            config = commands.openFileDialog(True, False, False, "ocio|OCIO Config", None)[0]
            self.config = OCIO.Config.CreateFromFile(config)
            OCIO.SetCurrentConfig(self.config)
            for source in commands.nodesOfType("RVFileSource") + commands.nodesOfType("RVImageSource"):
                for nodeType in OCIO_ROLES.keys():
                    self.disableSourceOCIO(source, nodeType)
            for group in commands.nodesOfType("RVDisplayGroup"):
                self.disableDisplayOCIO(group)
            DEFAULT_PIPE.clear()
            for source in commands.nodesOfType("RVFileSource") + commands.nodesOfType("RVImageSource"):
                for nodeType in OCIO_ROLES.keys():
                    self.useSourceOCIO(source, nodeType)
            for group in commands.nodesOfType("RVDisplayGroup"):
                self.usingOCIOForDisplay[group] = False
                self.useDisplayOCIO(group)
            commands.defineModeMenu("OCIO Source Setup", self.buildOCIOMenu(), True)
            commands.writeSettings("ocio_source_setup", "ocio_config", config)
        except Exception as inst:
            print(inst)

    def buildOCIOMenu(self):
        #
        #   Try to acquire OCIO config to populate the display menu
        #

        if self.config is None:
            try:
                self.config = ocio_config_from_media(None, None)
                OCIO.SetCurrentConfig(self.config)
            except Exception:
                return [("OCIO", [("Choose Config...", self.selectConfig, None, None)])]

        #
        #   Make a unique entry for each device's display group
        #

        daList = []
        for display in commands.nodesOfType("RVDisplayGroup"):
            dList = [
                (
                    "Active",
                    self.ocioActiveEvent(display),
                    None,
                    isOCIODisplayManaged(display),
                ),
                ("_", None),
            ]
            for d in self.config.getDisplays():
                vList = []
                for v in self.config.getViews(d):
                    vList.append(
                        (
                            v,
                            ocioDisplayEvent(display, d, v),
                            None,
                            ocioDisplayMenuCheck(display, d, v),
                        )
                    )
                dList.append((d, vList))
            device = "  " + commands.getStringProperty(display + ".device.name")[0] + ": " + displayOCIOValue(display)
            daList.append((device, dList))

        #
        #   Apply file space changes only to the visible source
        #

        cssList = [
            (
                "Active",
                self.ocioActiveEvent("OCIOFile"),
                None,
                isOCIOManaged("OCIOFile"),
            ),
            ("_", None),
        ]
        csaList = []

        def addPath(family, tree):
            for f in family:
                for t in tree:
                    if f in t:
                        return addPath(family[1:], t)
                tree.append([f])
                return addPath(family, tree)

        families = [(cs.getFamily().split("/") + [cs.getName()]) for cs in self.config.getColorSpaces()]
        root = []
        for family in families:
            addPath(family, root)

        def addMenu(root, isSingle):
            if len(root) == 1:
                name = root[0]
                if isSingle:
                    OCIO_DEFAULTS.setdefault("OCIOFile", name)
                    return [
                        (
                            name,
                            ocioEvent("OCIOFile", "ocio.inColorSpace", name),
                            None,
                            ocioMenuCheck("OCIOFile", "ocio.inColorSpace", name),
                        )
                    ]
                else:
                    return [
                        (
                            name,
                            ocioEventOnAllOfType("OCIOFile", "ocio.inColorSpace", name),
                            None,
                            ocioMenuCheck("OCIOFile", "ocio.inColorSpace", name),
                        )
                    ]
            else:
                menu = []
                for r in root[1:]:
                    menu += addMenu(r, isSingle)
                return [(root[0], menu)]

        for r in root:
            cssList += addMenu(r, True)
            csaList += addMenu(r, False)

        #
        #   Apply file look changes only to the visible source
        #

        lsList = [
            (
                "Active",
                self.ocioActiveEvent("OCIOLook"),
                None,
                isOCIOManaged("OCIOLook"),
            ),
            ("_", None),
        ]
        laList = []
        for look in self.config.getLooks():
            OCIO_DEFAULTS.setdefault("OCIOLook", look.getName())
            lsList.append(
                (
                    look.getName(),
                    ocioEvent("OCIOLook", "ocio_look.look", look.getName()),
                    None,
                    ocioMenuCheck("OCIOLook", "ocio_look.look", look.getName()),
                )
            )
            laList.append(
                (
                    look.getName(),
                    ocioEventOnAllOfType("OCIOLook", "ocio_look.look", look.getName()),
                    None,
                    ocioMenuCheck("OCIOLook", "ocio_look.look", look.getName()),
                )
            )

        #
        #   Show what is applied in the submenu titles, so the user doesn't
        #   have to look for check marks.
        #

        currentFile = currentSourceOCIOValue("OCIOFile", "ocio.inColorSpace")
        currentLook = currentSourceOCIOValue("OCIOLook", "ocio_look.look", NO_LOOK)
        self.menuSourceState = (currentFile, currentLook)

        final = [
            ("Current Source", None, None, lambda: commands.DisabledMenuState),
            ("  File Color Space: " + currentFile, cssList),
        ]
        if len(lsList) > 2:
            final += [("  Look: " + currentLook, lsList)]
        final += [
            ("All Sources", None, None, lambda: commands.DisabledMenuState),
            ("  File Color Space: " + allSourcesOCIOValue("OCIOFile", "ocio.inColorSpace"), csaList),
        ]
        if len(laList) > 0:
            final += [("  Look: " + allSourcesOCIOValue("OCIOLook", "ocio_look.look", NO_LOOK), laList)]
        final += [
            ("_", None),
            ("Displays", None, None, lambda: commands.DisabledMenuState),
        ]
        final += daList
        final += [("_", None)]
        final += [("Change Config...", self.selectConfig, None, None)]

        return [("OCIO", final)]

    def __init__(self):
        rvtypes.MinorMode.__init__(self)

        self.usingOCIOForDisplay = {}
        self.readingSession = False
        self.config = None
        self.autoInputSources = {}
        self.autoViews = {}
        self.videoSyncPending = False
        self.builtInProperties = {}
        self.menuUpdatePending = False
        self.menuSourceState = None

        #
        #   Look for an implementation of the OCIOHelper on the PATH.
        #   Use the default if the import failed.
        #

        try:
            import rv_ocio_setup

            inherited = []
            for method in METHODS:
                try:
                    exec("global %s; %s = rv_ocio_setup.%s" % (method, method, method))
                    inherited.append(method)
                except AttributeError:
                    pass

            print(("INFO: Using %s for OCIO setup methods: %s" % (rv_ocio_setup.__file__, " ".join(inherited))))

        except ImportError:
            pass

        # Resolve OCIO config: externally set $OCIO takes precedence,
        # otherwise find bundled/saved config or download latest ACES 2.0 release.
        config_path = ensure_ocio_config()
        if config_path and os.path.isfile(config_path):
            try:
                self.config = OCIO.Config.CreateFromFile(config_path)
                OCIO.SetCurrentConfig(self.config)
            except Exception as e:
                print(f"ERROR: Failed to load OCIO config from {config_path}: {e}")

        self.init(
            "OCIO Source Setup",
            None,
            [
                (
                    "source-group-complete",
                    self.sourceSetup,
                    "Color and Geometry Management",
                ),
                ("before-session-read", self.beforeSessionRead, ""),
                ("after-session-read", self.afterSessionRead, ""),
                ("graph-new-node", self.checkForDisplayGroup, ""),
                ("graph-node-inputs-changed", self.checkForDisplayGroup, ""),
                ("graph-state-change", self.maybeUpdateViews, ""),
                ("after-graph-view-change", self.scheduleMenuUpdate, ""),
                ("frame-changed", self.updateMenuForCurrentSource, ""),
                ("play-stop", self.updateMenuForCurrentSource, ""),
            ],
            self.buildOCIOMenu(),
            "source_setup",
            10,
        )  # source_setup key used by source_setup and this mode


#
#   Dynamically looked up by the mode manager to create this mode. The name
#   matters
#

_theMode = None


def theMode():
    global _theMode
    return _theMode


def createMode():
    global _theMode
    _theMode = OCIOSourceSetupMode()
    return _theMode
