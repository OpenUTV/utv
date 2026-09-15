//******************************************************************************
// Copyright (c) 2007 Tweak Inc.
// All rights reserved.
//
// SPDX-License-Identifier: Apache-2.0
//
//******************************************************************************

#include <IOpng/IOpng.h>
#include <iostream>
#include <TwkFB/Operations.h>
#include <TwkFB/Exception.h>
#include <TwkMath/Iostream.h>
#include <TwkUtil/File.h>
#include <png.h>
#ifdef HAVE_LIBSPNG
#include <spng.h>
#endif

namespace TwkFB
{
    using namespace std;

    IOpng::IOpng()
        : FrameBufferIO("IOpng", "m9")
        , m_error(false)
    {
        unsigned int cap = ImageRead | ImageWrite | Int8Capable | Int16Capable;
        addType("png", "Portable Network Graphics Image", cap);
    }

    IOpng::~IOpng() {}

    string IOpng::about() const
    {
        char temp[128];
#ifdef HAVE_LIBSPNG
        sprintf(temp, "PNG (libspng %d.%d.%d, fallback libpng %s)", SPNG_VERSION_MAJOR, SPNG_VERSION_MINOR, SPNG_VERSION_PATCH,
                PNG_LIBPNG_VER_STRING);
#else
        sprintf(temp, "PNG (libpng %s)", PNG_LIBPNG_VER_STRING);
#endif
        return temp;
    }

    struct IOpngErrorContext
    {
        bool error = false;
        jmp_buf jmpbuf;
    };

    static void png_error_handler(png_structp png_ptr, png_const_charp error_msg)
    {
        IOpngErrorContext* context = static_cast<IOpngErrorContext*>(png_get_error_ptr(png_ptr));
        if (context)
        {
            context->error = true;
            longjmp(context->jmpbuf, 1);
        }
    }

    static void readAttrs(FrameBuffer& fb, png_structp png_ptr, png_infop info_ptr)
    {
        //
        //  Color Space
        //
        //  We'll give priority to the enum'd spaces, then profiles, then
        //  gamma/chromaticity.  But we'll report everything...for the
        //  moment.
        //
        //

        double gamma = 1.0;
        int intent = 0;
        int unit = 0;
        png_charp icc_name, icc_ptr;
        png_bytep icc_profile;
        png_uint_32 icc_proflen = 0;
        int icc_compression;

        if (png_get_sRGB(png_ptr, info_ptr, &intent))
        {
            fb.setPrimaryColorSpace(ColorSpace::Rec709());
            fb.setTransferFunction(ColorSpace::sRGB());

            string itype = "-unknown-";

            switch (intent)
            {
            case PNG_sRGB_INTENT_PERCEPTUAL:
                itype = "PERCEPTUAL";
                break;
            case PNG_sRGB_INTENT_RELATIVE:
                itype = "RELATIVE";
                break;
            case PNG_sRGB_INTENT_SATURATION:
                itype = "SATURATION";
                break;
            case PNG_sRGB_INTENT_ABSOLUTE:
                itype = "ABSOLUTE";
                break;
            default:
                break;
            };

            fb.newAttribute("PNG/sRGBIntent", itype);
        }

        if (png_get_iCCP(png_ptr, info_ptr, &icc_name, &icc_compression, &icc_profile, &icc_proflen))
        {
            if (!fb.hasPrimaryColorSpace())
                fb.setPrimaryColorSpace(ColorSpace::ICCProfile());
            if (!fb.hasTransferFunction())
                fb.setTransferFunction(ColorSpace::ICCProfile());
            fb.setICCprofile(icc_profile, icc_proflen);
        }

        double w_x, w_y, r_x, r_y, g_x, g_y, b_x, b_y;

        if (png_get_gAMA(png_ptr, info_ptr, &gamma))
        {
            if (!fb.hasPrimaryColorSpace())
                fb.setPrimaryColorSpace(ColorSpace::Rec709());

            fb.attribute<float>(ColorSpace::Gamma()) = 1.0f / gamma; // PNG uses "file gamma"
        }

        if (png_get_cHRM(png_ptr, info_ptr, &w_x, &w_y, &r_x, &r_y, &g_x, &g_y, &b_x, &b_y))
        {
            fb.setPrimaryColorSpace(ColorSpace::Generic());

            TwkMath::Vec2f white(w_x, w_y);
            TwkMath::Vec2f red(r_x, r_y);
            TwkMath::Vec2f green(g_x, g_y);
            TwkMath::Vec2f blue(b_x, b_y);

            fb.attribute<TwkMath::Vec2f>(ColorSpace::WhitePrimary()) = white;
            fb.attribute<TwkMath::Vec2f>(ColorSpace::BluePrimary()) = blue;
            fb.attribute<TwkMath::Vec2f>(ColorSpace::GreenPrimary()) = green;
            fb.attribute<TwkMath::Vec2f>(ColorSpace::RedPrimary()) = red;
        }

        png_textp text_blocks;
        int num_blocks;

        if (png_get_text(png_ptr, info_ptr, &text_blocks, &num_blocks))
        {
            for (int i = 0; i < num_blocks; i++)
            {
                fb.newAttribute(text_blocks[i].key, string(text_blocks[i].text, text_blocks[i].text_length));
            }
        }
    }

