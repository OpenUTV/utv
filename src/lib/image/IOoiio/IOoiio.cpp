//******************************************************************************
// Copyright (c) 2001-2004 Tweak Inc. All rights reserved.
//
// SPDX-License-Identifier: Apache-2.0
//
//******************************************************************************
#include <OpenImageIO/imageio.h>
#include <IOoiio/IOoiio.h>
#include <TwkFB/Exception.h>
#include <TwkFB/Operations.h>
#include <TwkUtil/ByteSwap.h>
#include <TwkUtil/File.h>
#include <half.h>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <random>
#include <set>
#include <string>
#include <sstream>

namespace TwkFB
{
    using namespace std;
    using namespace TwkUtil;
#ifdef RV_VFX_CY2023
    using namespace OpenImageIO_v2_5;
#else
    using namespace OpenImageIO;
#endif

    //
    //  OIIO lists heif as an output format whenever it was built with libheif,
    //  but libheif encodes through codec plugins that may not be there: OpenUTV
    //  ships no HEVC encoder (x265), see AGENTS.md 1.4. Encode a small image to
    //  find out whether writing this extension really works on this machine.
    //
    static bool canEncode(const string& ext)
    {
        namespace fs = std::filesystem;

        std::error_code ec;
        const fs::path dir = fs::temp_directory_path(ec);
        if (ec)
            return false;

        ostringstream name;
        name << "utv_oiio_probe_" << std::random_device()() << "." << ext;
        const string path = (dir / name.str()).string();

        bool ok = false;
        try
        {
            if (auto out = ImageOutput::create(path))
            {
                const int size = 64;
                const vector<unsigned char> pixels(size * size * 3, 128);
                const ImageSpec spec(size, size, 3, TypeDesc::UINT8);
                ok = out->open(path, spec);
                ok = ok && out->write_image(TypeDesc::UINT8, pixels.data());
                ok = out->close() && ok;
            }
        }
        catch (...)
        {
            ok = false;
        }

        // Clear OIIO's per-thread error so a failed probe is not reported by a later call.
        (void)OIIO::geterror();
        fs::remove(path, ec);
        return ok;
    }

