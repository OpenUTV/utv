//
// Copyright (C) 2026 The OpenUTV Contributors. All Rights Reserved.
// SPDX-License-Identifier: Apache-2.0
//
#include <MovieRED/MovieRED.h>
#include <iostream>
#include <vector>
#include <string>
#include <boost/program_options.hpp>
#include <boost/algorithm/string.hpp>
#include <boost/algorithm/string/split.hpp>

using namespace TwkFB;
using namespace std;
using namespace boost::program_options;
using namespace boost::algorithm;
using namespace boost;

extern "C"
{

#ifdef PLATFORM_WINDOWS
    __declspec(dllexport) TwkMovie::MovieIO* create();
    __declspec(dllexport) void destroy(TwkMovie::MovieREDIO*);
#endif

    TwkMovie::MovieIO* create()
    {
        string format;
        string res;

        if (const char* args = getenv("MOVIERED_ARGS"))
        {
            try
            {
                vector<string> buffer;
                split(buffer, args, is_any_of(" "), token_compress_on);

                vector<const char*> newargs(buffer.size() + 1);

                newargs[0] = "";
                for (size_t i = 0; i < buffer.size(); i++)
                    newargs[i + 1] = buffer[i].c_str();

                const char** argv = &newargs.front();
                int argc = static_cast<int>(newargs.size());

                options_description desc("");
                desc.add_options()("format", value<string>()->default_value(format), "")("resolution", value<string>()->default_value(res),
                                                                                         "");

                variables_map vm;
                store(parse_command_line(argc, argv, desc), vm);
                notify(vm);

                format = vm["format"].as<string>();
                if (vm.count("resolution"))
                    res = vm["resolution"].as<string>();
            }
            catch (std::exception& e)
            {
                cout << "ERROR: MOVIERED_ARGS: " << e.what() << endl;
            }
            catch (...)
            {
                cout << "ERROR: bad MOVIERED_ARGS = \"" << args << "\"" << endl;
            }
        }

        TwkMovie::MovieRED::Format pixelFormat = TwkMovie::MovieRED::RGB16;
        if (format == "RGBA16")
            pixelFormat = TwkMovie::MovieRED::RGBA16;
        else if (format == "RGB_HALF" || format == "HALF")
            pixelFormat = TwkMovie::MovieRED::RGB_HALF;
        else if (format == "RGBA8")
            pixelFormat = TwkMovie::MovieRED::RGBA8;
        else
            pixelFormat = TwkMovie::MovieRED::RGB16;

        TwkMovie::MovieRED::pixelFormat = pixelFormat;

        if (res == "half")
            TwkMovie::MovieRED::resolution = TwkMovie::MovieRED::HALF_RES;
        else if (res == "quarter")
            TwkMovie::MovieRED::resolution = TwkMovie::MovieRED::QUARTER_RES;
        else
            TwkMovie::MovieRED::resolution = TwkMovie::MovieRED::FULL_RES;

        return new TwkMovie::MovieREDIO();
    }

    void destroy(TwkMovie::MovieREDIO* plug) { delete plug; }

} // extern "C"
