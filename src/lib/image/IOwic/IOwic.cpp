//
// Copyright (C) 2026  Contributors to the OpenUTV Project
//
// SPDX-License-Identifier: Apache-2.0
//
#include <IOwic/IOwic.h>
#include <TwkFB/Exception.h>
#include <TwkFB/Operations.h>

#include <windows.h>
#include <wincodec.h>
#include <wrl/client.h>

#include <algorithm>
#include <iomanip>
#include <sstream>
#include <string>
#include <vector>

namespace TwkFB
{
    using namespace std;
    using Microsoft::WRL::ComPtr;

    namespace
    {
        const char* const missingEncoderHelp =
            "Windows has no HEIF/HEVC encoder installed. Install \"HEIF Image Extensions\" and \"HEVC Video Extensions\""
            " from the Microsoft Store to export HEIC, or export AVIF instead.";

        //
        //  COM for the calling thread. If the thread already uses a different
        //  apartment model, COM is usable as it is and must not be uninitialized.
        //
        struct ComScope
        {
            ComScope()
                : owned(SUCCEEDED(CoInitializeEx(nullptr, COINIT_MULTITHREADED)))
            {
            }

            ~ComScope()
            {
                if (owned)
                    CoUninitialize();
            }

            bool owned;
        };

        string hresultText(HRESULT hr)
        {
            ostringstream str;
            str << "HRESULT 0x" << hex << setw(8) << setfill('0') << static_cast<unsigned long>(hr);
            return str.str();
        }