    IOoiio::IOoiio()
        : FrameBufferIO("IOoiio", "m3") // Modern hardened OpenImageIO prioritized over legacy bespoke parsers
    {
        StringPairVector codecs;
        unsigned int r = ImageRead;
        unsigned int w = ImageWrite;

        //
        //  Only advertise Write for extensions whose OIIO format actually has an
        //  output plugin in this OIIO build (e.g. Homebrew's OIIO has no QOI
        //  writer). Otherwise GenericIO would route writes here and fail.
        //
        set<string> writableExts;
        {
            set<string> outputFormats;
            for (const auto& name : Strutil::splits(get_string_attribute("output_format_list"), ","))
                outputFormats.insert(name);

            for (const auto& entry : get_extension_map())
            {
                if (outputFormats.count(entry.first))
                {
                    for (const auto& ext : entry.second)
                        writableExts.insert(Strutil::lower(ext));
                }
            }
        }

        auto rw = [&](const char* ext) { return writableExts.count(ext) ? (r | w) : r; };

        //
        //  HEIC/HEIF (HEVC) and AVIF (AV1) need an encoder that libheif may not have.
        //  On macOS, HEIC is written by the ImageIO plugin (IONSImage) with Apple's
        //  encoder, so it is read-only here.
        //
#if defined(PLATFORM_DARWIN)
        const bool heicWritable = false;
#else
        const bool heicWritable = writableExts.count("heic") && canEncode("heic");
#endif
        const bool avifWritable = writableExts.count("avif") && canEncode("avif");

        // Dedicated native writer plugins handle the following formats with custom streaming pipelines:
        // IOpng ("m9"), IOdpx ("m5"), IOcin ("z_cin"), IOjpeg ("m2"), IOtarga ("z_targa"), IOrla ("z_rla"), IOrgbe ("z_rgbe").
        // These MUST be registered as Read-only in IOoiio so write requests route directly to their native writers.
        addType("png", "Portable Network Graphics Image", r, codecs);
        addType("dpx", "SMPTE DPX", r, codecs);
        addType("cin", "Kodak Cineon", r, codecs);
        addType("cineon", "Kodak Cineon", r, codecs);
        addType("jpg", "JPEG image", r, codecs);
        addType("jpeg", "JPEG image", r, codecs);
        addType("tga", "TARGA", r, codecs);
        addType("targa", "TARGA", r, codecs);
        addType("rla", "Wavefront RLA", r, codecs);
        addType("hdr", "Radiance HDR", r, codecs);
        addType("rgbe", "Radiance HDR", r, codecs);

        // Read-only formats
        addType("psd", "Adobe Photoshop", r, codecs);
        addType("pic", "Softimage PIC", r, codecs);
        addType("ptex", "Disney PTex", r, codecs);
        addType("ptx", "Disney PTex", r, codecs);
        addType("gif", "Graphics Interchange Format", r, codecs);
        addType("ico", "Palette", r, codecs);
        addType("z", "Pixar Z-Depth", r, codecs);

        // Formats written via OpenImageIO (no dedicated native writer plugin)
        addType("webp", "Google WebP", rw("webp"), codecs);
        addType("qoi", "Quite OK Image", rw("qoi"), codecs);
        addType("bmp", "Windows Bitmap", rw("bmp"), codecs);
        addType("sgi", "SGI image", rw("sgi"), codecs);
        addType("bw", "SGI image", rw("bw"), codecs);
        addType("rgb", "SGI image", rw("rgb"), codecs);
        addType("rgba", "SGI image", rw("rgba"), codecs);
        addType("inta", "SGI image", rw("inta"), codecs);
        addType("int", "SGI image", rw("int"), codecs);
        addType("pnm", "PNM", rw("pnm"), codecs);
        addType("pbm", "Portable Network Graphics", rw("pbm"), codecs);
        addType("pgm", "Portable Network Graphics", rw("pgm"), codecs);
        addType("ppm", "Portable Network Grapics", rw("ppm"), codecs);
        addType("fits", "FITS", rw("fits"), codecs);
        addType("iff", "IFF", rw("iff"), codecs);
        addType("dds", "Direct Draw Surface", rw("dds"), codecs);
        addType("heic", "High Efficiency Image File", heicWritable ? (r | w) : r, codecs);
        addType("heif", "High Efficiency Image File", heicWritable ? (r | w) : r, codecs);
        addType("hif", "High Efficiency Image File", heicWritable ? (r | w) : r, codecs);
        addType("avif", "AV1 Image File", avifWritable ? (r | w) : r, codecs);
        addType("jxl", "JPEG XL Image", rw("jxl"), codecs);

        // These are handled by their dedicated optimized streaming plugins:
        // IOexr ("m0"), IOtiff ("m1"), IOjpeg ("m2"), IOhtj2k ("m7")
        // addType("tif", "TIFF Image", rw, codecs);
        // addType("tiff", "TIFF Image", rw, codecs);
        // addType("j2c", "JPEG-2000 Codestream", r, codecs);
        // addType("j2k", "JPEG-2000 Codestream", r, codecs);
        // addType("jpt", "JPT-stream (JPEG 2000, JPIP)", r, codecs);
        // addType("jp2", "JPEG-2000 Image", r, codecs);
    }

    IOoiio::~IOoiio() {}

    string IOoiio::about() const
    {
        ostringstream str;
        str << "OpenImageIO: " << OIIO_VERSION_MAJOR << "." << OIIO_VERSION_MINOR << "." << OIIO_VERSION_PATCH;

        return str.str();
    }

