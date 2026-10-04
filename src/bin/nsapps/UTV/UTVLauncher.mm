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
#import <spawn.h>
#import <vector>
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
    const char *customDeps = getenv("UTV_DEPS_ROOT");
    if (!customDeps) customDeps = getenv("OPENUTV_DEPS_ROOT");
    if (!customDeps) customDeps = getenv("HOMEBREW_PREFIX");
    if (customDeps && strlen(customDeps) > 0) {
        NSString *prefix = [NSString stringWithUTF8String:customDeps];
        if ([[NSFileManager defaultManager] fileExistsAtPath:prefix]) {
            return prefix;
        }
    }

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

//
// Homebrew upgrades its libraries independently of UTV. When one changes incompatibly
// (e.g. OpenColorIO 2.5 -> 2.6 renames every symbol), dyld aborts UTV-bin before any of
// its code runs: no window, no log, no dialog. Start UTV-bin once with -version, which
// loads and binds every library and exits in under 0.1s, and report a load failure.
//
// Returns nil if UTV-bin loads, or if the check itself could not run or failed for some
// other reason (never block a launch on the check). Otherwise returns dyld's message.
//
static NSString *libraryLoadFailure(NSString *realBin) {
    // stderr goes to a file rather than a pipe, so the child can never block on a full pipe.
    NSString *errPath = [NSTemporaryDirectory()
        stringByAppendingPathComponent:[NSString stringWithFormat:@"openutv_library_check_%d.txt", getpid()]];
    [[NSFileManager defaultManager] createFileAtPath:errPath contents:nil attributes:nil];
    NSFileHandle *errFile = [NSFileHandle fileHandleForWritingAtPath:errPath];
    if (!errFile) {
        return nil;
    }

    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:realBin];
    task.arguments = @[@"-version"];
    task.standardError = errFile;
    task.standardOutput = [NSFileHandle fileHandleWithNullDevice];
    task.standardInput = [NSFileHandle fileHandleWithNullDevice];

    NSString *output = nil;
    if ([task launchAndReturnError:nil]) {
        // Give up after 20 seconds and let the normal launch proceed.
        for (int i = 0; i < 2000 && [task isRunning]; i++) {
            usleep(10000);
        }

        if ([task isRunning]) {
            [task terminate];
        } else if ([task terminationReason] == NSTaskTerminationReasonUncaughtSignal) {
            output = [NSString stringWithContentsOfFile:errPath encoding:NSUTF8StringEncoding error:nil];
        }
    }

    [errFile closeFile];
    [[NSFileManager defaultManager] removeItemAtPath:errPath error:nil];

    if (!output) {
        return nil;
    }

    NSRange dyld = [output rangeOfString:@"dyld["];
    if (dyld.location == NSNotFound) {
        return nil;
    }

    NSString *message = [[output substringFromIndex:dyld.location]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return [message length] > 1200 ? [message substringToIndex:1200] : message;
}

// The Homebrew formula named in a dyld message, e.g. ".../Cellar/opencolorio/2.6.0/lib/..." -> "opencolorio 2.6.0".
static NSString *formulaInLoadFailure(NSString *message) {
    NSRange all = NSMakeRange(0, [message length]);

    NSRegularExpression *cellar = [NSRegularExpression regularExpressionWithPattern:@"/Cellar/([^/\\s]+)/([^/\\s]+)/" options:0 error:nil];
    NSTextCheckingResult *m = [[cellar matchesInString:message options:0 range:all] lastObject];
    if (m) {
        return [NSString stringWithFormat:@"%@ %@", [message substringWithRange:[m rangeAtIndex:1]],
                                          [message substringWithRange:[m rangeAtIndex:2]]];
    }

    // "Library not loaded" names the path UTV was linked to: <prefix>/opt/<formula>/lib/...
    NSRegularExpression *opt = [NSRegularExpression regularExpressionWithPattern:@"/opt/([^/\\s]+)/lib/" options:0 error:nil];
    m = [[opt matchesInString:message options:0 range:all] firstObject];
    return m ? [message substringWithRange:[m rangeAtIndex:1]] : nil;
}

static NSString *const kLibraryFixCommand = @"brew update && brew upgrade && brew upgrade --cask utv";

