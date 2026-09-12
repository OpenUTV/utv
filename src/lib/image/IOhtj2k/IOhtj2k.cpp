//
//  Copyright (c) 2025 Sam Richards
//  All rights reserved.
//
//  SPDX-License-Identifier: Apache-2.0
//
//
#include <IOhtj2k/IOhtj2k.h>
#include <TwkUtil/FileStream.h>
#include <TwkUtil/FileMMap.h>
#include <TwkUtil/File.h>
#include <TwkFB/Exception.h>
#include <fstream>
#include <iostream>
#include <iomanip>
#include <TwkFB/Operations.h>
#include <TwkMath/Iostream.h>
#include <TwkUtil/Interrupt.h>
#include <TwkUtil/StdioBuf.h>
#include <TwkUtil/ByteSwap.h>
#include <TwkMath/Color.h>
#include <vector>
#include <string>
#include <openjph/ojph_arg.h>
#include <openjph/ojph_mem.h>
#include <openjph/ojph_file.h>
#include <openjph/ojph_codestream.h>
#include <openjph/ojph_params.h>
#include <openjph/ojph_message.h>
#include <openjpeg.h>
#include <cstdarg>
#ifdef _MSC_VER
#define snprintf _snprintf
#endif

namespace TwkFB
{
    using namespace std;
    using namespace TwkUtil;
    using namespace TwkMath;

    class QuietOjphError : public ojph::message_error
    {
    public:
        void operator()(int error_code, const char* file_name, int line_num, const char* fmt, ...) override
        {
            char buf[512];
            va_list args;
            va_start(args, fmt);
            vsnprintf(buf, sizeof(buf), fmt, args);
            va_end(args);
            throw runtime_error(buf);
        }
    };

    static QuietOjphError g_quietOjphError;
    static bool g_quietOjphConfigured = false;

    static void ensureQuietOjph()
    {
        if (!g_quietOjphConfigured)
        {
            ojph::configure_error(&g_quietOjphError);
            g_quietOjphConfigured = true;
        }
    }

    static void opjQuietInfo(const char*, void*) {}

    static void opjQuietWarn(const char*, void*) {}

    static void opjQuietError(const char*, void*) {}

    bool isHTJ2K(const uint8_t* data, size_t size)
    {
        if (!data || size < 8)
            return false;
        // Direct codestream
        if (data[0] == 0xFF && data[1] == 0x4F)
        {
            if (data[2] == 0xFF && data[3] == 0x51 && size >= 8)
            {
                uint16_t rsiz = (static_cast<uint16_t>(data[6]) << 8) | data[7];
                return (rsiz & 0x4000) != 0;
            }
        }
        // Scan for 'jph ' brand or 'jp2c' codestream box
        size_t limit = (size > 16384) ? 16384 : size;
        if (limit >= 8)
        {
            for (size_t i = 0; i + 4 <= limit; ++i)
            {
                if (data[i] == 'j' && data[i + 1] == 'p' && data[i + 2] == 'h' && data[i + 3] == ' ')
                    return true;

                if (data[i] == 'j' && data[i + 1] == 'p' && data[i + 2] == '2' && data[i + 3] == 'c')
                {
                    size_t cs = i + 4;
                    if (cs + 8 <= size && data[cs] == 0xFF && data[cs + 1] == 0x4F && data[cs + 2] == 0xFF && data[cs + 3] == 0x51)
                    {
                        uint16_t rsiz = (static_cast<uint16_t>(data[cs + 6]) << 8) | data[cs + 7];
                        return (rsiz & 0x4000) != 0;
                    }
                }
            }
        }
        return false;
    }

    static bool isHTJ2KFile(const string& filename)
    {
        FILE* f = TwkUtil::fopen(filename.c_str(), "rb");
        if (!f)
            return false;
        uint8_t buf[16384];
        size_t n = fread(buf, 1, sizeof(buf), f);
        fclose(f);
        return isHTJ2K(buf, n);
    }