    static void readAttrs(TwkFB::FrameBuffer& fb, ImageSpec& spec)
    {
        for (size_t i = 0, s = spec.extra_attribs.size(); i != s; i++)
        {
            const ParamValue& value = spec.extra_attribs[i];
            const TypeDesc type = value.type();
            const string name = value.name().string();

            if (name == "ICCProfile")
            {
                fb.setICCprofile(value.data(), type.size());
                fb.setPrimaryColorSpace(ColorSpace::ICCProfile());
                fb.setTransferFunction(ColorSpace::ICCProfile());
                continue;
            }

            // Extract human-readable string for any metadata type (EXIF, IPTC, XMP, arrays, rationals)
            string strVal = ImageSpec::metadata_val(value, true);
            if (!strVal.empty())
            {
                fb.newAttribute<string>(name, strVal);
            }

            // Also preserve typed numeric attributes for scalar numbers
            if (value.nvalues() == 1)
            {
                if (type.basetype == TypeDesc::INT32 || type.basetype == TypeDesc::UINT32 || type.basetype == TypeDesc::INT16
                    || type.basetype == TypeDesc::UINT16)
                {
                    fb.newAttribute<int>(name, value.get_int());
                }
                else if (type.basetype == TypeDesc::FLOAT)
                {
                    fb.newAttribute<float>(name, value.get_float());
                }
                else if (type.basetype == TypeDesc::DOUBLE)
                {
                    fb.newAttribute<double>(name, *(const double*)value.data());
                }
            }
        }

        fb.newAttribute<string>("Reader", "OpenImageIO");
    }

    static bool subimagesAsLayers(const string& fname) { return fname == "psd"; }

    static bool premultedAlpha(const string& fname) { return fname != "psd"; }

    void IOoiio::getImageInfo(const std::string& filename, FBInfo& fbi) const
    {
        string ext = extension(filename);

#if 0
    if (ext == "dpx" || ext == "cin" || ext == "cineon" || ext == "DPX" || ext == "CIN")
    {
        TWK_THROW_STREAM(IOException, "OIIO: Unable to open file \"" 
                         << filename << "\" for reading");
    }
#endif

        if (std::unique_ptr<ImageInput> in = ImageInput::create(filename))
        {
            ImageSpec spec;
            in->open(filename, spec);
            bool useLayers = subimagesAsLayers(in->format_name());

            fbi.width = spec.width;
            fbi.height = spec.height;
            fbi.numChannels = spec.nchannels;
            FrameBuffer::DataType dtype;

            switch (spec.format.basetype)
            {
            case TypeDesc::UNKNOWN:
            case TypeDesc::NONE:
            case TypeDesc::INT64:
            case TypeDesc::UINT64:
                break;
            case TypeDesc::UINT8:
            case TypeDesc::INT8:
                dtype = FrameBuffer::UCHAR;
                break;
            case TypeDesc::UINT16:
            case TypeDesc::INT16:
                dtype = FrameBuffer::USHORT;
                break;
            case TypeDesc::UINT32:
            case TypeDesc::INT32:
                dtype = FrameBuffer::UINT;
                break;
            case TypeDesc::HALF:
                dtype = FrameBuffer::HALF;
                break;
            case TypeDesc::FLOAT:
                dtype = FrameBuffer::FLOAT;
                break;
            case TypeDesc::DOUBLE:
                dtype = FrameBuffer::DOUBLE;
                break;
            }

            fbi.dataType = dtype;

            FrameBuffer::Orientation orientation;

            switch (spec.get_int_attribute("Orientation", 1))
            {
            case 5:
            case 1:
                orientation = FrameBuffer::TOPLEFT;
                break;
            case 6:
            case 2:
                orientation = FrameBuffer::TOPRIGHT;
                break;
            case 7:
            case 3:
                orientation = FrameBuffer::BOTTOMRIGHT;
                break;
            case 8:
            case 4:
                orientation = FrameBuffer::NATURAL;
                break;
            }

            for (int c = 0; c < spec.nchannels; c++)
            {
                FBInfo::ChannelInfo cinfo;
                cinfo.name = spec.channelnames[c];
                cinfo.type = fbi.dataType;
                fbi.channelInfos.push_back(cinfo);
            }

            fbi.orientation = orientation;

            fbi.proxy.attribute<string>("AlphaType") = premultedAlpha(in->format_name()) ? "Premultiplied" : "Unpremultiplied";

            readAttrs(fbi.proxy, spec);

            size_t nsubimages = 1;
            ImageSpec subspec;
            while (in->seek_subimage(nsubimages, 0, subspec))
                nsubimages++;

            if (nsubimages > 1)
            {
                for (size_t i = 0; i < nsubimages; i++)
                {
                    FBInfo::ViewInfo vinfo;
                    FBInfo::LayerInfo linfo;
                    ostringstream str;

                    if (useLayers)
                    {
                        str << "Layer " << i;
                        fbi.layers.push_back(str.str());
                        fbi.viewInfos.resize(1);
                        linfo.name = str.str();
                        vinfo.name = "";
                    }
                    else
                    {
                        str << "View " << i;
                        fbi.views.push_back(str.str());
                        vinfo.name = str.str();
                    }

                    for (size_t q = 0; q < subspec.channelnames.size(); q++)
                    {
                        FBInfo::ChannelInfo cinfo;
                        cinfo.name = subspec.channelnames[q];

                        if (subspec.channelformats.size() == subspec.channelnames.size())
                        {
                            switch (subspec.channelformats[q].basetype)
                            {
                            case TypeDesc::UNKNOWN:
                            case TypeDesc::NONE:
                            case TypeDesc::INT64:
                            case TypeDesc::UINT64:
                                break;
                            case TypeDesc::UINT8:
                            case TypeDesc::INT8:
                                cinfo.type = FrameBuffer::UCHAR;
                                break;
                            case TypeDesc::UINT16:
                            case TypeDesc::INT16:
                                cinfo.type = FrameBuffer::USHORT;
                                break;
                            case TypeDesc::UINT32:
                            case TypeDesc::INT32:
                                cinfo.type = FrameBuffer::UINT;
                                break;
                            case TypeDesc::HALF:
                                cinfo.type = FrameBuffer::HALF;
                                break;
                            case TypeDesc::FLOAT:
                                cinfo.type = FrameBuffer::FLOAT;
                                break;
                            case TypeDesc::DOUBLE:
                                cinfo.type = FrameBuffer::DOUBLE;
                                break;
                            }
                        }
                        else
                        {
                            cinfo.type = fbi.dataType;
                        }

                        if (useLayers)
                            linfo.channels.push_back(cinfo);
                        else
                            vinfo.otherChannels.push_back(cinfo);
                    }

                    if (useLayers)
                        fbi.viewInfos.front().layers.push_back(linfo);
                    else
                        fbi.viewInfos.push_back(vinfo);
                }
            }
        }
        else
        {
            TWK_THROW_STREAM(IOException, "OIIO: Unable to open file \"" << filename << "\" for reading. " << geterror());
        }
    }