static void launchTerminalLibraryUpdate(void) {
    NSString *appBundlePath = [[NSBundle mainBundle] bundlePath];

    NSMutableString *script = [NSMutableString string];
    [script appendString:@"#!/bin/bash\n"];
    [script appendString:@"# OpenUTV Library Update Script\n\n"];
    [script appendString:@"if [ -f \"/opt/homebrew/bin/brew\" ]; then\n"];
    [script appendString:@"    eval \"$(/opt/homebrew/bin/brew shellenv)\"\n"];
    [script appendString:@"elif [ -f \"/usr/local/bin/brew\" ]; then\n"];
    [script appendString:@"    eval \"$(/usr/local/bin/brew shellenv)\"\n"];
    [script appendString:@"fi\n\n"];
    [script appendString:@"echo '--> Updating Homebrew libraries and OpenUTV so they match'\n"];
    [script appendFormat:@"echo '    %@'\n", kLibraryFixCommand];
    [script appendString:@"brew update && brew upgrade\n"];
    [script appendString:@"brew upgrade --cask utv 2>/dev/null || true\n"];
    [script appendString:@"echo ''\n"];

    if (appBundlePath && [appBundlePath hasSuffix:@".app"]) {
        [script appendString:@"read -r -p 'Press [Enter] to launch OpenUTV now, or close this window... '\n"];
        [script appendFormat:@"open -a \"%@\" 2>/dev/null || true\n", appBundlePath];
        [script appendString:@"exit 0\n"];
    } else {
        [script appendString:@"read -n 1 -s -r -p 'Press any key to close...' && exit 0\n"];
    }

    NSString *scriptPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"openutv_update_libraries.command"];
    NSError *writeErr = nil;
    [script writeToFile:scriptPath atomically:YES encoding:NSUTF8StringEncoding error:&writeErr];
    if (writeErr) {
        NSLog(@"UTVLauncher: Failed to write command script: %@", writeErr);
        return;
    }
    chmod([scriptPath UTF8String], 0755);
    [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:scriptPath]];
}

static void reportLibraryLoadFailure(NSString *failure, BOOL isFinder) {
    NSString *formula = formulaInLoadFailure(failure);

    if (!isFinder) {
        fprintf(stderr, "\n");
        fprintf(stderr, "================================================================================\n");
        fprintf(stderr, "  UTV: Homebrew libraries do not match this version of UTV\n");
        fprintf(stderr, "================================================================================\n\n");
        fprintf(stderr, "UTV could not load%s%s. Homebrew has upgraded a library since this version of UTV\n",
                formula ? " " : " a required library", formula ? [formula UTF8String] : "");
        fprintf(stderr, "was built, or the library is older than this version of UTV needs.\n\n");
        fprintf(stderr, "To update the libraries and UTV so they match, run:\n");
        fprintf(stderr, "  %s\n\n", [kLibraryFixCommand UTF8String]);
        fprintf(stderr, "Details:\n%s\n\n", [failure UTF8String]);
        fprintf(stderr, "If this does not help, report it at https://github.com/OpenUTV/utv/issues\n");
        fprintf(stderr, "================================================================================\n\n");
        return;
    }

    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [NSApp activateIgnoringOtherApps:YES];

    NSAlert *alert = [[NSAlert alloc] init];
    [alert setAlertStyle:NSAlertStyleCritical];
    [alert setMessageText:@"UTV and its Homebrew libraries don't match"];
    [alert setInformativeText:[NSString stringWithFormat:
        @"UTV could not load %@.\n\n"
        @"Homebrew has upgraded a library since this version of UTV was built, or the library is older than this "
        @"version of UTV needs. Updating both fixes it:\n\n%@\n\nDetails:\n%@",
        formula ?: @"a required library", kLibraryFixCommand,
        [failure length] > 400 ? [[failure substringToIndex:400] stringByAppendingString:@"…"] : failure]];
    [alert addButtonWithTitle:@"Update with Homebrew"];
    [alert addButtonWithTitle:@"Copy Command"];
    [alert addButtonWithTitle:@"Quit"];

    NSModalResponse response = [alert runModal];
    if (response == NSAlertFirstButtonReturn) {
        launchTerminalLibraryUpdate();
    } else if (response == NSAlertSecondButtonReturn) {
        NSPasteboard *pb = [NSPasteboard generalPasteboard];
        [pb clearContents];
        [pb setString:kLibraryFixCommand forType:NSPasteboardTypeString];
    }
}

