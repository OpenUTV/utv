//
// Copyright Contributors to the UTV Project
// SPDX-License-Identifier: Apache-2.0
//

#ifndef __RvCommon__MacNativeFileDialog__h__
#define __RvCommon__MacNativeFileDialog__h__

#ifdef PLATFORM_DARWIN

#include <QtCore/QStringList>
#include <QtCore/QString>

namespace Rv
{

    QStringList runMacNativeOpenDialog(const QString& caption, const QString& initialPath, const QStringList& allowedExtensions,
                                       bool canChooseFiles, bool canChooseDirectories, bool allowsMultipleSelection);

} // namespace Rv

#endif // PLATFORM_DARWIN

#endif // __RvCommon__MacNativeFileDialog__h__
