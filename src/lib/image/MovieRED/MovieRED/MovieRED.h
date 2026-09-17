//******************************************************************************
// Copyright (c) 2026 The OpenUTV Contributors. All rights reserved.
//
// SPDX-License-Identifier: Apache-2.0
//
//******************************************************************************
#ifndef __MovieRED__MovieRED__h__
#define __MovieRED__MovieRED__h__

#include <string>
#include <TwkMovie/MovieReader.h>
#include <TwkMovie/MovieIO.h>

namespace TwkMovie
{

    class MovieRED : public MovieReader
    {
    public:
        MovieRED();
        virtual ~MovieRED();

        enum Format
        {
            RGB16,
            RGBA16,
            RGB_HALF,
            RGBA8
        };

        enum Resolution
        {
            FULL_RES,
            HALF_RES,
            QUARTER_RES,
            EIGHTH_RES
        };

        // MovieReader API
        virtual MovieReader* clone() const override;
        virtual void preloadOpen(const std::string& filename, const ReadRequest& request) override;
        virtual void postPreloadOpen(const MovieInfo& as, const ReadRequest& request) override;

        // Movie API
        virtual void imagesAtFrame(const ReadRequest& request, FrameBufferVector&) override;
        virtual void identifiersAtFrame(const ReadRequest& request, IdentifierVector&) override;

        static Format pixelFormat;
        static Resolution resolution;

    private:
        void identifier(int frame, std::ostream&);

        struct Impl;
        Impl* m_impl;
    };

    class MovieREDIO : public MovieIO
    {
    public:
        MovieREDIO();
        virtual ~MovieREDIO();

        virtual std::string about() const override;
        virtual MovieReader* movieReader() const override;
        virtual MovieWriter* movieWriter() const override;
        virtual void getMovieInfo(const std::string& filename, MovieInfo&) const override;
    };

} // namespace TwkMovie

#endif // __MovieRED__MovieRED__h__