    static void getImageInfoOpenJPEG(const string& filename, FBInfo& fbi)
    {
        FILE* f = TwkUtil::fopen(filename.c_str(), "rb");
        if (!f)
            TWK_THROW_STREAM(IOException, "Cannot open file " << filename);

        unsigned char magic[12];
        size_t n = fread(magic, 1, 12, f);
        fclose(f);

        bool isJP2 = (n >= 12 && magic[0] == 0 && magic[1] == 0 && magic[2] == 0 && magic[3] == 12 && magic[4] == 'j' && magic[5] == 'P'
                      && magic[6] == ' ' && magic[7] == ' ');
        OPJ_CODEC_FORMAT fmt = isJP2 ? OPJ_CODEC_JP2 : OPJ_CODEC_J2K;

        opj_stream_t* stream = opj_stream_create_default_file_stream(filename.c_str(), OPJ_TRUE);
        if (!stream)
            TWK_THROW_STREAM(IOException, "OpenJPEG: failed to create stream for " << filename);

        opj_codec_t* codec = opj_create_decompress(fmt);
        if (!codec)
        {
            opj_stream_destroy(stream);
            TWK_THROW_STREAM(IOException, "OpenJPEG: failed to create decompressor for " << filename);
        }

        opj_set_info_handler(codec, opjQuietInfo, nullptr);
        opj_set_warning_handler(codec, opjQuietWarn, nullptr);
        opj_set_error_handler(codec, opjQuietError, nullptr);

        opj_dparameters_t core;
        opj_set_default_decoder_parameters(&core);

        if (!opj_setup_decoder(codec, &core))
        {
            opj_destroy_codec(codec);
            opj_stream_destroy(stream);
            TWK_THROW_STREAM(IOException, "OpenJPEG: failed to setup decoder for " << filename);
        }

        opj_image_t* image = nullptr;
        if (!opj_read_header(stream, codec, &image) || !image)
        {
            opj_destroy_codec(codec);
            opj_stream_destroy(stream);
            TWK_THROW_STREAM(IOException, "OpenJPEG: failed to read header from " << filename);
        }

        fbi.width = image->x1 - image->x0;
        fbi.height = image->y1 - image->y0;
        fbi.numChannels = image->numcomps;
        fbi.pixelAspect = 1.0;
        fbi.orientation = FrameBuffer::NATURAL;

        int prec = (image->numcomps > 0) ? image->comps[0].prec : 8;
        if (prec <= 8)
            fbi.dataType = FrameBuffer::UCHAR;
        else
            fbi.dataType = FrameBuffer::USHORT;

        opj_image_destroy(image);
        opj_destroy_codec(codec);
        opj_stream_destroy(stream);
    }

    static void readImageOpenJPEG(FrameBuffer& fb, const string& filename)
    {
        FILE* f = TwkUtil::fopen(filename.c_str(), "rb");
        if (!f)
            TWK_THROW_STREAM(IOException, "Cannot open file " << filename);

        unsigned char magic[12];
        size_t n = fread(magic, 1, 12, f);
        fclose(f);

        bool isJP2 = (n >= 12 && magic[0] == 0 && magic[1] == 0 && magic[2] == 0 && magic[3] == 12 && magic[4] == 'j' && magic[5] == 'P'
                      && magic[6] == ' ' && magic[7] == ' ');
        OPJ_CODEC_FORMAT fmt = isJP2 ? OPJ_CODEC_JP2 : OPJ_CODEC_J2K;

        opj_stream_t* stream = opj_stream_create_default_file_stream(filename.c_str(), OPJ_TRUE);
        if (!stream)
            TWK_THROW_STREAM(IOException, "OpenJPEG: failed to create stream for " << filename);

        opj_codec_t* codec = opj_create_decompress(fmt);
        if (!codec)
        {
            opj_stream_destroy(stream);
            TWK_THROW_STREAM(IOException, "OpenJPEG: failed to create decompressor for " << filename);
        }

        opj_set_info_handler(codec, opjQuietInfo, nullptr);
        opj_set_warning_handler(codec, opjQuietWarn, nullptr);
        opj_set_error_handler(codec, opjQuietError, nullptr);

        opj_dparameters_t core;
        opj_set_default_decoder_parameters(&core);

        if (!opj_setup_decoder(codec, &core))
        {
            opj_destroy_codec(codec);
            opj_stream_destroy(stream);
            TWK_THROW_STREAM(IOException, "OpenJPEG: failed to setup decoder for " << filename);
        }

        opj_image_t* image = nullptr;
        if (!opj_read_header(stream, codec, &image) || !image)
        {
            opj_destroy_codec(codec);
            opj_stream_destroy(stream);
            TWK_THROW_STREAM(IOException, "OpenJPEG: failed to read header from " << filename);
        }

        if (!opj_decode(codec, stream, image) || !opj_end_decompress(codec, stream))
        {
            opj_image_destroy(image);
            opj_destroy_codec(codec);
            opj_stream_destroy(stream);
            TWK_THROW_STREAM(IOException, "OpenJPEG: failed to decode " << filename);
        }

        const int w = image->x1 - image->x0;
        const int h = image->y1 - image->y0;
        const int ch = image->numcomps;
        const int prec = (ch > 0) ? image->comps[0].prec : 8;

        FrameBuffer::DataType dtype = (prec <= 8) ? FrameBuffer::UCHAR : FrameBuffer::USHORT;

        fb.restructure(w, h, 0, ch, dtype);
        fb.setOrientation(FrameBuffer::TOPLEFT);
        fb.newAttribute("fileBitDepth", prec);

        int bit_offset = 0;
        if (prec == 10)
            bit_offset = 6;
        else if (prec == 12)
            bit_offset = 4;

        if (dtype == FrameBuffer::UCHAR)
        {
            for (int y = 0; y < h; ++y)
            {
                unsigned char* dout = fb.scanline<unsigned char>(y);
                for (int x = 0; x < w; ++x)
                {
                    for (int c = 0; c < ch; ++c)
                    {
                        int dx = image->comps[c].dx;
                        int dy = image->comps[c].dy;
                        int cw = image->comps[c].w;
                        int val = image->comps[c].data[(y / dy) * cw + (x / dx)];
                        if (image->comps[c].sgnd)
                            val += (1 << (prec - 1));
                        dout[x * ch + c] = static_cast<unsigned char>(val);
                    }
                }
            }
        }
        else
        {
            for (int y = 0; y < h; ++y)
            {
                unsigned short* dout = fb.scanline<unsigned short>(y);
                for (int x = 0; x < w; ++x)
                {
                    for (int c = 0; c < ch; ++c)
                    {
                        int dx = image->comps[c].dx;
                        int dy = image->comps[c].dy;
                        int cw = image->comps[c].w;
                        int val = image->comps[c].data[(y / dy) * cw + (x / dx)];
                        if (image->comps[c].sgnd)
                            val += (1 << (prec - 1));
                        dout[x * ch + c] = static_cast<unsigned short>(val << bit_offset);
                    }
                }
            }
        }

        opj_image_destroy(image);
        opj_destroy_codec(codec);
        opj_stream_destroy(stream);
    }

