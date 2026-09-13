//
// Copyright (C) 2026 Makai Systems. All Rights Reserved.
//
// Native Objective-C Trampoline Launcher for UTV
// Verifies required Homebrew dependencies before dyld execution.
// Supports dynamic remote manifests, native Terminal execution, and diagnostics packaging.
//

#import <Cocoa/Cocoa.h>
#import <mach-o/dyld.h>
#import <sys/stat.h>
#import <unistd.h>
#import <stdlib.h>
#import <stdio.h>

struct DepCheck {
    const char *formula;
    const char *paths[4]; // NULL terminated relative paths under brew prefix
};

static const struct DepCheck kRequiredDependencies[] = {
    {"qt", {"opt/qt", "opt/qtbase", NULL}},
    {"boost", {"opt/boost", NULL}},
    {"ffmpeg-full", {"opt/ffmpeg-full", "opt/ffmpeg", NULL}},
    {"python@3.14", {"opt/python@3.14", "opt/python3", "opt/python", NULL}},
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
    {"pyside", {"opt/pyside", "opt/pyside@6", NULL}},
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

static NSDictionary *fetchRemoteManifest(void) {
    if (getenv("UTV_SKIP_REMOTE_MANIFEST") != NULL) {
        return nil;
    }
    NSURL *url = [NSURL URLWithString:@"https://raw.githubusercontent.com/OpenUTV/utv/main/deploy/dependencies.json"];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url
                                                       cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                   timeoutInterval:1.5];
    [req setValue:@"OpenUTV-Launcher" forHTTPHeaderField:@"User-Agent"];

    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    __block NSData *resultData = nil;

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    config.timeoutIntervalForRequest = 1.5;
    config.timeoutIntervalForResource = 1.5;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];

    [[session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!error && [(NSHTTPURLResponse *)response statusCode] == 200) {
            resultData = data;
        }
        dispatch_semaphore_signal(sema);
    }] resume];

    dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)));
    [session finishTasksAndInvalidate];

    if (resultData) {
        NSError *jsonErr = nil;
        id json = [NSJSONSerialization JSONObjectWithData:resultData options:0 error:&jsonErr];
        if ([json isKindOfClass:[NSDictionary class]]) {
            return (NSDictionary *)json;
        }
    }
    return nil;
}

static NSArray<NSString *> *findMissingDependencies(NSString *brewPrefix, NSDictionary *manifest) {
    if (getenv("UTV_SKIP_DEP_CHECK") != NULL) {
        return @[];
    }

    NSMutableArray<NSString *> *missing = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];

    NSArray *remoteFormulae = manifest[@"formulae"];
    if ([remoteFormulae isKindOfClass:[NSArray class]] && [remoteFormulae count] > 0) {
        for (NSDictionary *entry in remoteFormulae) {
            if (![entry isKindOfClass:[NSDictionary class]]) continue;
            NSString *formulaName = entry[@"name"];
            NSArray *paths = entry[@"paths"];
            if (!formulaName || ![paths isKindOfClass:[NSArray class]]) continue;

            BOOL found = NO;
            for (NSString *relPath in paths) {
                NSString *fullPath = [brewPrefix stringByAppendingPathComponent:relPath];
                if ([fm fileExistsAtPath:fullPath]) {
                    found = YES;
                    break;
                }
            }
            if (!found) {
                [missing addObject:formulaName];
            }
        }
    } else {
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
    }

    const char *testMissing = getenv("UTV_TEST_MISSING_DEPS");
    if (testMissing) {
        NSArray *items = [[NSString stringWithUTF8String:testMissing] componentsSeparatedByString:@" "];
        [missing addObjectsFromArray:items];
    }

    // Deduplicate while preserving order
    return [[NSOrderedSet orderedSetWithArray:missing] array];
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

