//
// Copyright (C) 2026 OpenUTV Authors. All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//
#include <MoviePDF/MoviePDF.h>
#include <TwkFB/Exception.h>
#include <TwkFB/Operations.h>
#include <algorithm>
#include <cmath>
#include <cstring>
#include <iostream>
#include <sstream>

#if defined(_WIN32)
#define strcasecmp _stricmp
#else
#include <strings.h>
#endif

#if defined(PLATFORM_DARWIN)
#include <CoreFoundation/CoreFoundation.h>
#endif

namespace TwkMovie
{
    using namespace std;
    using namespace TwkFB;

    MoviePDF::MoviePDF()
        : MovieReader()
        , m_dpi(144.0f)
        , m_autoCrop(true)
        , m_marginPts(18)
#if defined(PLATFORM_DARWIN)
        , m_cgDoc(nullptr)
#endif
    {
        m_threadSafe = true;
    }

    MoviePDF::~MoviePDF()
    {
#if defined(PLATFORM_DARWIN)
        if (m_cgDoc)
        {
            CGPDFDocumentRelease(m_cgDoc);
            m_cgDoc = nullptr;
        }
#endif
    }

    MovieReader* MoviePDF::clone() const
    {
        MoviePDF* mov = new MoviePDF();
        if (!filename().empty())
        {
            mov->open(filename(), m_info, m_request);
        }
        return mov;
    }

    void MoviePDF::postPreloadOpen(const MovieInfo& /*info*/, const ReadRequest& request) { m_request = request; }

    void MoviePDF::preloadOpen(const std::string& filename, const ReadRequest& request)
    {
        lock_guard<mutex> lock(m_mutex);
        m_filename = filename;
        m_request = request;

        // Determine rendering DPI (default 144.0 DPI = 2x Retina scale for crisp text)
        m_dpi = 144.0f;
        if (const char* envDpi = getenv("RV_PDF_DPI"))
        {
            float val = static_cast<float>(atof(envDpi));
            if (val >= 36.0f && val <= 1200.0f)
                m_dpi = val;
        }
        else if (const char* envDpi2 = getenv("UTV_PDF_DPI"))
        {
            float val = static_cast<float>(atof(envDpi2));
            if (val >= 36.0f && val <= 1200.0f)
                m_dpi = val;
        }

        m_autoCrop = true;
        if (const char* envCrop = getenv("RV_PDF_AUTOCROP"))
        {
            if (strcmp(envCrop, "0") == 0 || strcasecmp(envCrop, "false") == 0 || strcasecmp(envCrop, "no") == 0)
                m_autoCrop = false;
        }
        else if (const char* envCrop2 = getenv("UTV_PDF_AUTOCROP"))
        {
            if (strcmp(envCrop2, "0") == 0 || strcasecmp(envCrop2, "false") == 0 || strcasecmp(envCrop2, "no") == 0)
                m_autoCrop = false;
        }

        m_marginPts = 18;
        if (const char* envMargin = getenv("RV_PDF_MARGIN"))
        {
            m_marginPts = max(0, atoi(envMargin));
        }
        else if (const char* envMargin2 = getenv("UTV_PDF_MARGIN"))
        {
            m_marginPts = max(0, atoi(envMargin2));
        }

        int pageCount = 0;
        int firstPageW = 0;
        int firstPageH = 0;

#if defined(PLATFORM_DARWIN)
        CFStringRef pathStr = CFStringCreateWithCString(kCFAllocatorDefault, filename.c_str(), kCFStringEncodingUTF8);
        if (!pathStr)
        {
            TWK_THROW_STREAM(IOException, "MoviePDF: Cannot encode filename: " << filename);
        }
        CFURLRef url = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, pathStr, kCFURLPOSIXPathStyle, false);
        CFRelease(pathStr);
        if (!url)
        {
            TWK_THROW_STREAM(IOException, "MoviePDF: Cannot create URL for file: " << filename);
        }

        m_cgDoc = CGPDFDocumentCreateWithURL(url);
        CFRelease(url);

        if (!m_cgDoc)
        {
            TWK_THROW_STREAM(IOException, "MoviePDF: Failed to open PDF document: " << filename);
        }