static BOOL isLaunchedFromFinder(int argc, char *argv[]) {
    if (isatty(STDIN_FILENO) || isatty(STDOUT_FILENO) || isatty(STDERR_FILENO)) {
        return NO;
    }
    // Started through LaunchServices (Finder, Dock, Spotlight, or `open` from a shell): stderr is
    // /dev/null, so a message printed there is never seen. `open` passes the shell's TERM along,
    // so TERM alone does not tell the two apart.
    struct stat errStat;
    if (fstat(STDERR_FILENO, &errStat) == 0 && S_ISCHR(errStat.st_mode)) {
        return YES;
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

@interface UTVLaunchEventCollector : NSObject <NSApplicationDelegate>
@property(nonatomic, strong) NSMutableArray<NSString *> *requests;
@end

@implementation UTVLaunchEventCollector
- (instancetype)init {
    if ((self = [super init])) {
        _requests = [NSMutableArray array];
    }
    return self;
}

- (void)application:(NSApplication *)application openURLs:(NSArray<NSURL *> *)urls {
    for (NSURL *url in urls) {
        [self.requests addObject:[url isFileURL] ? [url path] : [url absoluteString]];
    }
}
@end

static NSArray<NSString *> *collectLaunchOpenRequests(void) {
    UTVLaunchEventCollector *collector = [[UTVLaunchEventCollector alloc] init];
    [NSApplication sharedApplication];
    [NSApp setDelegate:collector];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    [NSApp finishLaunching];

    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:0.4];
    while ([deadline timeIntervalSinceNow] > 0) {
        NSEvent *event = [NSApp nextEventMatchingMask:NSEventMaskAny
                                            untilDate:deadline
                                               inMode:NSDefaultRunLoopMode
                                              dequeue:YES];
        if (event) [NSApp sendEvent:event];
    }
    return collector.requests;
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSString *brewPrefix = detectBrewPrefix();
        NSDictionary *manifest = fetchRemoteManifest();
        NSArray<NSString *> *missing = findMissingDependencies(brewPrefix, manifest);
        NSArray<NSString *> *postInstallCmds = manifest[@"post_install_commands"];

        // All dependencies satisfied -> launch real binary immediately
        if ([missing count] == 0) {
            // Set UTV environment variables for runtime child processes
            if (getenv("UTV_DEPS_ROOT") == NULL) {
                setenv("UTV_DEPS_ROOT", [brewPrefix UTF8String], 1);
            }
            if (getenv("OPENUTV_DEPS_ROOT") == NULL) {
                setenv("OPENUTV_DEPS_ROOT", [brewPrefix UTF8String], 1);
            }
            if (getenv("UTV_HOME") == NULL) {
                NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
                if (bundlePath) {
                    setenv("UTV_HOME", [bundlePath UTF8String], 1);
                    setenv("OPENUTV_HOME", [bundlePath UTF8String], 1);
                }
            }

            // Check if --run <cmd> [args...] mode was requested
            if (argc >= 3 && strcmp(argv[1], "--run") == 0) {
                NSString *targetCmd = [NSString stringWithUTF8String:argv[2]];
                NSString *binDir = [[[NSBundle mainBundle] executablePath] stringByDeletingLastPathComponent];
                NSString *targetPath = [binDir stringByAppendingPathComponent:targetCmd];
                if (![[NSFileManager defaultManager] fileExistsAtPath:targetPath]) {
                    targetPath = [[brewPrefix stringByAppendingPathComponent:@"bin"] stringByAppendingPathComponent:targetCmd];
                }
                if ([[NSFileManager defaultManager] fileExistsAtPath:targetPath]) {
                    execv([targetPath UTF8String], &argv[2]);
                    perror("UTVLauncher: execv --run failed");
                    return 1;
                } else {
                    fprintf(stderr, "UTVLauncher: Command '%s' not found.\n", argv[2]);
                    return 1;
                }
            }

            NSString *realBin = findRealBinary();
            if (realBin) {
                if (getenv("UTV_SKIP_LIBRARY_CHECK") == NULL) {
                    NSString *failure = libraryLoadFailure(realBin);
                    if (failure) {
                        reportLibraryLoadFailure(failure, isLaunchedFromFinder(argc, argv));
                        return 1;
                    }
                }
                if (isLaunchedFromFinder(argc, argv)) {
                    NSArray<NSString *> *opened = collectLaunchOpenRequests();
                    NSMutableArray<NSString *> *args = [NSMutableArray array];
                    for (int i = 0; i < argc; ++i) {
                        if (i > 0 && strncmp(argv[i], "-psn_", 5) == 0) continue;
                        [args addObject:[NSString stringWithUTF8String:argv[i]]];
                    }
                    [args addObjectsFromArray:opened];
                    std::vector<char *> childArgv;
                    for (NSString *a in args) childArgv.push_back(const_cast<char *>([a UTF8String]));
                    childArgv.push_back(NULL);

                    extern char **environ;
                    pid_t child;
                    if (posix_spawn(&child, [realBin UTF8String], NULL, NULL, childArgv.data(), environ) == 0) {
                        return 0;
                    }
                    perror("UTVLauncher: posix_spawn failed");
                    return 1;
                }
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
            fprintf(stderr, "  brew tap OpenUTV/utv\n");
            fprintf(stderr, "  brew trust OpenUTV/utv\n");
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
