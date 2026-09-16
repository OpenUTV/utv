//******************************************************************************
// Copyright (c) 2026 The OpenUTV Contributors. All rights reserved.
//
// SPDX-License-Identifier: Apache-2.0
//
//******************************************************************************
#ifndef __MovieBRAW__MovieBRAW__h__
#define __MovieBRAW__MovieBRAW__h__

#include <string>
#include <TwkMovie/MovieReader.h>
#include <TwkMovie/MovieIO.h>

namespace TwkMovie
{

    class MovieBRAW : public MovieReader
    {
    public:
        MovieBRAW();
        virtual ~MovieBRAW();

        enum Format
        {
            RGBA8,
            RGBA16,
            RGBA_FLOAT
        };

        // MovieReader API
        virtual MovieReader* clone() const override;
        virtual void preloadOpen(const std::string& filename, const ReadRequest& request) override;
        virtual void postPreloadOpen(const MovieInfo& as, const ReadRequest& request) override;

        // Movie API
        virtual void imagesAtFrame(const ReadRequest& request, FrameBufferVector&) override;
        virtual void identifiersAtFrame(const ReadRequest& request, IdentifierVector&) override;

        static Format pixelFormat;

    private:
        void identifier(int frame, std::ostream&);

        struct Impl;
        Impl* m_impl;
    };

    class MovieBRAWIO : public MovieIO
    {
    public:
        MovieBRAWIO();
        virtual ~MovieBRAWIO();

        virtual std::string about() const override;
        virtual MovieReader* movieReader() const override;
        virtual MovieWriter* movieWriter() const override;
        virtual void getMovieInfo(const std::string& filename, MovieInfo&) const override;
    };

} // namespace TwkMovie

#endif // __MovieBRAW__MovieBRAW__h__
