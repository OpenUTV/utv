//*****************************************************************************/
//
// Filename: FastMemcpy.h
//
// Copyright (c) 2019 Autodesk, Inc.
// All rights reserved.
//
// SPDX-License-Identifier: Apache-2.0
//
//*****************************************************************************/

#include <cstdio>
#include <stdint.h>
#include <vector>

#include <TwkUtil/Timer.h>
#include <TwkFB/TwkFBThreadPool.h>
#include <TwkFB/FastMemcpy.h>

namespace
{
    //  Check an expansion against the source, for the plain and threaded
    //  versions. The source rows are padded and the width is odd so a wrong
    //  stride or row size shows up as shifted pixels.
    template <typename T, typename Expand> bool checkExpansion(const char* name, T alpha, Expand plain, Expand threaded)
    {
        const size_t width = 1021;
        const size_t height = 37;
        const size_t rowElems = width * 3 + 5;

        std::vector<T> src(rowElems * height, T(0));
        for (size_t y = 0; y < height; y++)
            for (size_t x = 0; x < width * 3; x++)
                src[y * rowElems + x] = static_cast<T>(y * 251 + x * 7 + 1);

        Expand fns[] = {plain, threaded};
        for (Expand fn : fns)
        {
            std::vector<T> dst(width * height * 4 + 1, T(0));
            const T canary = static_cast<T>(0x5A);
            dst.back() = canary;

            fn(width, height, reinterpret_cast<const uint8_t*>(src.data()), rowElems * sizeof(T), dst.data(), alpha);

            for (size_t y = 0; y < height; y++)
            {
                for (size_t x = 0; x < width; x++)
                {
                    const T* in = &src[y * rowElems + x * 3];
                    const T* out = &dst[(y * width + x) * 4];
                    if (out[0] != in[0] || out[1] != in[1] || out[2] != in[2] || out[3] != alpha)
                    {
                        printf("FAILED: %s wrong pixel at %zu,%zu\n", name, x, y);
                        return false;
                    }
                }
            }

            if (dst.back() != canary)
            {
                printf("FAILED: %s wrote past the end of the destination\n", name);
                return false;
            }
        }

        printf("%s: ok\n", name);
        return true;
    }
} // namespace

bool TestExpandRGBToRGBA()
{
    using namespace TwkUtil;

    TwkFB::ThreadPool::initialize();

    bool ok = true;
    ok = checkExpansion<uint8_t>("expand_rgb_to_rgba_8bit", 0xFF, expand_rgb_to_rgba_8bit, expand_rgb_to_rgba_8bit_MP) && ok;
    ok = checkExpansion<uint16_t>("expand_rgb_to_rgba_16bit", 0xFFFF, expand_rgb_to_rgba_16bit, expand_rgb_to_rgba_16bit_MP) && ok;
    ok = checkExpansion<uint32_t>("expand_rgb_to_rgba_32bit", 0x3F800000, expand_rgb_to_rgba_32bit, expand_rgb_to_rgba_32bit_MP) && ok;

    //  One 8192 x 8192 8-bit RGB frame: this must stay well under one 60 fps
    //  frame or expanding costs more than the upload it speeds up.
    const size_t size = 8192;
    const size_t tryCount = 10;
    std::vector<uint8_t> src(size * size * 3, 128);
    std::vector<uint8_t> dst(size * size * 4);

    Timer timer(true);
    for (size_t i = 0; i < tryCount; i++)
        expand_rgb_to_rgba_8bit_MP(size, size, src.data(), size * 3, dst.data(), 0xFF);
    printf("expand_rgb_to_rgba_8bit_MP() for 8192x8192 frame:%f sec/frame\n", timer.elapsed() / tryCount);

    TwkFB::ThreadPool::shutdown();

    return ok;
}

void TestFastMemcpy()
{
    using namespace TwkUtil;

    printf("Test TestPxlMemcpy\n");

    TwkFB::ThreadPool::initialize();

    const size_t bufferSize = 7680 * 4320 * 4 * 2;
    const size_t tryCount = 100;

    uint8_t* srcBuffer = new uint8_t[bufferSize];
    uint8_t* interBuffer = new uint8_t[bufferSize];
    uint8_t* dstBuffer = new uint8_t[bufferSize];

    Timer timer(true);
    for (size_t i = 0; i < tryCount; i++)
        FastMemcpy(dstBuffer, srcBuffer, bufferSize);
    printf("PxlMemcpy() for 8k frame:%f sec/frame\n", timer.elapsed() / tryCount);

    Timer timer1(true);
    for (size_t i = 0; i < tryCount; i++)
        FastMemcpy_MP(dstBuffer, srcBuffer, bufferSize);
    printf("PxlMemcpy_MP() for 8k frame:%f sec/frame\n", timer1.elapsed() / tryCount);

    delete[] srcBuffer;
    delete[] interBuffer;
    delete[] dstBuffer;

    TwkFB::ThreadPool::shutdown();
}