    static void pngNoMessageHandler(png_structp png_ptr, png_const_charp error_message)
    {
#ifdef USE_FAR_KEYWORD
        jmp_buf jmpbuf;
        png_memcpy(jmpbuf, png_ptr->jmpbuf, png_sizeof(jmp_buf));
        IOpngErrorContext* context = static_cast<IOpngErrorContext*>(png_get_error_ptr(png_ptr));
        if (context)
        {
            context->error = true;
            longjmp(jmpbuf, 1);
        }
#else
        IOpngErrorContext* context = static_cast<IOpngErrorContext*>(png_get_error_ptr(png_ptr));
        if (context)
        {
            context->error = true;
            longjmp(context->jmpbuf, 1);
        }
#endif
    }

    static void setjmpHandler(png_structp* pp, png_infop* ip, png_infop* ep, FILE* fp, const string& filename)
    {
        png_destroy_read_struct(pp, ip, ep);
        if (fp)
        {
            fclose(fp);
            fp = nullptr;
        }
        TWK_THROW_STREAM(IOException, "PNG: error reading " << filename);
    }

    void IOpng::getImageInfo(const string& filename, FBInfo& fbi) const
    {
#ifdef HAVE_LIBSPNG
        spng_ctx* spng_read_ctx = spng_ctx_new(0);
        if (spng_read_ctx)
        {
            FILE* sfp = TwkUtil::fopen(filename.c_str(), "rb");
            if (sfp)
            {
                if (spng_set_png_file(spng_read_ctx, sfp) == SPNG_OK)
                {
                    struct spng_ihdr ihdr;
                    if (spng_get_ihdr(spng_read_ctx, &ihdr) == SPNG_OK)
                    {
                        fbi.width = ihdr.width;
                        fbi.height = ihdr.height;
                        fbi.uncropWidth = ihdr.width;
                        fbi.uncropHeight = ihdr.height;
                        fbi.uncropX = 0;
                        fbi.uncropY = 0;
                        fbi.orientation = FrameBuffer::TOPLEFT;
                        fbi.dataType = (ihdr.bit_depth == 16) ? FrameBuffer::USHORT : FrameBuffer::UCHAR;

                        int channels = 4;
                        if (ihdr.color_type == SPNG_COLOR_TYPE_GRAYSCALE)
                            channels = 1;
                        else if (ihdr.color_type == SPNG_COLOR_TYPE_GRAYSCALE_ALPHA)
                            channels = 2;
                        else if (ihdr.color_type == SPNG_COLOR_TYPE_TRUECOLOR)
                            channels = 3;
                        else if (ihdr.color_type == SPNG_COLOR_TYPE_INDEXED)
                        {
                            struct spng_trns trns;
                            channels = (spng_get_trns(spng_read_ctx, &trns) == SPNG_OK) ? 4 : 3;
                        }
                        fbi.numChannels = channels;

                        struct spng_phys phys;
                        if (spng_get_phys(spng_read_ctx, &phys) == SPNG_OK && phys.unit_specifier == 1 && phys.ppu_x > 0 && phys.ppu_y > 0)
                        {
                            fbi.pixelAspect = ((float)phys.ppu_y) / ((float)phys.ppu_x);
                        }
                        else
                        {
                            fbi.pixelAspect = 1.0f;
                        }

                        uint8_t srgb_intent = 0;
                        if (spng_get_srgb(spng_read_ctx, &srgb_intent) == SPNG_OK)
                        {
                            fbi.proxy.setPrimaryColorSpace(ColorSpace::Rec709());
                            fbi.proxy.setTransferFunction(ColorSpace::sRGB());
                        }

                        spng_ctx_free(spng_read_ctx);
                        fclose(sfp);
                        return;
                    }
                }
                fclose(sfp);
            }
            spng_ctx_free(spng_read_ctx);
        }
#endif
        FILE* fp = TwkUtil::fopen(filename.c_str(), "rb");
        if (!fp)
        {
            TWK_THROW_STREAM(IOException, "PNG: cannot open " << filename);
        }

        IOpngErrorContext errorContext;
        errorContext.error = m_error;

        png_structp png_ptr = png_create_read_struct(PNG_LIBPNG_VER_STRING, &errorContext, png_error_handler, 0);

        //
        //  Throttle error messages.
        //
        // png_set_error_fn (png_ptr, png_ptr->error_ptr, pngNoMessageHandler,
        // png_ptr->warning_fn);
        png_set_error_fn(png_ptr, &errorContext, pngNoMessageHandler, 0);

        if (!png_ptr || errorContext.error)
        {
            if (fp)
            {
                fclose(fp);
                fp = nullptr;
            }
            TWK_THROW_STREAM(IOException, "PNG: error creating read struct " << filename);
        }

        if (setjmp(errorContext.jmpbuf))
            setjmpHandler(&png_ptr, 0, 0, fp, filename);

        png_infop info_ptr = png_create_info_struct(png_ptr);

        if (!info_ptr)
        {
            png_destroy_read_struct(&png_ptr, (png_infopp)NULL, (png_infopp)NULL);

            if (fp)
            {
                fclose(fp);
                fp = nullptr;
            }
            TWK_THROW_STREAM(IOException, "PNG: error creating read struct " << filename);
        }

        if (setjmp(errorContext.jmpbuf))
            setjmpHandler(&png_ptr, &info_ptr, 0, fp, filename);

        png_infop end_info = png_create_info_struct(png_ptr);

        if (!end_info)
        {
            png_destroy_read_struct(&png_ptr, &info_ptr, (png_infopp)NULL);
            if (fp)
            {
                fclose(fp);
                fp = nullptr;
            }
            TWK_THROW_STREAM(IOException, "PNG: error creating info struct " << filename);
        }

        //
        //	Wicked (ick) longjmp error handler
        //

        if (setjmp(errorContext.jmpbuf))
            setjmpHandler(&png_ptr, &info_ptr, &end_info, fp, filename);

        png_init_io(png_ptr, fp);
        png_set_sig_bytes(png_ptr, 0);
        png_read_info(png_ptr, info_ptr);

        int b = png_get_bit_depth(png_ptr, info_ptr);

        fbi.dataType = b == 8 ? FrameBuffer::UCHAR : FrameBuffer::USHORT;
        fbi.width = png_get_image_width(png_ptr, info_ptr);
        fbi.height = png_get_image_height(png_ptr, info_ptr);
        fbi.numChannels = png_get_channels(png_ptr, info_ptr);
        fbi.orientation = FrameBuffer::TOPLEFT;

        int xPixPerMeter = png_get_x_pixels_per_meter(png_ptr, info_ptr);
        int yPixPerMeter = png_get_y_pixels_per_meter(png_ptr, info_ptr);
        fbi.pixelAspect = 1.0;

        if (xPixPerMeter > 0 && yPixPerMeter > 0)
        {
            fbi.pixelAspect = ((float)yPixPerMeter) / ((float)xPixPerMeter);
        }

        readAttrs(fbi.proxy, png_ptr, info_ptr);

        string ctype = "-unknown-";
        int color_type = png_get_color_type(png_ptr, info_ptr);

        switch (color_type)
        {
        case PNG_COLOR_TYPE_GRAY_ALPHA:
            ctype = "GRAY_ALPHA";
            break;
        case PNG_COLOR_TYPE_GRAY:
            ctype = "GRAY";
            break;
        case PNG_COLOR_TYPE_PALETTE:
            ctype = "PALETTE";
            break;
        case PNG_COLOR_TYPE_RGB:
            ctype = "RGB";
            break;
        case PNG_COLOR_TYPE_RGB_ALPHA:
            ctype = "RGB_ALPHA";
            break;
        default:
            break;
        }

        fbi.proxy.newAttribute("PNG/ColorType", ctype);
        if (fp)
        {
            fclose(fp);
            fp = nullptr;
        }
    }