    void IOoiio::readImage(FrameBuffer& fb, const std::string& filename, const ReadRequest& request) const
    {
        if (std::unique_ptr<ImageInput> in = ImageInput::create(filename))
        {
            bool useLayers = subimagesAsLayers(in->format_name());

            ImageSpec spec;
            int subimage = 0;
            in->open(filename, spec);

            if (useLayers)
            {
                if (request.layers.size())
                {
                    sscanf(request.layers[0].c_str(), "Layer %d", &subimage);
                    if (!in->seek_subimage(subimage, 0, spec))
                    {
                        TWK_THROW_STREAM(IOException, "OIIO: failed to find subimage " << subimage);
                    }
                }
            }
            else if (request.views.size())
            {
                sscanf(request.views[0].c_str(), "View %d", &subimage);
                if (!in->seek_subimage(subimage, 0, spec))
                {
                    TWK_THROW_STREAM(IOException, "OIIO: failed to find subimage " << subimage);
                }
            }

            FrameBuffer::DataType dtype;
            TypeDesc::BASETYPE informat = (TypeDesc::BASETYPE)spec.format.basetype;

            switch (spec.format.basetype)
            {
            case TypeDesc::UNKNOWN:
            case TypeDesc::NONE:
                dtype = FrameBuffer::UCHAR;
                break;
            case TypeDesc::UINT8:
            case TypeDesc::INT8:
                dtype = FrameBuffer::UCHAR;
                break;
            case TypeDesc::UINT16:
            case TypeDesc::INT16:
                dtype = FrameBuffer::USHORT;
                break;
            case TypeDesc::UINT32:
            case TypeDesc::INT32:
            case TypeDesc::INT64:
            case TypeDesc::UINT64:
                dtype = FrameBuffer::UINT;
                informat = TypeDesc::UINT32;
                break;
            case TypeDesc::HALF:
                dtype = FrameBuffer::HALF;
                break;
            case TypeDesc::DOUBLE:
            case TypeDesc::FLOAT:
                dtype = FrameBuffer::FLOAT;
                break;
            }

            FrameBuffer::Orientation orientation;

            switch (spec.get_int_attribute("Orientation", 1))
            {
            case 5:
            case 1:
                orientation = FrameBuffer::TOPLEFT;
                break;
            case 6:
            case 2:
                orientation = FrameBuffer::TOPRIGHT;
                break;
            case 7:
            case 3:
                orientation = FrameBuffer::BOTTOMRIGHT;
                break;
            case 8:
            case 4:
                orientation = FrameBuffer::NATURAL;
                break;
            }

            fb.restructure(spec.width, spec.height, spec.depth, spec.nchannels, dtype, NULL, &spec.channelnames, orientation, true);

            in->read_image(subimage, 0, 0, spec.nchannels, informat, fb.pixels<void>());

            readAttrs(fb, spec);

            fb.attribute<string>("AlphaType") = premultedAlpha(in->format_name()) ? "Premultiplied" : "Unpremultiplied";

            if (useLayers)
            {
                if (!request.layers.empty())
                {
                    fb.attribute<int>("OIIO/subimage") = subimage;
                    fb.attribute<string>("Layer") = request.layers[0];
                }
            }
            else if (!request.views.empty())
            {
                fb.attribute<int>("OIIO/subimage") = subimage;
                fb.attribute<string>("View") = request.views[0];
            }

            in->close();
            in.reset();
        }
        else
        {
            TWK_THROW_STREAM(IOException, "OIIO: Unable to open file \"" << filename << "\" for reading. " << geterror());
        }
    }

