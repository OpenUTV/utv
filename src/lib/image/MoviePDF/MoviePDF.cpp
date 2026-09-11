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
#include <iostream>
#include <sstream>

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

    void MoviePDF::renderPage(int pageNumber, FrameBuffer& fb)
    {
        lock_guard<mutex> lock(m_mutex);

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
        int w = static_cast<int>(round(pw * scale));
        int h = static_cast<int>(round(ph * scale));
        if (w <= 0)
            w = 1;
        if (h <= 0)
            h = 1;

        fb.restructure(w, h, 0, 4, FrameBuffer::UCHAR, nullptr, nullptr, FrameBuffer::TOPLEFT);

        CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        CGContextRef ctx = CGBitmapContextCreate(fb.pixels<unsigned char>(), w, h, 8, fb.scanlinePaddedSize(), cs,
                                                 kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);

        if (!ctx)
        {
            CGColorSpaceRelease(cs);
            TWK_THROW_STREAM(IOException, "MoviePDF: Failed to create bitmap render context for page " << pageNumber);
        }

        // Draw solid white background for presentation
        CGContextSetRGBFillColor(ctx, 1.0, 1.0, 1.0, 1.0);
        CGContextFillRect(ctx, CGRectMake(0, 0, w, h));

        // Draw PDF page top-down into context
        CGContextSaveGState(ctx);
        CGContextTranslateCTM(ctx, 0, h);
        CGContextScaleCTM(ctx, 1.0, -1.0);

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
        int w = static_cast<int>(round(ptSize.width() * scale));
        int h = static_cast<int>(round(ptSize.height() * scale));
        if (w <= 0)
            w = 1;
        if (h <= 0)
            h = 1;

        QImage img = m_qtDoc->render(pageIndex, QSize(w, h));
        if (img.format() != QImage::Format_RGBA8888)
        {
            img = img.convertToFormat(QImage::Format_RGBA8888);
        }

        fb.restructure(w, h, 0, 4, FrameBuffer::UCHAR, nullptr, nullptr, FrameBuffer::TOPLEFT);
        for (int y = 0; y < h; ++y)
        {
            memcpy(fb.scanline<unsigned char>(y), img.constScanLine(y), w * 4);
        }
#endif

        identifier(pageNumber, fb.idstream());
        fb.addAttribute(new IntAttribute("PDF/Page", pageNumber));
        fb.addAttribute(new IntAttribute("PDF/PageCount", m_info.end));
        fb.addAttribute(new FloatAttribute("PDF/DPI", m_dpi));
        fb.addAttribute(new StringAttribute("File", m_filename));
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

    void MoviePDF::identifier(int frame, ostream& os) const { os << frame << "@" << static_cast<int>(m_dpi) << "dpi:" << m_filename; }

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