static void launchTerminalSetup(NSArray<NSString *> *missing, NSArray<NSString *> *postInstallCmds, BOOL needsBrew) {
    NSString *missingList = [missing componentsJoinedByString:@" "];
    NSString *appBundlePath = [[NSBundle mainBundle] bundlePath];

    // 1. Copy command to pasteboard for user convenience
    NSString *clipCmd = [NSString stringWithFormat:@"brew install %@ && brew link --overwrite ffmpeg-full", missingList];
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString:clipCmd forType:NSPasteboardTypeString];

    // 2. Generate standalone .command script
    NSMutableString *script = [NSMutableString string];
    [script appendString:@"#!/bin/bash\n"];
    [script appendString:@"# OpenUTV Dependency Setup Script\n\n"];
    [script appendString:@"clear 2>/dev/null || true\n"];
    [script appendString:@"echo '================================================================='\n"];
    [script appendString:@"echo '  OpenUTV: Setting Up Multimedia Dependencies'\n"];
    [script appendString:@"echo '================================================================='\n"];
    [script appendString:@"echo ''\n\n"];

    [script appendString:@"# Ensure Homebrew is on PATH\n"];
    [script appendString:@"if [ -f \"/opt/homebrew/bin/brew\" ]; then\n"];
    [script appendString:@"    eval \"$(/opt/homebrew/bin/brew shellenv)\"\n"];
    [script appendString:@"elif [ -f \"/usr/local/bin/brew\" ]; then\n"];
    [script appendString:@"    eval \"$(/usr/local/bin/brew shellenv)\"\n"];
    [script appendString:@"fi\n\n"];

    if (needsBrew) {
        [script appendString:@"if ! command -v brew &>/dev/null; then\n"];
        [script appendString:@"    echo 'Homebrew is not installed on your system.'\n"];
        [script appendString:@"    echo 'Installing Homebrew now (you may be prompted for your password)...'\n"];
        [script appendString:@"    echo ''\n"];
        [script appendString:@"    /bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"\n"];
        [script appendString:@"    if [ -f \"/opt/homebrew/bin/brew\" ]; then\n"];
        [script appendString:@"        eval \"$(/opt/homebrew/bin/brew shellenv)\"\n"];
        [script appendString:@"    elif [ -f \"/usr/local/bin/brew\" ]; then\n"];
        [script appendString:@"        eval \"$(/usr/local/bin/brew shellenv)\"\n"];
        [script appendString:@"    fi\n"];
        [script appendString:@"fi\n\n"];
    }

    if ([missing count] > 0) {
        [script appendString:[NSString stringWithFormat:@"echo '--> Installing packages: %@'\n", missingList]];
        [script appendString:[NSString stringWithFormat:@"brew install %@\n\n", missingList]];
    }

    [script appendString:@"echo '--> Linking packages and resolving conflicts...'\n"];
    if (postInstallCmds && [postInstallCmds count] > 0) {
        for (NSString *cmd in postInstallCmds) {
            [script appendFormat:@"%@\n", cmd];
        }
    } else {
        [script appendString:@"brew link --overwrite ffmpeg-full 2>/dev/null || true\n"];
    }

    [script appendString:@"\necho ''\n"];
    [script appendString:@"echo '================================================================='\n"];
    [script appendString:@"echo '  Setup completed! You can now run OpenUTV.'\n"];
    [script appendString:@"echo '================================================================='\n"];
    [script appendString:@"echo ''\n"];

    if (appBundlePath && [appBundlePath hasSuffix:@".app"]) {
        [script appendFormat:@"read -r -p 'Press [Enter] to launch OpenUTV now, or close this window... '\n"];
        [script appendFormat:@"open -a \"%@\" 2>/dev/null || true\n", appBundlePath];
        [script appendString:@"exit 0\n"];
    } else {
        [script appendString:@"read -n 1 -s -r -p 'Press any key to close...' && exit 0\n"];
    }

    NSString *tempDir = NSTemporaryDirectory();
    NSString *scriptPath = [tempDir stringByAppendingPathComponent:@"openutv_setup_dependencies.command"];
    NSError *writeErr = nil;
    [script writeToFile:scriptPath atomically:YES encoding:NSUTF8StringEncoding error:&writeErr];
    if (writeErr) {
        NSLog(@"UTVLauncher: Failed to write command script: %@", writeErr);
        return;
    }
    chmod([scriptPath UTF8String], 0755);

    // Launch via NSWorkspace. macOS opens Terminal.app and executes the script directly without TCC issues
    [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:scriptPath]];
}