    void IOoiio::writeImage(const FrameBuffer& img, const std::string& filename, const WriteRequest& request) const
    {
        const FrameBuffer* outfb = &img;

        // Ensure temporary FrameBuffer is cleanly deleted upon return/exception
        struct FBAutoCleanup
        {
            const FrameBuffer*& current;
            const FrameBuffer& original;

            ~FBAutoCleanup()
            {
                if (current != &original)
                    delete current;
            }
        } autoCleanup{outfb, img};

        //
        //  Merge planar frames if needed
        //
        if (outfb->isPlanar())
        {
            const FrameBuffer* fb = outfb;
            outfb = mergePlanes(outfb);
            if (fb != &img)
                delete fb;
        }

        //
        //  Convert YUV / Primaries to Linear Rec. 709 if required
        //
        if (!request.keepColorSpace && (outfb->hasPrimaries() || outfb->isYUV() || outfb->isYRYBY()))
        {
            const FrameBuffer* fb = outfb;
            outfb = convertToLinearRGB709(outfb);
            if (fb != &img)
                delete fb;
        }

        //
        //  Convert packed or unsupported types to standard formats
        //
        switch (outfb->dataType())
        {
        case FrameBuffer::UCHAR:
        case FrameBuffer::USHORT:
        case FrameBuffer::UINT:
        case FrameBuffer::HALF:
        case FrameBuffer::FLOAT:
        case FrameBuffer::DOUBLE:
            break;
        default:
        {
            const FrameBuffer* fb = outfb;
            outfb = copyConvert(outfb, FrameBuffer::UCHAR);
            if (fb != &img)
                delete fb;
            break;
        }
        }

        //
        //  Handle orientation: NATURAL (bottom-left origin) needs vertical flip;
        //  TOPRIGHT / BOTTOMRIGHT needs horizontal flop.
        //
        bool needflip = false;
        bool needflop = false;

        switch (outfb->orientation())
        {
        case FrameBuffer::NATURAL:
            needflip = true;
            break;
        case FrameBuffer::TOPRIGHT:
        case FrameBuffer::BOTTOMRIGHT:
            needflop = true;
            break;
        default:
            break;
        }

        if (needflop)
        {
            if (outfb == &img)
                outfb = img.copy();
            flop(const_cast<FrameBuffer*>(outfb));
        }

        if (needflip)
        {
            if (outfb == &img)
                outfb = img.copy();
            flip(const_cast<FrameBuffer*>(outfb));
        }

        std::unique_ptr<ImageOutput> out = ImageOutput::create(filename);
        if (!out)
        {
            TWK_THROW_STREAM(IOException, "OIIO: Unable to create output for \"" << filename << "\": " << OIIO::geterror());
        }

        TypeDesc format = TypeDesc::UINT8;
        switch (outfb->dataType())
        {
        case FrameBuffer::UCHAR:
            format = TypeDesc::UINT8;
            break;
        case FrameBuffer::USHORT:
            format = TypeDesc::UINT16;
            break;
        case FrameBuffer::UINT:
            format = TypeDesc::UINT32;
            break;
        case FrameBuffer::HALF:
            format = TypeDesc::HALF;
            break;
        case FrameBuffer::FLOAT:
            format = TypeDesc::FLOAT;
            break;
        case FrameBuffer::DOUBLE:
            format = TypeDesc::DOUBLE;
            break;
        default:
            format = TypeDesc::UINT8;
            break;
        }

        //
        //  Drop a trailing alpha channel for writers that cannot store one
        //  (e.g. PNM). The pixel stride still spans all source channels, so
        //  OIIO simply skips the alpha values.
        //
        const int numChannels = outfb->numChannels();
        const bool hasChannelNames = outfb->channelNames().size() == static_cast<size_t>(numChannels);
        const bool lastIsAlpha = !hasChannelNames || outfb->channelNames().back() == "A";
        int nchannels = numChannels;

        if ((numChannels == 2 || numChannels == 4) && lastIsAlpha && !out->supports("alpha"))
        {
            nchannels = numChannels - 1;
        }

        //
        //  Work around OIIO writers that mishandle some sample types. OIIO
        //  converts from the in-memory format to the file format.
        //
        //  pnm:  emits PFM (bottom-to-top float) for any floating point spec
        //        regardless of extension, so store integer samples for
        //        .ppm/.pgm/.pbm/.pnm.
        //  fits: writes BITPIX=-32 for HALF but still writes 16-bit samples,
        //        producing a truncated file, so promote HALF to FLOAT.
        //
        TypeDesc fileFormat = format;
        if (Strutil::iequals(out->format_name(), "pnm") && format.is_floating_point())
        {
            fileFormat = TypeDesc::UINT16;
        }
        else if (Strutil::iequals(out->format_name(), "fits") && format == TypeDesc::HALF)
        {
            fileFormat = TypeDesc::FLOAT;
        }

        ImageSpec spec(outfb->width(), outfb->height(), nchannels, fileFormat);

        if (hasChannelNames)
        {
            spec.channelnames.assign(outfb->channelNames().begin(), outfb->channelNames().begin() + nchannels);
        }

        if (request.pixelAspect != 1.0f && request.pixelAspect != 0.0f)
        {
            spec.attribute("PixelAspectRatio", request.pixelAspect);
        }
        else if (outfb->pixelAspectRatio() != 1.0f && outfb->pixelAspectRatio() != 0.0f)
        {
            spec.attribute("PixelAspectRatio", outfb->pixelAspectRatio());
        }

        if (!request.compression.empty())
        {
            spec.attribute("compression", request.compression);
        }

        if (request.quality >= 0.0f && request.quality <= 1.0f)
        {
            spec.attribute("CompressionQuality", static_cast<int>(request.quality * 100.0f));
        }

        for (const auto& p : request.parameters)
        {
            spec.attribute(p.first, p.second);
        }

        if (!out->open(filename, spec))
        {
            TWK_THROW_STREAM(IOException, "OIIO: Unable to open \"" << filename << "\" for writing: " << out->geterror());
        }

        stride_t xstride = outfb->pixelSize();
        stride_t ystride = outfb->scanlinePaddedSize();

        if (!out->write_image(format, outfb->pixels<unsigned char>(), xstride, ystride))
        {
            TWK_THROW_STREAM(IOException, "OIIO: Error writing \"" << filename << "\": " << out->geterror());
        }

        if (!out->close())
        {
            TWK_THROW_STREAM(IOException, "OIIO: Error closing \"" << filename << "\": " << out->geterror());
        }
    }

} //  End namespace TwkFB
