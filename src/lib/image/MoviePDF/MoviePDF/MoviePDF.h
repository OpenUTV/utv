//
// Copyright (C) 2026 OpenUTV Authors. All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//
#ifndef __MoviePDF__MoviePDF__h__
#define __MoviePDF__MoviePDF__h__

#include <TwkMovie/MovieIO.h>
#include <TwkMovie/MovieReader.h>
#include <mutex>
#include <string>

#if defined(PLATFORM_DARWIN)
#include <CoreGraphics/CoreGraphics.h>
#endif

#if defined(HAVE_QTPDF)
#include <QtPdf/QPdfDocument>
#include <memory>
#endif

namespace TwkMovie
{

    class MoviePDF : public MovieReader
    {
    public:
        MoviePDF();
        virtual ~MoviePDF();

        // MovieReader API
        virtual MovieReader* clone() const;
        virtual void preloadOpen(const std::string& filename, const ReadRequest& request);
        virtual void postPreloadOpen(const MovieInfo& info, const ReadRequest& request);

        // Movie API
        virtual void imagesAtFrame(const ReadRequest& request, FrameBufferVector& fbs);
        virtual void identifiersAtFrame(const ReadRequest& request, IdentifierVector& ids);

    private:
        void identifier(int frame, std::ostream& os) const;
        void renderPage(int pageNumber, TwkFB::FrameBuffer& fb);

        float m_dpi;
        mutable std::mutex m_mutex;

#if defined(PLATFORM_DARWIN)
        CGPDFDocumentRef m_cgDoc;
#endif

#if defined(HAVE_QTPDF)
        std::unique_ptr<QPdfDocument> m_qtDoc;
#endif
    };

    class MoviePDFIO : public MovieIO
    {
    public:
        MoviePDFIO();
        virtual ~MoviePDFIO();

        virtual std::string about() const;
        virtual MovieReader* movieReader() const;
        virtual MovieWriter* movieWriter() const;
        virtual void getMovieInfo(const std::string& filename, MovieInfo&) const;
    };

} // namespace TwkMovie

#endif // __MoviePDF__MoviePDF__h__
