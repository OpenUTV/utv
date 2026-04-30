//
// Copyright (C) 2024  Autodesk, Inc. All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

#pragma once

#include "TwkApp/VideoModule.h"

#include <string>

#include <Processing.NDI.Lib.h>
#include <Processing.NDI.DynamicLoad.h>

namespace NDI
{
    extern const NDIlib_v6* p_NDI_lib;

    class NDIModule : public TwkApp::VideoModule
    {
    public:
        NDIModule();
        virtual ~NDIModule() final;

        [[nodiscard]] std::string name() const override;
        [[nodiscard]] std::string SDKIdentifier() const override;
        [[nodiscard]] std::string SDKInfo() const override;
        void open() override;
        void close() override;
        [[nodiscard]] bool isOpen() const override;

    private:
        bool m_NDIlib_initialized{false};
    };

} // namespace NDI
