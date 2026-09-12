//
// Copyright (C) 2026 Makai Systems. All Rights Reserved.
//
// Native Objective-C Trampoline Launcher for UTV
// Verifies required Homebrew dependencies before dyld execution.
//

#import <Cocoa/Cocoa.h>
#import <mach-o/dyld.h>
#import <sys/stat.h>
#import <unistd.h>
#import <stdlib.h>
#import <stdio.h>

struct DepCheck {
    const char *formula;
    const char *paths[3]; // NULL terminated relative paths under brew prefix
};

static const struct DepCheck kRequiredDependencies[] = {
    {"qt", {"opt/qt", "opt/qtbase", NULL}},
    {"boost", {"opt/boost", NULL}},
    {"ffmpeg-full", {"opt/ffmpeg-full", "opt/ffmpeg", NULL}},
    {"opencolorio", {"opt/opencolorio", NULL}},
    {"openimageio", {"opt/openimageio", NULL}},
    {"openexr", {"opt/openexr", NULL}},
    {"imath", {"opt/imath", NULL}},
    {"libpng", {"opt/libpng", NULL}},
    {"libtiff", {"opt/libtiff", NULL}},
    {"jpeg-turbo", {"opt/jpeg-turbo", NULL}},
    {"libraw", {"opt/libraw", NULL}},
    {"openjpeg", {"opt/openjpeg", NULL}},
    {"openjph", {"opt/openjph", NULL}},
    {"webp", {"opt/webp", NULL}},
    {"yaml-cpp", {"opt/yaml-cpp", NULL}},
    {"spdlog", {"opt/spdlog", NULL}},
    {"icu4c", {"opt/icu4c", NULL}},
    {NULL, {NULL}}
};

static NSString *detectBrewPrefix(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:@"/opt/homebrew/bin/brew"]) {
        return @"/opt/homebrew";
    }
    if ([fm fileExistsAtPath:@"/usr/local/bin/brew"]) {
        return @"/usr/local";
    }
    const char *pathEnv = getenv("PATH");
    if (pathEnv) {
        NSArray *dirs = [[NSString stringWithUTF8String:pathEnv] componentsSeparatedByString:@":"];
        for (NSString *d in dirs) {
            NSString *brewBin = [d stringByAppendingPathComponent:@"brew"];
            if ([fm fileExistsAtPath:brewBin]) {
                return [d stringByDeletingLastPathComponent];
            }
        }
    }
#if defined(__arm64__) || defined(__aarch64__)
    return @"/opt/homebrew";
#else
    return @"/usr/local";
#endif
}

static BOOL isBrewInstalled(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:@"/opt/homebrew/bin/brew"] ||
        [fm fileExistsAtPath:@"/usr/local/bin/brew"]) {
        return YES;
    }
    const char *pathEnv = getenv("PATH");
    if (pathEnv) {
        NSArray *dirs = [[NSString stringWithUTF8String:pathEnv] componentsSeparatedByString:@":"];
        for (NSString *d in dirs) {
            NSString *brewBin = [d stringByAppendingPathComponent:@"brew"];
            if ([fm fileExistsAtPath:brewBin]) {
                return YES;
            }
        }
    }
    return NO;
}

static NSArray<NSString *> *findMissingDependencies(NSString *brewPrefix) {
    if (getenv("UTV_SKIP_DEP_CHECK") != NULL) {
        return @[];
    }

    NSMutableArray<NSString *> *missing = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];

    for (int i = 0; kRequiredDependencies[i].formula != NULL; ++i) {
        BOOL found = NO;
        for (int j = 0; kRequiredDependencies[i].paths[j] != NULL; ++j) {
            NSString *relPath = [NSString stringWithUTF8String:kRequiredDependencies[i].paths[j]];
            NSString *fullPath = [brewPrefix stringByAppendingPathComponent:relPath];
            if ([fm fileExistsAtPath:fullPath]) {
                found = YES;
                break;
            }
        }
        if (!found) {
            [missing addObject:[NSString stringWithUTF8String:kRequiredDependencies[i].formula]];
        }
    }

    const char *testMissing = getenv("UTV_TEST_MISSING_DEPS");
    if (testMissing) {
        NSArray *items = [[NSString stringWithUTF8String:testMissing] componentsSeparatedByString:@" "];
        [missing addObjectsFromArray:items];
    }

    return missing;
}

