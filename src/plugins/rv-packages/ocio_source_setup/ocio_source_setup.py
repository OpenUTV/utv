#
# Copyright (C) 2023  Autodesk, Inc. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#
from rv import rvtypes, commands, extra_commands as rve
import os
import urllib.request
import PyOpenColorIO as OCIO

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


def isAutoSetupACES():
    try:
        val = commands.readSettings("General", "autoSetupACES", "")
        if val != "":
            return bool(int(val))
        val2 = commands.readSettings("OCIO", "auto_setup_aces", "")
        if val2 != "":
            return bool(int(val2))
    except Exception:
        pass
    return False


def get_aces_linear_colorspace(config):
    if config is None:
        return "ACEScg"
    try:
        cs = config.getColorSpace("ACEScg")
        if cs:
            return "ACEScg"
    except Exception:
        pass
    try:
        cs = config.getColorSpace(OCIO.ROLE_SCENE_LINEAR)
        if cs:
            return cs.getName()
    except Exception:
        pass
    try:
        for cs in config.getColorSpaces():
            if "acescg" in cs.getName().lower():
                return cs.getName()
    except Exception:
        pass
    return "ACEScg"


def get_aces_srgb_display(config):
    if config is None:
        return ""
    displays = list(config.getDisplays())
    for d in displays:
        if d.lower() in ("srgb - display", "srgb", "srgb display"):
            return d
    for d in displays:
        if "srgb" in d.lower():
            return d
    return config.getDefaultDisplay()


