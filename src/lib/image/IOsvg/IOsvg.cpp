//
// Copyright (C) 2026  Makai Systems. All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//
#include <IOsvg/IOsvg.h>
#include <TwkFB/Exception.h>
#include <cmath>
#include <iostream>
#include <sstream>

#define NANOSVG_IMPLEMENTATION
#include <IOsvg/nanosvg.h>
#define NANOSVGRAST_IMPLEMENTATION
#include <IOsvg/nanosvgrast.h>

namespace TwkFB
{
    using namespace std;

    IOsvg::IOsvg()
        : FrameBufferIO("IOsvg", "m4")
    {
        unsigned int cap = ImageRead;
        StringPairVector codecs;
        addType("svg", "Scalable Vector Graphics", cap, codecs);
    }

    IOsvg::~IOsvg() {}

    string IOsvg::about() const { return "Scalable Vector Graphics (NanoSVG)"; }

    void IOsvg::getImageInfo(const string& filename, FBInfo& fbi) const
    {
        NSVGimage* g = nsvgParseFromFile(filename.c_str(), "px", 96.0f);
        if (!g || !g->shapes)
        {
            if (g)
                nsvgDelete(g);
            TWK_THROW_STREAM(IOException, "IOsvg: failed to parse SVG file or no shapes found: " << filename);
        }

        int w = (int)ceilf(g->width);
        int h = (int)ceilf(g->height);
        if (w <= 0)
            w = 1920;
        if (h <= 0)
            h = 1080;

        nsvgDelete(g);

        fbi.dataType = FrameBuffer::UCHAR;
        fbi.width = w;
        fbi.height = h;
        fbi.numChannels = 4;
        fbi.orientation = FrameBuffer::TOPLEFT;

        fbi.proxy.setPrimaryColorSpace(ColorSpace::sRGB());
        fbi.proxy.setTransferFunction(ColorSpace::sRGB());
    }

    void IOsvg::readImage(FrameBuffer& fb, const string& filename, const ReadRequest& request) const
    {
        NSVGimage* g = nsvgParseFromFile(filename.c_str(), "px", 96.0f);
        if (!g)
        {
            TWK_THROW_STREAM(IOException, "IOsvg: failed to parse SVG file: " << filename);
        }

        int w = (int)ceilf(g->width);
        int h = (int)ceilf(g->height);
        if (w <= 0)
            w = 1920;
        if (h <= 0)
            h = 1080;

        NSVGrasterizer* rast = nsvgCreateRasterizer();
        if (!rast)
        {
            nsvgDelete(g);
            TWK_THROW_STREAM(IOException, "IOsvg: failed to create SVG rasterizer for " << filename);
        }

        fb.restructure(w, h, 0, 4, FrameBuffer::UCHAR);
        fb.setOrientation(FrameBuffer::TOPLEFT);

        nsvgRasterize(rast, g, 0.0f, 0.0f, 1.0f, fb.pixels<unsigned char>(), w, h, w * 4);

        nsvgDeleteRasterizer(rast);
        nsvgDelete(g);

        fb.setPrimaryColorSpace(ColorSpace::sRGB());
        fb.setTransferFunction(ColorSpace::sRGB());
    }

} // namespace TwkFB