static NSString *findRealBinary(void) {
    char path[PATH_MAX];
    uint32_t size = sizeof(path);
    if (_NSGetExecutablePath(path, &size) == 0) {
        char resolved[PATH_MAX];
        if (realpath(path, resolved) != NULL) {
            NSString *execPath = [NSString stringWithUTF8String:resolved];
            NSString *dir = [execPath stringByDeletingLastPathComponent];
            NSString *bin = [dir stringByAppendingPathComponent:@"UTV-bin"];
            if ([[NSFileManager defaultManager] fileExistsAtPath:bin]) {
                return bin;
            }
        }
    }
    NSString *bundleExec = [[NSBundle mainBundle] executablePath];
    if (bundleExec) {
        NSString *dir = [bundleExec stringByDeletingLastPathComponent];
        NSString *bin = [dir stringByAppendingPathComponent:@"UTV-bin"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:bin]) {
            return bin;
        }
    }
    return nil;
}

static void runTerminalCommand(NSString *command) {
    NSString *escaped = [command stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];

    NSString *appleScriptSource = [NSString stringWithFormat:
        @"tell application \"Terminal\"\n"
        @"    activate\n"
        @"    do script \"%@\"\n"
        @"end tell", escaped];

    NSAppleScript *script = [[NSAppleScript alloc] initWithSource:appleScriptSource];
    NSDictionary *err = nil;
    [script executeAndReturnError:&err];
    if (err) {
        NSLog(@"UTVLauncher: Failed to launch Terminal via AppleScript: %@", err);
    }
}

