//
// Copyright (C) 2026 The OpenUTV Contributors. All Rights Reserved.
// SPDX-License-Identifier: Apache-2.0
//
#include <MovieBRAW/MovieBRAW.h>
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
    __declspec(dllexport) void destroy(TwkMovie::MovieBRAWIO*);
#endif

    TwkMovie::MovieIO* create()
    {
        string format;

        if (const char* args = getenv("MOVIEBRAW_ARGS"))
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
                desc.add_options()("format", value<string>()->default_value(format), "");

                variables_map vm;
                store(parse_command_line(argc, argv, desc), vm);
                notify(vm);

                format = vm["format"].as<string>();
            }
            catch (std::exception& e)
            {
                cout << "ERROR: MOVIEBRAW_ARGS: " << e.what() << endl;
            }
            catch (...)
            {
                cout << "ERROR: bad MOVIEBRAW_ARGS = \"" << args << "\"" << endl;
            }
        }

        TwkMovie::MovieBRAW::Format pixelFormat = TwkMovie::MovieBRAW::RGBA8;
        if (format == "RGBA16")
            pixelFormat = TwkMovie::MovieBRAW::RGBA16;
        else if (format == "RGBA_FLOAT" || format == "RGB_FLOAT")
            pixelFormat = TwkMovie::MovieBRAW::RGBA_FLOAT;
        else
            pixelFormat = TwkMovie::MovieBRAW::RGBA8;

        TwkMovie::MovieBRAW::pixelFormat = pixelFormat;

        return new TwkMovie::MovieBRAWIO();
    }

    void destroy(TwkMovie::MovieBRAWIO* plug) { delete plug; }

} // extern "C"