def get_aces_srgb_view(config, display):
    if config is None or not display:
        return ""
    views = list(config.getViews(display))
    for v in views:
        vl = v.lower()
        if "sdr" in vl and "rec.709" in vl and "d60" not in vl:
            return v
    for v in views:
        vl = v.lower()
        if "sdr video" in vl or "sdr-video" in vl:
            return v
    for v in views:
        if v.lower() in ("srgb", "rec.709", "rec709"):
            return v
    return config.getDefaultView(display)


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
        if isAutoSetupACES():
            display = get_aces_srgb_display(config)
            view = get_aces_srgb_view(config, display)
        else:
            display = config.getDefaultDisplay()
            view = config.getDefaultView(display)

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
        if inspace == "" and isAutoSetupACES():
            inspace = get_aces_linear_colorspace(config)

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
        commands.redraw()

    return F


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
        commands.redraw()

    def useDisplayOCIO(self, group):
        """
        This installs the OCIODisplay node in the DisplayGroup's display pipeline
        in place of RV's RVDisplayColor node.

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
            pipelineList = ocio_node_from_media(self.config, dpipeline, DEFAULT_PIPE[groupName])
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
        commands.setStringProperty(dpipeline + ".pipeline.nodes", pipeline, True)

        pipeNodes = commands.nodesInGroup(dpipeline)
        pipeNodes.sort()
        for index, pNode in enumerate(pipelineList):
            stageOCIO = pipeNodes[index]
            try:
                applyProps(stageOCIO, pNode["context"], pNode["properties"])
            except KeyError as inst:
                print(("ERROR: Unable to apply properties to %s: %s" % (stageOCIO, inst)))

        self.usingOCIOForDisplay[group] = True
        commands.redraw()

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

        device = commands.getStringProperty(group + ".device.name")[0]
        print(("INFO: using RVDisplayColor for display: %s" % device))

        self.usingOCIOForDisplay[group] = False
        commands.redraw()

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

        #
        #   If this is the first OCIO color pipeline for a source assume
        #   that we also want to use OCIO for display. In this case we're
        #   just going to assume the defaults
        #

        if len(commands.nodesOfType("OCIOFile")) >= 1 or isAutoSetupACES():
            for group in commands.nodesOfType("RVDisplayGroup"):
                if not self.usingOCIOForDisplay.get(group, False):
                    self.useDisplayOCIO(group)

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
        if event.contents().endswith("ocio_display.display"):
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
            device = "  " + commands.getStringProperty(display + ".device.name")[0]
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

        acesList = [
            (
                "Auto-Setup ACES (ACEScg -> sRGB)",
                self.toggleAutoSetupACES,
                None,
                self.isAutoSetupACESCheck,
            ),
            (
                "Apply ACES Setup Now",
                self.applyACESNow,
                None,
                None,
            ),
            ("_", None),
        ]

        final = acesList + [
            ("Current Source", None, None, lambda: commands.DisabledMenuState),
            ("  File Color Space", cssList),
        ]
        if len(lsList) > 2:
            final += [("  Look", lsList)]
        final += [
            ("All Sources", None, None, lambda: commands.DisabledMenuState),
            ("  File Color Space", csaList),
        ]
        if len(laList) > 0:
            final += [("  Look", laList)]
        final += [
            ("_", None),
            ("Displays", None, None, lambda: commands.DisabledMenuState),
        ]
        final += daList
        final += [("_", None)]
        final += [("Change Config...", self.selectConfig, None, None)]

        return [("OCIO", final)]

    def toggleAutoSetupACES(self, event=None):
        new_state = not isAutoSetupACES()
        commands.writeSettings("General", "autoSetupACES", int(new_state))
        commands.writeSettings("OCIO", "auto_setup_aces", int(new_state))
        if new_state:
            self.applyACESSetup()
        else:
            rve.displayFeedback("Auto-Setup ACES: Disabled", 2.0)
        commands.defineModeMenu("OCIO Source Setup", self.buildOCIOMenu(), True)

    def isAutoSetupACESCheck(self):
        return commands.CheckedMenuState if isAutoSetupACES() else commands.UncheckedMenuState

    def applyACESNow(self, event=None):
        self.applyACESSetup()

    def applyACESSetup(self):
        if self.config is None:
            cfg_path = ensure_ocio_config()
            if cfg_path and os.path.isfile(cfg_path):
                self.config = OCIO.Config.CreateFromFile(cfg_path)
                OCIO.SetCurrentConfig(self.config)

        if self.config is None:
            print("ERROR: Cannot apply ACES setup without a valid OCIO config")
            return

        inspace = get_aces_linear_colorspace(self.config)
        target_disp = get_aces_srgb_display(self.config)
        target_view = get_aces_srgb_view(self.config, target_disp)

        # 1. Update active sources to use OCIOFile with inspace
        for src in commands.nodesOfType("RVFileSource") + commands.nodesOfType("RVImageSource"):
            self.useSourceOCIO(src, "OCIOFile", inspace)
            src_group = commands.nodeGroup(src)
            for n in commands.nodesInGroup(src_group):
                if commands.nodeType(n) == "RVLinearizePipelineGroup":
                    for pn in commands.nodesInGroup(n):
                        if commands.nodeType(pn) == "OCIOFile":
                            commands.setStringProperty(f"{pn}.ocio.inColorSpace", [inspace], True)
                            commands.setStringProperty(f"{pn}.ocio_color.outColorSpace", [OCIO.ROLE_SCENE_LINEAR], True)
                            commands.setIntProperty(f"{pn}.ocio.active", [1], True)

        # 2. Update active displays to use OCIODisplay with target_disp and target_view
        for dg in commands.nodesOfType("RVDisplayGroup"):
            self.useDisplayOCIO(dg)
            for n in commands.nodesInGroup(dg):
                if commands.nodeType(n) == "RVDisplayPipelineGroup":
                    for pn in commands.nodesInGroup(n):
                        if commands.nodeType(pn) == "OCIODisplay":
                            commands.setIntProperty(f"{pn}.ocio.active", [0], True)
                            commands.setStringProperty(f"{pn}.ocio_display.display", [target_disp], True)
                            commands.setStringProperty(f"{pn}.ocio_display.view", [target_view], True)
                            commands.setIntProperty(f"{pn}.ocio.active", [1], True)

        commands.redraw()
        rve.displayFeedback(f"ACES Setup: {inspace} -> {target_disp} ({target_view})", 3.0)

    def __init__(self):
        rvtypes.MinorMode.__init__(self)

        self.usingOCIOForDisplay = {}
        self.readingSession = False
        self.config = None

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