static BOOL isLaunchedFromFinder(int argc, char *argv[]) {
    if (isatty(STDIN_FILENO) || isatty(STDOUT_FILENO) || isatty(STDERR_FILENO)) {
        return NO;
    }
    if (getenv("TERM") != NULL) {
        return NO;
    }
    if (argc > 1) {
        if (strncmp(argv[1], "-psn_", 5) != 0) {
            return NO;
        }
    }
    return YES;
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSString *brewPrefix = detectBrewPrefix();
        NSArray<NSString *> *missing = findMissingDependencies(brewPrefix);

        // All dependencies satisfied -> launch real binary immediately
        if ([missing count] == 0) {
            NSString *realBin = findRealBinary();
            if (realBin) {
                execv([realBin UTF8String], argv);
                perror("UTVLauncher: execv failed");
                return 1;
            } else {
                fprintf(stderr, "UTVLauncher: Real binary UTV-bin not found.\n");
                return 1;
            }
        }

        // Dependencies missing!
        BOOL isFinder = isLaunchedFromFinder(argc, argv);
        NSString *missingList = [missing componentsJoinedByString:@" "];

        if (!isFinder) {
            fprintf(stderr, "\n");
            fprintf(stderr, "================================================================================\n");
            fprintf(stderr, "  UTV: Missing Dependencies\n");
            fprintf(stderr, "================================================================================\n");
            fprintf(stderr, "UTV requires the following Homebrew libraries that are not currently installed:\n");
            for (NSString *formula in missing) {
                fprintf(stderr, "  • %s\n", [formula UTF8String]);
            }
            fprintf(stderr, "\nTo install the missing dependencies with Homebrew, run:\n");
            fprintf(stderr, "  brew install %s\n\n", [missingList UTF8String]);
            fprintf(stderr, "Or install UTV using Homebrew Cask (installs all dependencies automatically):\n");
            fprintf(stderr, "  brew install --cask utv\n\n");
            fprintf(stderr, "For more information, visit: https://github.com/OpenUTV/utv\n");
            fprintf(stderr, "================================================================================\n\n");
            return 1;
        }

        // GUI Mode: show native macOS alert dialog
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        [NSApp activateIgnoringOtherApps:YES];

        BOOL hasBrew = isBrewInstalled();

        if (hasBrew) {
            NSAlert *alert = [[NSAlert alloc] init];
            [alert setAlertStyle:NSAlertStyleCritical];
            [alert setMessageText:@"UTV Dependencies Required"];

            NSImage *appIcon = [NSApp applicationIconImage];
            if (!appIcon) {
                appIcon = [[NSBundle mainBundle] imageForResource:@"UTV.icns"];
            }
            if (appIcon) {
                [alert setIcon:appIcon];
            }

            NSString *depList = [missing componentsJoinedByString:@"\n• "];
            NSString *info = [NSString stringWithFormat:
                @"UTV requires multimedia libraries from Homebrew that are not currently installed:\n\n• %@\n\n"
                @"Would you like to install them now?", depList];
            [alert setInformativeText:info];

            [alert addButtonWithTitle:@"Install with Homebrew"];
            [alert addButtonWithTitle:@"Copy Command"];
            [alert addButtonWithTitle:@"Quit"];

            NSModalResponse response = [alert runModal];
            if (response == NSAlertFirstButtonReturn) {
                NSString *installCmd = [NSString stringWithFormat:
                    @"echo 'Installing UTV dependencies via Homebrew...'; "
                    @"brew install %@; "
                    @"echo ''; "
                    @"echo '================================================================='; "
                    @"echo '  Dependencies installed! You can now launch UTV.'; "
                    @"echo '================================================================='; "
                    @"read -n 1 -s -r -p 'Press any key to close...' && exit", missingList];
                runTerminalCommand(installCmd);
            } else if (response == NSAlertSecondButtonReturn) {
                NSString *cmd = [NSString stringWithFormat:@"brew install %@", missingList];
                NSPasteboard *pb = [NSPasteboard generalPasteboard];
                [pb clearContents];
                [pb setString:cmd forType:NSPasteboardTypeString];

                NSAlert *copiedAlert = [[NSAlert alloc] init];
                [copiedAlert setAlertStyle:NSAlertStyleInformational];
                [copiedAlert setMessageText:@"Command Copied to Clipboard"];
                [copiedAlert setInformativeText:[NSString stringWithFormat:@"The following command has been copied to your clipboard:\n\n%@", cmd]];
                [copiedAlert addButtonWithTitle:@"OK"];
                [copiedAlert runModal];
            }
        } else {
            // Homebrew not installed at all
            NSAlert *alert = [[NSAlert alloc] init];
            [alert setAlertStyle:NSAlertStyleCritical];
            [alert setMessageText:@"Homebrew Required"];

            NSImage *appIcon = [NSApp applicationIconImage];
            if (!appIcon) {
                appIcon = [[NSBundle mainBundle] imageForResource:@"UTV.icns"];
            }
            if (appIcon) {
                [alert setIcon:appIcon];
            }

            [alert setInformativeText:
                @"UTV requires multimedia dependencies managed via Homebrew (Qt 6, FFmpeg, OpenColorIO, OpenEXR, etc.), but Homebrew was not found on your Mac.\n\n"
                @"Would you like to install Homebrew and UTV dependencies now?"];

            [alert addButtonWithTitle:@"Install Homebrew"];
            [alert addButtonWithTitle:@"Visit brew.sh"];
            [alert addButtonWithTitle:@"Quit"];

            NSModalResponse response = [alert runModal];
            if (response == NSAlertFirstButtonReturn) {
                NSString *installCmd = [NSString stringWithFormat:
                    @"/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\" && "
                    @"brew install %@ && "
                    @"echo '' && "
                    @"echo '=================================================================' && "
                    @"echo '  Homebrew and dependencies installed! You can now launch UTV.' && "
                    @"echo '=================================================================' && "
                    @"read -n 1 -s -r -p 'Press any key to close...' && exit", missingList];
                runTerminalCommand(installCmd);
            } else if (response == NSAlertSecondButtonReturn) {
                [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://brew.sh"]];
            }
        }

        return 0;
    }
}