        pageCount = static_cast<int>(CGPDFDocumentGetNumberOfPages(m_cgDoc));
        if (pageCount <= 0)
        {
            CGPDFDocumentRelease(m_cgDoc);
            m_cgDoc = nullptr;
            TWK_THROW_STREAM(IOException, "MoviePDF: Document contains no pages: " << filename);
        }

        CGPDFPageRef page1 = CGPDFDocumentGetPage(m_cgDoc, 1);
        if (page1)
        {
            CGRect cropBox = CGPDFPageGetBoxRect(page1, kCGPDFCropBox);
            if (CGRectIsEmpty(cropBox))
                cropBox = CGPDFPageGetBoxRect(page1, kCGPDFMediaBox);

            int rotation = CGPDFPageGetRotationAngle(page1);
            float pw = cropBox.size.width;
            float ph = cropBox.size.height;
            if (rotation == 90 || rotation == 270)
            {
                swap(pw, ph);
            }

            float scale = m_dpi / 72.0f;
            firstPageW = static_cast<int>(round(pw * scale));
            firstPageH = static_cast<int>(round(ph * scale));
        }
#elif defined(HAVE_QTPDF)
        m_qtDoc = make_unique<QPdfDocument>();
        auto status = m_qtDoc->load(QString::fromUtf8(filename.c_str()));
        if (status != QPdfDocument::Error::None)
        {
            m_qtDoc.reset();
            TWK_THROW_STREAM(IOException,
                             "MoviePDF: Failed to open PDF via QtPdf (error " << static_cast<int>(status) << "): " << filename);
        }

        pageCount = m_qtDoc->pageCount();
        if (pageCount <= 0)
        {
            m_qtDoc.reset();
            TWK_THROW_STREAM(IOException, "MoviePDF: Document contains no pages: " << filename);
        }

        QSizeF ptSize = m_qtDoc->pagePointSize(0);
        float scale = m_dpi / 72.0f;
        firstPageW = static_cast<int>(round(ptSize.width() * scale));
        firstPageH = static_cast<int>(round(ptSize.height() * scale));
#else
        TWK_THROW_STREAM(IOException, "MoviePDF: No PDF rendering backend available.");
#endif

        if (firstPageW <= 0)
            firstPageW = 1224;
        if (firstPageH <= 0)
            firstPageH = 1584;

        if (m_autoCrop && pageCount > 0)
        {
            int rw = 0, rh = 0;
            vector<uint32_t> tempPixels;
            renderRawPage(1, rw, rh, tempPixels);
            if (rw > 0 && rh > 0 && !tempPixels.empty())
            {
                int minX, maxX, minY, maxY;
                findContentBox(tempPixels.data(), rw, rh, minX, maxX, minY, maxY);
                if (minX <= maxX && minY <= maxY)
                {
                    int pad = static_cast<int>(round(m_marginPts * (m_dpi / 72.0f)));
                    int cMinX = max(0, minX - pad);
                    int cMaxX = min(rw - 1, maxX + pad);
                    int cMinY = max(0, minY - pad);
                    int cMaxY = min(rh - 1, maxY + pad);
                    firstPageW = cMaxX - cMinX + 1;
                    firstPageH = cMaxY - cMinY + 1;
                }
            }
        }