static void runDiagnostics(void) {
    NSString *bundleRes = [[NSBundle mainBundle] resourcePath];
    NSString *scriptPath = [bundleRes stringByAppendingPathComponent:@"openutv-diagnostics.sh"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:scriptPath]) {
        NSString *binDir = [[[NSBundle mainBundle] executablePath] stringByDeletingLastPathComponent];
        scriptPath = [binDir stringByAppendingPathComponent:@"openutv-diagnostics"];
    }

    if ([[NSFileManager defaultManager] fileExistsAtPath:scriptPath]) {
        NSTask *task = [[NSTask alloc] init];
        task.launchPath = @"/bin/bash";
        task.arguments = @[scriptPath];
        [task launch];
    } else {
        [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://github.com/OpenUTV/utv/issues/new?template=bug.yml"]];
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
        NSDictionary *manifest = fetchRemoteManifest();
        NSArray<NSString *> *missing = findMissingDependencies(brewPrefix, manifest);
        NSArray<NSString *> *postInstallCmds = manifest[@"post_install_commands"];

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
            fprintf(stderr, "  brew install %s && brew link --overwrite ffmpeg-full\n\n", [missingList UTF8String]);
            fprintf(stderr, "Or install UTV using Homebrew Cask (installs all dependencies automatically):\n");
            fprintf(stderr, "  brew install --cask utv\n\n");
            fprintf(stderr, "For more information or to report issues, visit: https://github.com/OpenUTV/utv\n");
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
            [alert addButtonWithTitle:@"Report Issue / Diagnostics"];
            [alert addButtonWithTitle:@"Quit"];

            NSModalResponse response = [alert runModal];
            if (response == NSAlertFirstButtonReturn) {
                launchTerminalSetup(missing, postInstallCmds, NO);
            } else if (response == NSAlertSecondButtonReturn) {
                NSString *cmd = [NSString stringWithFormat:@"brew install %@ && brew link --overwrite ffmpeg-full", missingList];
                NSPasteboard *pb = [NSPasteboard generalPasteboard];
                [pb clearContents];
                [pb setString:cmd forType:NSPasteboardTypeString];

                NSAlert *copiedAlert = [[NSAlert alloc] init];
                [copiedAlert setAlertStyle:NSAlertStyleInformational];
                [copiedAlert setMessageText:@"Command Copied to Clipboard"];
                [copiedAlert setInformativeText:[NSString stringWithFormat:@"The following command has been copied to your clipboard:\n\n%@", cmd]];
                [copiedAlert addButtonWithTitle:@"OK"];
                [copiedAlert runModal];
            } else if (response == NSAlertThirdButtonReturn) {
                runDiagnostics();
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

            [alert addButtonWithTitle:@"Install Homebrew & Setup"];
            [alert addButtonWithTitle:@"Visit brew.sh"];
            [alert addButtonWithTitle:@"Report Issue / Diagnostics"];
            [alert addButtonWithTitle:@"Quit"];

            NSModalResponse response = [alert runModal];
            if (response == NSAlertFirstButtonReturn) {
                launchTerminalSetup(missing, postInstallCmds, YES);
            } else if (response == NSAlertSecondButtonReturn) {
                [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://brew.sh"]];
            } else if (response == NSAlertThirdButtonReturn) {
                runDiagnostics();
            }
        }

        return 0;
    }
}