    void IOpng::readImage(FrameBuffer& fb, const std::string& filename, const ReadRequest& request) const
    {
#ifdef HAVE_LIBSPNG
        spng_ctx* spng_read_ctx = spng_ctx_new(0);
        if (spng_read_ctx)
        {
            FILE* sfp = TwkUtil::fopen(filename.c_str(), "rb");
            if (sfp)
            {
                if (spng_set_png_file(spng_read_ctx, sfp) == SPNG_OK)
                {
                    struct spng_ihdr ihdr;
                    if (spng_get_ihdr(spng_read_ctx, &ihdr) == SPNG_OK)
                    {
                        int fmt = SPNG_FMT_RGBA8;
                        FrameBuffer::DataType dt = FrameBuffer::UCHAR;
                        int components = 4;

                        if (ihdr.color_type == SPNG_COLOR_TYPE_GRAYSCALE)
                        {
                            fmt = (ihdr.bit_depth == 16) ? SPNG_FMT_RGBA16 : SPNG_FMT_G8;
                            dt = (ihdr.bit_depth == 16) ? FrameBuffer::USHORT : FrameBuffer::UCHAR;
                            components = (ihdr.bit_depth == 16) ? 4 : 1;
                        }
                        else if (ihdr.color_type == SPNG_COLOR_TYPE_GRAYSCALE_ALPHA)
                        {
                            fmt = (ihdr.bit_depth == 16) ? SPNG_FMT_GA16 : SPNG_FMT_GA8;
                            dt = (ihdr.bit_depth == 16) ? FrameBuffer::USHORT : FrameBuffer::UCHAR;
                            components = 2;
                        }
                        else if (ihdr.bit_depth == 16)
                        {
                            fmt = SPNG_FMT_RGBA16;
                            dt = FrameBuffer::USHORT;
                            components = 4;
                        }
                        else
                        {
                            fmt = SPNG_FMT_RGBA8;
                            dt = FrameBuffer::UCHAR;
                            components = 4;
                        }

                        size_t out_size = 0;
                        if (spng_decoded_image_size(spng_read_ctx, fmt, &out_size) == SPNG_OK)
                        {
                            fb.restructure(ihdr.width, ihdr.height, 0, components, dt);
                            fb.setOrientation(FrameBuffer::TOPLEFT);

                            struct spng_phys phys;
                            if (spng_get_phys(spng_read_ctx, &phys) == SPNG_OK && phys.unit_specifier == 1 && phys.ppu_x > 0
                                && phys.ppu_y > 0)
                            {
                                fb.setPixelAspectRatio(((float)phys.ppu_y) / ((float)phys.ppu_x));
                            }

                            uint8_t srgb_intent = 0;
                            if (spng_get_srgb(spng_read_ctx, &srgb_intent) == SPNG_OK)
                            {
                                fb.setPrimaryColorSpace(ColorSpace::Rec709());
                                fb.setTransferFunction(ColorSpace::sRGB());
                            }

                            double gamma = 0.0;
                            if (spng_get_gama(spng_read_ctx, &gamma) == SPNG_OK && gamma > 0.0)
                            {
                                fb.newAttribute("PNG/Gamma", gamma);
                            }

                            struct spng_iccp iccp;
                            if (spng_get_iccp(spng_read_ctx, &iccp) == SPNG_OK && iccp.profile_len > 0)
                            {
                                fb.setICCprofile((unsigned char*)iccp.profile, iccp.profile_len);
                            }

                            int decode_flags = SPNG_DECODE_TRNS;
                            int decode_ret = spng_decode_image(spng_read_ctx, fb.scanline<unsigned char>(0), out_size, fmt, decode_flags);
                            if (decode_ret == SPNG_OK)
                            {
                                spng_ctx_free(spng_read_ctx);
                                fclose(sfp);
                                return;
                            }
                        }
                    }
                }
                fclose(sfp);
            }
            spng_ctx_free(spng_read_ctx);
        }
#endif
        FILE* fp = TwkUtil::fopen(filename.c_str(), "rb");
        if (!fp)
        {
            TWK_THROW_STREAM(IOException, "PNG: cannot open " << filename);
        }

        IOpngErrorContext errorContext;
        errorContext.error = m_error;

        png_structp png_ptr = png_create_read_struct(PNG_LIBPNG_VER_STRING, &errorContext, png_error_handler, 0);

        if (!png_ptr || errorContext.error)
        {
            if (fp)
            {
                fclose(fp);
                fp = nullptr;
            }
            TWK_THROW_STREAM(IOException, "PNG: error creating read struct " << filename);
        }

        if (setjmp(errorContext.jmpbuf))
            setjmpHandler(&png_ptr, 0, 0, fp, filename);

        png_infop info_ptr = png_create_info_struct(png_ptr);

        if (!info_ptr)
        {
            png_destroy_read_struct(&png_ptr, (png_infopp)NULL, (png_infopp)NULL);

            if (fp)
            {
                fclose(fp);
                fp = nullptr;
            }
            TWK_THROW_STREAM(IOException, "PNG: error creating read struct " << filename);
        }

        if (setjmp(errorContext.jmpbuf))
            setjmpHandler(&png_ptr, &info_ptr, 0, fp, filename);

        png_infop end_info = png_create_info_struct(png_ptr);

        if (!end_info)
        {
            png_destroy_read_struct(&png_ptr, &info_ptr, (png_infopp)NULL);
            if (fp)
            {
                fclose(fp);
                fp = nullptr;
            }
            TWK_THROW_STREAM(IOException, "PNG: error creating info struct " << filename);
        }

        //
        //	Wicked (ick) longjmp error handler
        //

        if (setjmp(errorContext.jmpbuf))
            setjmpHandler(&png_ptr, &info_ptr, &end_info, fp, filename);

        png_init_io(png_ptr, fp);
        png_set_sig_bytes(png_ptr, 0);
        png_read_info(png_ptr, info_ptr);

        int b = png_get_bit_depth(png_ptr, info_ptr);
        int w = png_get_image_width(png_ptr, info_ptr);
        int h = png_get_image_height(png_ptr, info_ptr);
        int components = png_get_channels(png_ptr, info_ptr);

        int color_type = png_get_color_type(png_ptr, info_ptr);
        int bit_depth = png_get_bit_depth(png_ptr, info_ptr);
        if (color_type == PNG_COLOR_TYPE_PALETTE)
        {
            png_set_palette_to_rgb(png_ptr);

            components = png_get_valid(png_ptr, info_ptr, PNG_INFO_tRNS) ? 4 /*RGBA*/
                                                                         : 3 /*RGB*/;
        }

        if (color_type == PNG_COLOR_TYPE_GRAY && bit_depth < 8)
        {
            // png_set_gray_1_2_4_to_8(png_ptr);
            png_set_gray_to_rgb(png_ptr);
        }

        if (png_get_valid(png_ptr, info_ptr, PNG_INFO_tRNS))
        {
            png_set_tRNS_to_alpha(png_ptr);
        }

        fb.restructure(w, h, 0, components, b == 8 ? FrameBuffer::UCHAR : FrameBuffer::USHORT);
        fb.setOrientation(FrameBuffer::TOPLEFT);

        // make 16 eight bit
        // png_set_strip_16(png_ptr);

        // if (color_type & PNG_COLOR_MASK_ALPHA)
        // png_set_strip_alpha(png_ptr);

        if (bit_depth < 8)
            png_set_packing(png_ptr);

#if defined(TWK_LITTLE_ENDIAN) || defined(__LITTLE_ENDIAN__)
        if (bit_depth > 8)
            png_set_swap(png_ptr);
#endif

        // Silence the following warning;
        // "libpng warning: Interlace handling should be turned on when using
        // png_read_image"
        //
        if (png_get_interlace_type(png_ptr, info_ptr) != PNG_INTERLACE_NONE)
        {
            png_set_interlace_handling(png_ptr);
        }

        // if (color_type == PNG_COLOR_TYPE_GRAY ||
        // color_type == PNG_COLOR_TYPE_GRAY_ALPHA)
        //   png_set_gray_to_rgb(png_ptr);

        png_read_update_info(png_ptr, info_ptr);

        if (png_get_y_pixels_per_meter(png_ptr, info_ptr) != png_get_y_pixels_per_meter(png_ptr, info_ptr))
        {
            fb.setPixelAspectRatio((float)png_get_y_pixels_per_meter(png_ptr, info_ptr)
                                   / (float)png_get_x_pixels_per_meter(png_ptr, info_ptr));
        }

        readAttrs(fb, png_ptr, info_ptr);

        //
        //  Read Image Pixels
        //

        png_bytep* row_pointers = new png_bytep[h];

        for (size_t i = 0; i < h; i++)
        {
            row_pointers[i] = fb.scanline<png_byte>(i);
        }

        png_read_image(png_ptr, row_pointers);

        png_read_end(png_ptr, end_info);

        png_destroy_read_struct(&png_ptr, &info_ptr, &end_info);

        string ctype = "-unknown-";

        switch (color_type)
        {
        case PNG_COLOR_TYPE_GRAY_ALPHA:
            ctype = "GRAY_ALPHA";
            break;
        case PNG_COLOR_TYPE_GRAY:
            ctype = "GRAY";
            break;
        case PNG_COLOR_TYPE_PALETTE:
            ctype = "PALETTE";
            break;
        case PNG_COLOR_TYPE_RGB:
            ctype = "RGB";
            break;
        case PNG_COLOR_TYPE_RGB_ALPHA:
            ctype = "RGB_ALPHA";
            break;
        default:
            break;
        }

        fb.newAttribute("PNG/ColorType", ctype);

        delete[] row_pointers;
        if (fp)
        {
            fclose(fp);
            fp = nullptr;
        }
    }