        wstring toWide(const string& utf8)
        {
            if (utf8.empty())
                return wstring();
            const int len = MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, nullptr, 0);
            wstring wide(len > 0 ? len - 1 : 0, L'\0');
            if (len > 1)
                MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, &wide[0], len);
            return wide;
        }

        HRESULT createHeifEncoder(ComPtr<IWICImagingFactory>& factory, ComPtr<IWICBitmapEncoder>& encoder)
        {
            HRESULT hr = CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&factory));
            if (FAILED(hr))
                return hr;
            return factory->CreateEncoder(GUID_ContainerFormatHeif, nullptr, &encoder);
        }
    } // namespace

    //
    //  Sorted after IOoiio ("m3"), which reads these files and writes them if
    //  libheif has an HEVC encoder.
    //
    //  Write is always advertised: the formats cache is made on the build
    //  machine, while the encoder is a property of the user's machine. A missing
    //  encoder is reported when writing, with what to install.
    //
    IOwic::IOwic()
        : FrameBufferIO("IOwic", "o")
    {
        StringPairVector codecs;
        addType("heic", "High Efficiency Image File (Windows encoder)", ImageWrite, codecs);
        addType("heif", "High Efficiency Image File (Windows encoder)", ImageWrite, codecs);
        addType("hif", "High Efficiency Image File (Windows encoder)", ImageWrite, codecs);
    }

    IOwic::~IOwic() {}

    string IOwic::about() const { return "Windows Imaging Component (HEIF)"; }

    void IOwic::getImageInfo(const std::string&, FBInfo&) const
    {
        TWK_THROW_STREAM(UnsupportedException, "IOwic: reading is not supported");
    }

    void IOwic::readImage(FrameBuffer&, const std::string&, const ReadRequest&) const
    {
        TWK_THROW_STREAM(UnsupportedException, "IOwic: reading is not supported");
    }

    void IOwic::writeImage(const FrameBuffer& img, const std::string& filename, const WriteRequest& request) const
    {
        ComScope com;
        ComPtr<IWICImagingFactory> factory;
        ComPtr<IWICBitmapEncoder> encoder;

        HRESULT hr = createHeifEncoder(factory, encoder);
        if (FAILED(hr))
        {
            TWK_THROW_STREAM(IOException,
                             "IOwic: cannot write \"" << filename << "\": " << missingEncoderHelp << " (" << hresultText(hr) << ")");
        }

        //
        //  Convert to packed 8 bit RGB or RGBA.
        //

        const FrameBuffer* outfb = &img;

        if (outfb->isPlanar())
        {
            const FrameBuffer* fb = outfb;
            outfb = mergePlanes(outfb);
            if (fb != &img)
                delete fb;
        }

        if (outfb->isYUV() || outfb->isYRYBY() || outfb->dataType() >= FrameBuffer::PACKED_R10_G10_B10_X2)
        {
            const FrameBuffer* fb = outfb;
            outfb = convertToLinearRGB709(outfb);
            if (fb != &img)
                delete fb;
        }

        const bool hasAlpha = outfb->hasChannel("A");
        const int nchannels = hasAlpha ? 4 : 3;
        {
            const FrameBuffer* fb = outfb;
            vector<string> mapping = {"R", "G", "B"};
            if (hasAlpha)
                mapping.push_back("A");
            outfb = channelMap(const_cast<FrameBuffer*>(outfb), mapping);
            if (fb != &img)
                delete fb;
        }

        if (outfb->dataType() != FrameBuffer::UCHAR)
        {
            const FrameBuffer* fb = outfb;
            outfb = copyConvert(outfb, FrameBuffer::UCHAR);
            if (fb != &img)
                delete fb;
        }

        //
        //  WIC wants BGRA, top-down. FrameBuffer scanlines are bottom-up.
        //

        const UINT width = static_cast<UINT>(outfb->width());
        const UINT height = static_cast<UINT>(outfb->height());
        const UINT stride = width * 4;
        vector<BYTE> pixels(static_cast<size_t>(stride) * height);

        for (UINT row = 0; row < height; row++)
        {
            const unsigned char* src = outfb->scanline<unsigned char>(height - row - 1);
            BYTE* dst = pixels.data() + static_cast<size_t>(row) * stride;

            for (UINT col = 0; col < width; col++, src += nchannels, dst += 4)
            {
                dst[0] = src[2];
                dst[1] = src[1];
                dst[2] = src[0];
                dst[3] = hasAlpha ? src[3] : 255;
            }
        }

        if (outfb != &img)
            delete outfb;

        //
        //  Encode. WriteSource converts to the pixel format the encoder picks.
        //

        const wstring path = toWide(filename);
        ComPtr<IWICStream> stream;
        ComPtr<IWICBitmapFrameEncode> frame;
        ComPtr<IPropertyBag2> properties;
        ComPtr<IWICBitmap> bitmap;
        const char* step = "create stream";

        hr = factory->CreateStream(&stream);
        if (SUCCEEDED(hr))
        {
            step = "open output file";
            hr = stream->InitializeFromFilename(path.c_str(), GENERIC_WRITE);
        }
        if (SUCCEEDED(hr))
        {
            step = "initialize encoder";
            hr = encoder->Initialize(stream.Get(), WICBitmapEncoderNoCache);
        }
        if (SUCCEEDED(hr))
        {
            step = "create frame";
            hr = encoder->CreateNewFrame(&frame, &properties);
        }
        if (SUCCEEDED(hr) && properties)
        {
            PROPBAG2 option = {};
            wchar_t optionName[] = L"ImageQuality";
            option.pstrName = optionName;
            VARIANT value;
            VariantInit(&value);
            value.vt = VT_R4;
            value.fltVal = (std::min)(1.0f, (std::max)(0.0f, request.quality));
            // Not every encoder version has this option; ignore a failure.
            properties->Write(1, &option, &value);
        }
        if (SUCCEEDED(hr))
        {
            step = "initialize frame";
            hr = frame->Initialize(properties.Get());
        }
        if (SUCCEEDED(hr))
        {
            step = "set size";
            hr = frame->SetSize(width, height);
        }
        if (SUCCEEDED(hr))
        {
            WICPixelFormatGUID format = hasAlpha ? GUID_WICPixelFormat32bppBGRA : GUID_WICPixelFormat32bppBGR;
            step = "set pixel format";
            hr = frame->SetPixelFormat(&format);
        }
        if (SUCCEEDED(hr))
        {
            step = "wrap pixels";
            hr = factory->CreateBitmapFromMemory(width, height, hasAlpha ? GUID_WICPixelFormat32bppPBGRA : GUID_WICPixelFormat32bppBGR,
                                                 stride, static_cast<UINT>(pixels.size()), pixels.data(), &bitmap);
        }
        if (SUCCEEDED(hr))
        {
            step = "encode image";
            hr = frame->WriteSource(bitmap.Get(), nullptr);
        }
        if (SUCCEEDED(hr))
        {
            step = "encode image";
            hr = frame->Commit();
        }
        if (SUCCEEDED(hr))
        {
            step = "finish file";
            hr = encoder->Commit();
        }

        if (FAILED(hr))
        {
            // Release the file before removing the partial output.
            frame.Reset();
            encoder.Reset();
            stream.Reset();
            DeleteFileW(path.c_str());

            // The HEIF container encoder can be present without the HEVC codec it needs.
            const bool encodeStep = string(step) == "encode image" || string(step) == "finish file";
            TWK_THROW_STREAM(IOException, "IOwic: cannot write \"" << filename << "\": failed to " << step << " (" << hresultText(hr)
                                                                   << ")." << (encodeStep ? string(" ") + missingEncoderHelp : string()));
        }
    }

} // namespace TwkFB