        m_info.start = 1;
        m_info.end = pageCount;
        m_info.inc = 1;
        m_info.fps = 1.0;
        m_info.width = firstPageW;
        m_info.height = firstPageH;
        m_info.uncropWidth = firstPageW;
        m_info.uncropHeight = firstPageH;
        m_info.uncropX = 0;
        m_info.uncropY = 0;
        m_info.pixelAspect = 1.0f;
        m_info.video = true;
        m_info.audio = false;
        m_info.orientation = FrameBuffer::TOPLEFT;
        m_info.numChannels = 4;
        m_info.dataType = FrameBuffer::UCHAR;
        m_info.slowRandomAccess = false;
    }

    void MoviePDF::findContentBox(const uint32_t* pixels, int w, int h, int& minX, int& maxX, int& minY, int& maxY) const
    {
        minX = w;
        maxX = -1;
        minY = h;
        maxY = -1;

        for (int y = 0; y < h; ++y)
        {
            const uint32_t* row = pixels + y * w;
            for (int x = 0; x < w; ++x)
            {
                uint32_t p = row[x];
                uint8_t r = p & 0xFF;
                uint8_t g = (p >> 8) & 0xFF;
                uint8_t b = (p >> 16) & 0xFF;
                if (r < 248 || g < 248 || b < 248)
                {
                    if (x < minX)
                        minX = x;
                    if (x > maxX)
                        maxX = x;
                    if (y < minY)
                        minY = y;
                    if (y > maxY)
                        maxY = y;
                }
            }
        }
    }

    void MoviePDF::renderRawPage(int pageNumber, int& w, int& h, vector<uint32_t>& pixels)
    {
#if defined(PLATFORM_DARWIN)
        if (!m_cgDoc)
        {
            TWK_THROW_STREAM(IOException, "MoviePDF: Document is not open: " << m_filename);
        }

        CGPDFPageRef page = CGPDFDocumentGetPage(m_cgDoc, pageNumber);
        if (!page)
        {
            TWK_THROW_STREAM(IOException, "MoviePDF: Cannot retrieve page " << pageNumber << " in " << m_filename);
        }

        CGRect cropBox = CGPDFPageGetBoxRect(page, kCGPDFCropBox);
        if (CGRectIsEmpty(cropBox))
            cropBox = CGPDFPageGetBoxRect(page, kCGPDFMediaBox);

        int rotation = CGPDFPageGetRotationAngle(page);
        float pw = cropBox.size.width;
        float ph = cropBox.size.height;
        if (rotation == 90 || rotation == 270)
        {
            swap(pw, ph);
        }

        float scale = m_dpi / 72.0f;
        w = static_cast<int>(round(pw * scale));
        h = static_cast<int>(round(ph * scale));
        if (w <= 0)
            w = 1;
        if (h <= 0)
            h = 1;

        pixels.resize(w * h);

        CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        CGContextRef ctx = CGBitmapContextCreate(pixels.data(), w, h, 8, w * sizeof(uint32_t), cs,
                                                 kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);

        if (!ctx)
        {
            CGColorSpaceRelease(cs);
            TWK_THROW_STREAM(IOException, "MoviePDF: Failed to create bitmap render context for page " << pageNumber);
        }

        // Draw solid white background for presentation
        CGContextSetRGBFillColor(ctx, 1.0, 1.0, 1.0, 1.0);
        CGContextFillRect(ctx, CGRectMake(0, 0, w, h));

        // Draw PDF page directly using drawing transform
        CGContextSaveGState(ctx);
        CGAffineTransform t = CGPDFPageGetDrawingTransform(page, kCGPDFCropBox, CGRectMake(0, 0, w, h), 0, true);
        CGContextConcatCTM(ctx, t);
        CGContextDrawPDFPage(ctx, page);
        CGContextRestoreGState(ctx);

        CGContextRelease(ctx);
        CGColorSpaceRelease(cs);

#elif defined(HAVE_QTPDF)
        if (!m_qtDoc)
        {
            TWK_THROW_STREAM(IOException, "MoviePDF: Document is not open: " << m_filename);
        }

        int pageIndex = pageNumber - 1;
        QSizeF ptSize = m_qtDoc->pagePointSize(pageIndex);
        float scale = m_dpi / 72.0f;
        w = static_cast<int>(round(ptSize.width() * scale));
        h = static_cast<int>(round(ptSize.height() * scale));
        if (w <= 0)
            w = 1;
        if (h <= 0)
            h = 1;

        QImage img = m_qtDoc->render(pageIndex, QSize(w, h));
        if (img.format() != QImage::Format_RGBA8888)
        {
            img = img.convertToFormat(QImage::Format_RGBA8888);
        }

        pixels.resize(w * h);
        for (int y = 0; y < h; ++y)
        {
            memcpy(&pixels[y * w], img.constScanLine(y), w * sizeof(uint32_t));
        }
#endif
    }

    void MoviePDF::renderPage(int pageNumber, FrameBuffer& fb)
    {
        lock_guard<mutex> lock(m_mutex);

        int rw = 0, rh = 0;
        vector<uint32_t> tempPixels;
        renderRawPage(pageNumber, rw, rh, tempPixels);

        if (m_autoCrop)
        {
            int minX, maxX, minY, maxY;
            findContentBox(tempPixels.data(), rw, rh, minX, maxX, minY, maxY);

            if (minX <= maxX && minY <= maxY)
            {
                int pad = static_cast<int>(round(m_marginPts * (m_dpi / 72.0f)));
                int cMinX = max(0, minX - pad);
                int cMaxX = min(rw - 1, maxX + pad);
                int cMinY = max(0, minY - pad);
                int cMaxY = min(rh - 1, maxY + pad);
                int cw = cMaxX - cMinX + 1;
                int ch = cMaxY - cMinY + 1;

                fb.restructure(cw, ch, 0, 4, FrameBuffer::UCHAR, nullptr, nullptr, FrameBuffer::TOPLEFT);
                for (int y = 0; y < ch; ++y)
                {
                    memcpy(fb.scanline<unsigned char>(y), &tempPixels[(cMinY + y) * rw + cMinX], cw * sizeof(uint32_t));
                }
            }
            else
            {
                fb.restructure(rw, rh, 0, 4, FrameBuffer::UCHAR, nullptr, nullptr, FrameBuffer::TOPLEFT);
                memcpy(fb.pixels<unsigned char>(), tempPixels.data(), rw * rh * sizeof(uint32_t));
            }
        }
        else
        {
            fb.restructure(rw, rh, 0, 4, FrameBuffer::UCHAR, nullptr, nullptr, FrameBuffer::TOPLEFT);
            memcpy(fb.pixels<unsigned char>(), tempPixels.data(), rw * rh * sizeof(uint32_t));
        }

        identifier(pageNumber, fb.idstream());
        fb.addAttribute(new IntAttribute("PDF/Page", pageNumber));
        fb.addAttribute(new IntAttribute("PDF/PageCount", m_info.end));
        fb.addAttribute(new FloatAttribute("PDF/DPI", m_dpi));
        fb.addAttribute(new StringAttribute("File", m_filename));
        if (m_autoCrop)
        {
            fb.addAttribute(new IntAttribute("PDF/AutoCrop", 1));
            fb.addAttribute(new IntAttribute("PDF/MarginPts", m_marginPts));
        }
    }

    void MoviePDF::imagesAtFrame(const ReadRequest& request, FrameBufferVector& fbs)
    {
        int frame = max(m_info.start, min(request.frame, m_info.end));
        fbs.resize(1);
        if (!fbs.front())
            fbs.front() = new FrameBuffer();
        renderPage(frame, *fbs.front());
    }

    void MoviePDF::identifiersAtFrame(const ReadRequest& request, IdentifierVector& ids)
    {
        int frame = max(m_info.start, min(request.frame, m_info.end));
        ostringstream str;
        identifier(frame, str);
        ids.resize(1);
        ids.front() = str.str();
    }

    void MoviePDF::identifier(int frame, ostream& os) const
    {
        os << frame << "@" << static_cast<int>(m_dpi) << "dpi:crop=" << (m_autoCrop ? m_marginPts : -1) << ":" << m_filename;
    }

    //--------------------------------------------------------------------------
    // MoviePDFIO
    //--------------------------------------------------------------------------

    MoviePDFIO::MoviePDFIO()
        : MovieIO("MoviePDF", "m0")
    {
        StringPairVector video;
        StringPairVector audio;
        unsigned int capabilities = MovieIO::MovieRead | MovieIO::AttributeRead;
        addType("pdf", "Portable Document Format", capabilities, video, audio);
        addType("PDF", "Portable Document Format", capabilities, video, audio);
    }

    MoviePDFIO::~MoviePDFIO() {}

    string MoviePDFIO::about() const { return "PDF Document Reader"; }

    MovieReader* MoviePDFIO::movieReader() const { return new MoviePDF(); }

    MovieWriter* MoviePDFIO::movieWriter() const { return nullptr; }

    void MoviePDFIO::getMovieInfo(const string& filename, MovieInfo& minfo) const
    {
        MoviePDF reader;
        reader.open(filename, minfo);
        minfo = reader.info();
    }

} // namespace TwkMovie