    IOhtj2k::IOhtj2k(IOType type, size_t chunkSize, int maxAsync)
        : StreamingFrameBufferIO("IOhtj2k", "m7", type, chunkSize, maxAsync)
    {
        StringPairVector codecs;
        unsigned int cap = ImageRead | BruteForceIO;

        addType("j2c", "JPEG 2000 Codestream", cap, codecs);
        addType("j2k", "JPEG 2000 Codestream", cap, codecs);
        addType("jp2", "JPEG 2000 Image", cap, codecs);
        addType("jpf", "JPEG 2000 Part 2 Image", cap, codecs);
        addType("jph", "High-Throughput JPEG 2000 Image", cap, codecs);
    }

    IOhtj2k::~IOhtj2k() {}

    string IOhtj2k::about() const { return "JPEG 2000 (OpenJPH / OpenJPEG)"; }

    static void getImageInfoHTJ2K(const string& filename, FBInfo& fbi)
    {
        ojph::j2c_infile j2c_file;
        j2c_file.open(filename.c_str());

        ojph::codestream codestream;
        codestream.read_headers(&j2c_file);

        ojph::param_siz siz = codestream.access_siz();
        ojph::param_nlt nlt = codestream.access_nlt();
        bool nlt_is_signed;
        ojph::ui8 nlt_bit_depth;
        ojph::ui8 nl_type;
        bool has_nlt = nlt.get_nonlinear_transform(0, nlt_bit_depth, nlt_is_signed, nl_type);
        bool is_signed = siz.is_signed(0);

        if (is_signed)
            TWK_THROW_STREAM(UnsupportedException, "HTJ2K: unsupported signed jpeg2000 file " << filename);

        if (has_nlt)
            TWK_THROW_STREAM(UnsupportedException, "HTJ2K: unsupported notlinear transform " << filename);

        fbi.numChannels = siz.get_num_components();
        fbi.width = siz.get_recon_width(0);
        fbi.height = siz.get_recon_height(0);
        fbi.pixelAspect = double(1.0);
        fbi.orientation = FrameBuffer::NATURAL;

        switch (siz.get_bit_depth(0))
        {
        case 8:
            fbi.dataType = FrameBuffer::UCHAR;
            break;
        case 10:
        case 12:
            fbi.dataType = FrameBuffer::USHORT;
            break;
        case 16:
            fbi.dataType = FrameBuffer::USHORT;
            break;
        default:
            TWK_THROW_STREAM(UnsupportedException, "HTJ2K: unsupported bitdepth " << filename);
        }
    }

    void IOhtj2k::getImageInfo(const std::string& filename, FBInfo& fbi) const
    {
        ensureQuietOjph();
        if (isHTJ2KFile(filename))
        {
            try
            {
                getImageInfoHTJ2K(filename, fbi);
                return;
            }
            catch (...)
            {
                // Fall through to OpenJPEG fallback
            }
        }
        getImageInfoOpenJPEG(filename, fbi);
    }

