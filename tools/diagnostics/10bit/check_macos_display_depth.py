#!/usr/bin/env python3
# ******************************************************************************
# Copyright (c) 2026 OpenUTV / Makai Systems
# All rights reserved.
#
# SPDX-License-Identifier: Apache-2.0
# ******************************************************************************
"""
Query macOS screen color depth, bit-depth (NSBitsPerSample), and EDR capabilities.
"""

import subprocess
import sys


def main():
    objc_code = """
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <Foundation/Foundation.h>
#include <stdio.h>

int main() {
    @autoreleasepool {
        NSArray<NSScreen*>* screens = [NSScreen screens];
        printf("Detected %lu display(s):\\n\\n", (unsigned long)[screens count]);
        for (NSUInteger i = 0; i < [screens count]; ++i) {
            NSScreen* screen = screens[i];
            const NSInteger bps = NSBitsPerSampleFromDepth([screen depth]);
            printf("Display [%lu]: %s%s\\n",
                   (unsigned long)i,
                   [[screen localizedName] UTF8String],
                   (screen == [NSScreen mainScreen]) ? " (Main Display)" : "");
            printf("  NSBitsPerSample:  %ld %s\\n",
                   (long)bps,
                   (bps >= 10) ? "(True Deep Color / 10-bit Scanout)" : "(8-bit SDR / Dithered FRC Panel)");
            printf("  ColorSpace:       %s\\n", [[[screen colorSpace] localizedName] UTF8String]);
            printf("  Max Current EDR:  %.2f\\n", screen.maximumExtendedDynamicRangeColorComponentValue);
            printf("  Max Potential EDR:%.2f\\n", screen.maximumPotentialExtendedDynamicRangeColorComponentValue);
            printf("  Max Reference EDR:%.2f\\n\\n", screen.maximumReferenceExtendedDynamicRangeColorComponentValue);
        }
    }
    return 0;
}
"""
    try:
        subprocess.run(
            [
                "clang",
                "-x",
                "objective-c",
                "-framework",
                "AppKit",
                "-framework",
                "QuartzCore",
                "-o",
                "/tmp/check_screen_depth_runner",
                "-",
            ],
            input=objc_code.encode("utf-8"),
            capture_output=True,
            check=True,
        )
        subprocess.run(["/tmp/check_screen_depth_runner"], check=True)
    except subprocess.CalledProcessError as e:
        print(f"Error compiling/running display depth checker: {e}", file=sys.stderr)
        if e.stderr:
            print(e.stderr.decode("utf-8"), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