    void IOpng::writeImage(const FrameBuffer& img, const std::string& filename, const WriteRequest& request) const
    {
        FILE* fp = TwkUtil::fopen(filename.c_str(), "wb");

        if (!fp)
        {
            TWK_THROW_STREAM(IOException, "PNG: error open file " << filename);
        }

        const FrameBuffer* outfb = &img;

        //
        //  Convert to UCHAR packed if not already.
        //

        if (img.isPlanar())
        {
            const FrameBuffer* fb = outfb;
            outfb = mergePlanes(outfb);
            if (fb != &img)
                delete fb;
        }

        //
        //  Convert everything to REC709
        //

        if (outfb->hasPrimaries() || outfb->isYUV() || outfb->isYRYBY())
        {
            const FrameBuffer* fb = outfb;
            outfb = convertToLinearRGB709(outfb);
            if (fb != &img)
                delete fb;
        }

        switch (img.dataType())
        {
        case FrameBuffer::UCHAR:
        case FrameBuffer::USHORT:
            break;
        default:
        {
            const FrameBuffer* fb = outfb;
            outfb = copyConvert(outfb, FrameBuffer::UCHAR);
            if (fb != &img)
                delete fb;
            break;
        }
        break;
        }

        //
        //  Flip and Flop to get in the right orientation
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
        };