    void copyScanLine(ojph::codestream* codestream, ojph::ui32 width, ojph::ui32 channels, ojph::ui32 row, ojph::ui32 component,
                      FrameBuffer::DataType dtype, int bit_offset, FrameBuffer* fb)
    {

        ojph::ui32 comp_num;
        ojph::line_buf* line = codestream->pull(comp_num);
        const ojph::si32* sp = line->i32;
        assert(comp_num == component);
        if (dtype == FrameBuffer::UCHAR)
        {
            unsigned char* dout = fb->scanline<unsigned char>(row);
            dout += component;
            for (ojph::ui32 j = width; j > 0; j--, dout += channels)
            {
                *dout = *sp++;
            }
        }
        if (dtype == FrameBuffer::USHORT)
        {
            unsigned short* dout = fb->scanline<unsigned short>(row);
            dout += component;
            for (ojph::ui32 j = width; j > 0; j--, dout += channels)
            {
                *dout = *sp << bit_offset;
                sp++;
            }
        }
    }

    FrameBuffer* decodeHTJ2K(ojph::infile_base* infile, FrameBuffer* fb)
    {
        ojph::codestream codestream;
        codestream.read_headers(infile);

        // codestream.enable_resilience();
        ojph::param_siz siz = codestream.access_siz();
        ojph::param_nlt nlt = codestream.access_nlt();
        codestream.create();

        int bit_offset = 0;
        const int ch = siz.get_num_components();
        const int w = siz.get_recon_width(0);
        const int h = siz.get_recon_height(0);
        bool nlt_is_signed;
        ojph::ui8 nlt_bit_depth;
        ojph::ui8 nl_type;
        bool has_nlt = nlt.get_nonlinear_transform(0, nlt_bit_depth, nlt_is_signed, nl_type);
        bool is_signed = siz.is_signed(0);

        // Signed and notlinear transforms are not supported, but it could be added in the future.
        if (is_signed)
            TWK_THROW_STREAM(UnsupportedException, "HTJ2K: unsupported signed jpeg2000 image");

        if (has_nlt)
            TWK_THROW_STREAM(UnsupportedException, "HTJ2K: unsupported notlinear transform in jpeg2000 image");

        // 4. Wrap the decoded image in a FrameBuffer
        FrameBuffer::DataType dtype = FrameBuffer::USHORT;

        switch (siz.get_bit_depth(0))
        {
        case 8:
            dtype = FrameBuffer::UCHAR;
            break;
        case 10:
            bit_offset = 6;
            dtype = FrameBuffer::USHORT;
            break;
        case 12:
            bit_offset = 4;
        case 16:
            dtype = FrameBuffer::USHORT;
            break;
        }

        if (fb == NULL)
        {
            // If no FrameBuffer is provided, create a new one
            // Typically used when called from MovieFFMpeg
            fb = new FrameBuffer(w, h, ch, dtype);
            fb->setOrientation(FrameBuffer::BOTTOMLEFT);
        }
        else
        {
            // If a FrameBuffer is provided, restructure it
            fb->restructure(w, h, 0, ch, dtype);
            // I dont really understand why its TOPLEFT here, but BOTTOMLEFT for MovieFFMPEG
            // when the underlying data is the same.
            // I suspect it has to do with the way the FrameBuffer is used in MovieFFMPEG
            // and how it expects the orientation to be set.
            fb->setOrientation(FrameBuffer::TOPLEFT);
        }
        fb->newAttribute("fileBitDepth", siz.get_bit_depth(0));
        if (codestream.is_planar())
        {
            // Its pretty rare for RGB to be planar, possibily the most common case is a single channel image
            for (ojph::ui32 c = 0; c < siz.get_num_components(); ++c)
                for (ojph::ui32 i = 0; i < h; ++i)
                    copyScanLine(&codestream, w, ch, i, c, dtype, bit_offset, fb);
        }
        else
        {
            for (ojph::ui32 i = 0; i < h; ++i)
                for (ojph::ui32 c = 0; c < siz.get_num_components(); ++c)
                    copyScanLine(&codestream, w, ch, i, c, dtype, bit_offset, fb);
        }

        return fb;
    }

    void IOhtj2k::readImage(FrameBuffer& fb, const std::string& filename, const ReadRequest& request) const
    {
        ensureQuietOjph();
        if (isHTJ2KFile(filename))
        {
            try
            {
                ojph::j2c_infile j2c_file;
                j2c_file.open(filename.c_str());
                decodeHTJ2K(&j2c_file, &fb);
                return;
            }
            catch (...)
            {
                // Fall through to OpenJPEG fallback
            }
        }
        readImageOpenJPEG(fb, filename);
    }

} // namespace TwkFB
