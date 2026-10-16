//
//  Copyright (c) 2011 Tweak Software.
//  All rights reserved.
//
//  SPDX-License-Identifier: Apache-2.0
//
//
#include <RvCommon/DesktopVideoModule.h>
#include <RvCommon/DesktopVideoDevice.h>
#include <RvCommon/GLView.h>
#include <IPCore/ImageRenderer.h>
#include <stl_ext/string_algo.h>
#include <QtGui/QtGui>
#include <map>
#include <boost/algorithm/string.hpp>

#include <QtWidgets/QApplication>
#include <QScreen>

namespace Rv
{
    using namespace std;
    using namespace boost;

    //----------------------------------------------------------------------

    // force intel code path for this commit
    static bool isDarwinArm() { return true; }

    static bool isDarwinIntel() { return true; }

    static bool useQtOnDarwinArm() { return true; }

    DesktopVideoModule::DesktopVideoModule(NativeDisplayPtr np, QTGLVideoDevice* shareDevice)
        : VideoModule()
    {
        m_devices = DesktopVideoDevice::createDesktopVideoDevices(this, shareDevice);
    }

    DesktopVideoModule::~DesktopVideoModule() {}

    string DesktopVideoModule::name() const { return "Desktop"; }

    void DesktopVideoModule::open() {}

    void DesktopVideoModule::close() {}

    bool DesktopVideoModule::isOpen() const { return true; }

    TwkApp::VideoDevice* DesktopVideoModule::deviceFromPosition(int x, int y) const
    {
        return deviceFromScreen(QGuiApplication::screenAt(QPoint(x, y)));
    }

    TwkApp::VideoDevice* DesktopVideoModule::deviceFromScreen(const QScreen* screen) const
    {
        const int index = QGuiApplication::screens().indexOf(const_cast<QScreen*>(screen));
        if (index < 0)
            return 0;

        for (int i = 0; i < m_devices.size(); ++i)
        {
            //
            //  These devices may be NVDesktopVideoDevices or
            //  DeskTopVideoDevices.
            //
            if (DesktopVideoDevice* dd = dynamic_cast<DesktopVideoDevice*>(m_devices[i]))
            {
                if (dd->qtScreen() == index)
                    return m_devices[i];
            }
        }

        return 0;
    }
} // namespace Rv