        if (needflop)
        {
            if (outfb == &img)
                outfb = img.copy();
            flop(const_cast<FrameBuffer*>(outfb));
        }

        IOpngErrorContext errorContext;
        errorContext.error = m_error;

        png_structp png_ptr = png_create_write_struct(PNG_LIBPNG_VER_STRING, &errorContext, pngNoMessageHandler, 0);
        if (!png_ptr)
        {
            if (fp)
            {
                fclose(fp);
                fp = nullptr;
            }
            TWK_THROW_STREAM(IOException, "PNG: error creating png_struct " << filename);
        }

        if (setjmp(errorContext.jmpbuf))
            setjmpHandler(&png_ptr, 0, 0, fp, filename);

        png_infop info_ptr = png_create_info_struct(png_ptr);

        if (!info_ptr)
        {
            png_destroy_write_struct(&png_ptr, (png_infopp)NULL);
            if (fp)
            {
                fclose(fp);
                fp = nullptr;
            }
            TWK_THROW_STREAM(IOException, "PNG: error creating info struct " << filename);
        }

        if (setjmp(errorContext.jmpbuf))
            setjmpHandler(&png_ptr, &info_ptr, 0, fp, filename);

        png_init_io(png_ptr, fp);

        int bit_depth = 0;
        int color_type = 0;

