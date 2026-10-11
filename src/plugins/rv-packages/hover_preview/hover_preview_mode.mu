//
// Copyright (c) 2026 Seth Rosenthal.
//
// SPDX-License-Identifier: Apache-2.0
//
module: hover_preview_mode {
use rvtypes;
use commands;
use extra_commands;
require timeline;

//
//  Timeline hover preview. While the mouse is over the timeline, this mode
//  asks UTV to show a preview of the frame under it by sending the internal
//  event "hover-preview-show" with "frame|x|y|label", and
//  "hover-preview-clear" to hide it. x and y are where the preview's arrow
//  points, in framebuffer pixels. UTV renders the frame and draws the
//  panel (see RvDocument::showHoverPreview()).
//
//  NOTE: the timeline has no formal API for its geometry, so this mode
//  uses these members of timeline.Timeline (timeline.mu): isActive(),
//  contains(), renderLocations() (the w, hm0 and hm1 fields),
//  frameAtPointer(), sourceAtFrame(), _drag and _Ytop. Changes to them in
//  timeline.mu need matching changes here.
//

class: HoverPreviewMode : MinorMode
{
    string _mode; // "off", "paused" or "always"
    bool   _shown;
    int    _frame;
    float  _x;     // where the arrow points, as last sent
    float  _y;

    method: clear (void;)
    {
        if (_shown)
        {
            sendInternalEvent("hover-preview-clear", "", "hover_preview");
            _shown = false;
        }
    }

    method: allowed (bool;)
    {
        _mode == "always" || (_mode == "paused" && !isPlaying());
    }

    method: update (void; Event event, timeline.Timeline tl)
    {
        //
        //  Hidden while scrubbing: the viewer already shows that frame.
        //

        if (tl eq nil || !tl.isActive() || tl._drag || !tl.contains(event.pointer()) || !allowed())
        {
            clear();
            return;
        }

        let loc   = tl.renderLocations(event),
            frame = tl.frameAtPointer(loc, event),
            fs    = frameStart(),
            fe    = frameEnd();

        if (frame < fs || frame > fe)
        {
            clear();
            return;
        }

        //
        //  The arrow points at the middle of the frame on the timeline, so
        //  it stops at the timeline's ends, and just above the frame number
        //  the timeline draws over the pointer. Pointer events measure the
        //  timeline in points; _Ytop is in device pixels, since it is set
        //  when the timeline renders.
        //

        State state = data();
        let {d, w, h, drawControls, tlh, mxb, hm0, hm1, thm1, vm0, vm1, t, Y} = loc,
            dpr = devicePixelRatio(),
            x   = (hm0 + (frame - fs + 0.5) / float(fe - fs + 1) * (w - hm1 - hm0)) * dpr,
            y   = tl._Ytop + (state.config.tlFrameTextSize + 3.0 / dpr + 4.0) * dpr;

        //
        //  Send only when something changed: the frame, or where the arrow
        //  points (the timeline can move while the pointer stays on one
        //  frame, e.g. when the window is resized).
        //

        if (_shown && frame == _frame && x == _x && y == _y) return;

        sendInternalEvent("hover-preview-show",
                          "%d|%g|%g|%s" % (frame, x, y, tl.sourceAtFrame(frame)),
                          "hover_preview");
        _shown = true;
        _frame = frame;
        _x     = x;
        _y     = y;
    }

    method: pointerMove (void; Event event)
    {
        event.reject();

        if (_mode != "off")
        {
            State state = data();
            update(event, state.timeline);
        }
    }

    method: hidePreview (void; Event event)
    {
        event.reject();
        clear();
    }

    method: previewHidden (void; Event event)
    {
        event.reject();
        //  The view resized and C++ hid the preview immediately. Its old
        //  position is invalid, so the next hover must send a fresh show.
        _shown = false;
    }

    method: deactivate (void;)
    {
        //
        //  Don't leave a preview on screen when the mode is turned off.
        //

        clear();
    }

    method: playStart (void; Event event)
    {
        event.reject();
        if (!allowed()) clear();
    }

    method: setMode (void; string mode, Event event)
    {
        _mode = mode;
        writeSetting("HoverPreview", "mode", SettingsValue.String(mode));
        if (!allowed()) clear();
    }

    method: modeState ((int;); string mode)
    {
        \: (int;)
        {
            if this._mode == mode then CheckedMenuState else UncheckedMenuState;
        };
    }

    method: HoverPreviewMode (HoverPreviewMode; string name)
    {
        //
        //  Ordered before the timeline (which has the default ordering of
        //  0 and accepts button presses), so the preview can hide when a
        //  scrub starts. Every handler rejects its event, so the timeline
        //  and other modes still receive it.
        //

        init(name,
             [("pointer--move", pointerMove, "Show the hover preview over the timeline"),
              ("pointer--leave", hidePreview, "Hide the hover preview"),
              ("hover-preview-hidden", previewHidden, "Reset the hover preview after a view resize"),
              ("pointer-1--push", hidePreview, "Hide the hover preview while scrubbing"),
              ("play-start", playStart, "Hide the hover preview during playback")],
             nil,
             Menu {
                 {"View", Menu {
                         {"Hover Preview", Menu {
                                 {"Off", setMode("off",), nil, modeState("off")},
                                 {"When Paused", setMode("paused",), nil, modeState("paused")},
                                 {"Always", setMode("always",), nil, modeState("always")}
                             }
                         }
                     }
                 }
             },
             nil,
             -1);

        let SettingsValue.String m = readSetting("HoverPreview", "mode", SettingsValue.String("paused"));

        _mode  = m;
        _shown = false;
        _frame = 0;
        _x     = 0.0;
        _y     = 0.0;
    }
}

\: createMode (Mode;)
{
    return HoverPreviewMode("hover-preview");
}
}
