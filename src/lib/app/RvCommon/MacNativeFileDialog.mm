//
// Copyright Contributors to the UTV Project
// SPDX-License-Identifier: Apache-2.0
//

#ifdef PLATFORM_DARWIN

#import <AppKit/AppKit.h>
#include <RvCommon/MacNativeFileDialog.h>

namespace Rv
{

    QStringList runMacNativeOpenDialog(
        const QString& caption,
        const QString& initialPath,
        const QStringList& allowedExtensions,
        bool canChooseFiles,
        bool canChooseDirectories,
        bool allowsMultipleSelection)
    {
        @autoreleasepool
        {
            NSOpenPanel* panel = [NSOpenPanel openPanel];
            [panel setCanChooseFiles:canChooseFiles ? YES : NO];
            [panel setCanChooseDirectories:canChooseDirectories ? YES : NO];
            [panel setAllowsMultipleSelection:allowsMultipleSelection ? YES : NO];
            [panel setResolvesAliases:YES];

            if (!caption.isEmpty())
            {
                [panel setMessage:caption.toNSString()];
            }

            if (!initialPath.isEmpty())
            {
                NSString* pathNs = initialPath.toNSString();
                BOOL isDir = NO;
                if ([[NSFileManager defaultManager] fileExistsAtPath:pathNs isDirectory:&isDir])
                {
                    NSURL* dirUrl = isDir ? [NSURL fileURLWithPath:pathNs]
                                          : [NSURL fileURLWithPath:[pathNs stringByDeletingLastPathComponent]];
                    [panel setDirectoryURL:dirUrl];
                }
            }

            if (!allowedExtensions.isEmpty())
            {
                NSMutableArray* types = [NSMutableArray array];
                for (const QString& ext : allowedExtensions)
                {
                    if (ext != "*" && ext != "&" && !ext.isEmpty())
                    {
                        [types addObject:ext.toNSString()];
                    }
                }
                if ([types count] > 0)
                {
                    [panel setAllowedFileTypes:types];
                    [panel setAllowsOtherFileTypes:YES];
                }
            }

            NSModalResponse response = [panel runModal];
            QStringList result;
            if (response == NSModalResponseOK)
            {
                for (NSURL* url in [panel URLs])
                {
                    if ([url isFileURL])
                    {
                        result.append(QString::fromNSString([url path]));
                    }
                }
            }
            return result;
        }
    }

} // namespace Rv

#endif // PLATFORM_DARWIN