        switch (outfb->dataType())
        {
        case FrameBuffer::UCHAR:
            bit_depth = 8;
            break;
        case FrameBuffer::USHORT:
            bit_depth = 16;
            break;
        default:
            break;
        }

        switch (outfb->numChannels())
        {
        case 3:
            color_type = PNG_COLOR_TYPE_RGB;
            break;
        case 4:
            color_type = PNG_COLOR_TYPE_RGB_ALPHA;
            break;
        case 1:
            color_type = PNG_COLOR_TYPE_GRAY;
            break;
        case 2:
            color_type = PNG_COLOR_TYPE_GRAY_ALPHA;
            break;
        }

        vector<png_bytep> rows(img.height());

        for (size_t i = 0; i < img.height(); i++)
        {
            rows[i] = (png_bytep)outfb->scanline<png_byte>(needflip ? img.height() - i - 1 : i);
        }

        png_set_IHDR(png_ptr, info_ptr, outfb->width(), outfb->height(), bit_depth, color_type, PNG_INTERLACE_NONE,
                     PNG_COMPRESSION_TYPE_DEFAULT, PNG_FILTER_TYPE_DEFAULT);

        png_set_rows(png_ptr, info_ptr, &rows.front());

        int transforms = PNG_TRANSFORM_IDENTITY;

#if defined(TWK_LITTLE_ENDIAN) || defined(__LITTLE_ENDIAN__)
        if (bit_depth > 8)
            transforms |= PNG_TRANSFORM_SWAP_ENDIAN;
#endif

        png_write_png(png_ptr, info_ptr, transforms, NULL);

        if (fp)
        {
            fclose(fp);
            fp = nullptr;
        }

        png_destroy_write_struct(&png_ptr, &info_ptr);

        if (outfb != &img)
            delete outfb;
    }

} // namespace TwkFB
