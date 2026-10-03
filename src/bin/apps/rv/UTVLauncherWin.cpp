//
// Copyright (C) 2026 Makai Systems and OpenUTV Contributors.
//
// SPDX-License-Identifier: Apache-2.0
//

//
//  Windows launcher. The same source builds two executables:
//
//    utv.exe               GUI subsystem. Starts the viewer (utv-bin.exe). rv.exe is a copy.
//    utv-cli-launcher.exe  Console subsystem (UTV_CONSOLE_LAUNCHER). The install step copies it over
//                          every command line tool, e.g. utvio.exe -> utvio-bin.exe, and adds the
//                          legacy rv* names (rvio.exe, rvpkg.exe, ...).
//
//  The install step also puts a copy of every launcher in <install>\cmd, the only directory the
//  installer adds to PATH; those run the programs in ..\bin.
//
//  Command line tools must be console programs: a shell then waits for them, gets their output and
//  exit code, and a caller that starts them with CREATE_NO_WINDOW gets no console window, neither
//  for the launcher nor for the tool it starts.
//
//  Either launcher:
//    1. finds the OpenUTVDeps runtime this build was made against (UTV_DEPS_VERSION),
//    2. sets PATH, PYTHONHOME and the Qt variables for its own process only, so the tool and anything
//       the tool starts inherit them, without touching the user or system environment,
//    3. for programs that render with OpenGL, decides between the GPU driver and Mesa (software) and
//       tells the opengl32.dll forwarder next to the executables through UTV_OPENGL,
//    4. starts <name>-bin.exe with the same arguments and returns its exit code.
//
//  The launcher never writes to the installation directory.
//

#if defined(_WIN32)

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif

#ifndef NOMINMAX
#define NOMINMAX
#endif

#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0A00
#endif

#include <windows.h>
#include <commctrl.h>
#include <shellapi.h>

#include <algorithm>
#include <cstdio>
#include <cstring>
#include <cwctype>
#include <iterator>
#include <string>
#include <vector>

#include "UTVLauncherConfig.h"

#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "advapi32.lib")
#pragma comment(lib, "user32.lib")
#pragma comment(lib, "kernel32.lib")
#pragma comment(lib, "gdi32.lib")

#pragma comment( \
    linker,      \
    "\"/manifestdependency:type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'\"")

#ifndef UTV_CONSOLE_LAUNCHER
#define UTV_CONSOLE_LAUNCHER 0
#endif

namespace
{

    const wchar_t kDepsReleasesUrl[] = L"https://github.com/OpenUTV/utv-dependencies/releases/tag/v" UTV_DEPS_VERSION;

    //
    //  Launcher name -> real executable. Every other name runs <name>-bin.exe. The rv* names are kept
    //  for scripts written for OpenRV. Keep the alias names in sync with cmake/install/post_install_windows.cmake.
    //
    struct Tool
    {
        const wchar_t* name;
        const wchar_t* binary;
        bool usesOpenGL;
    };

    const Tool kTools[] = {
        {L"utv", L"utv-bin", true},
        {L"rv", L"utv-bin", true},
        {L"utvio", L"utvio-bin", true},
        {L"rvio", L"utvio-bin", true},
        {L"utvprof", L"utvprof-bin", true},
        {L"rvprof", L"utvprof-bin", true},
        {L"utvls", L"utvls-bin", false},
        {L"rvls", L"utvls-bin", false},
        {L"utvpkg", L"utvpkg-bin", false},
        {L"rvpkg", L"utvpkg-bin", false},
        {L"utvpush", L"utvpush-bin", false},
        {L"rvpush", L"utvpush-bin", false},
        {L"utvshell", L"utvshell-bin", false},
        {L"rvshell", L"utvshell-bin", false},
    };

    // NTSTATUS exit codes of a process the loader could not start.
    const DWORD kLoaderFailures[] = {
        0xC0000135, // STATUS_DLL_NOT_FOUND
        0xC0000139, // STATUS_ENTRYPOINT_NOT_FOUND
        0xC0000138, // STATUS_ORDINAL_NOT_FOUND
        0xC000007B, // STATUS_INVALID_IMAGE_FORMAT
        0xC0000142, // STATUS_DLL_INIT_FAILED
    };

    // ---------------------------------------------------------------------------------------------
    //  Small helpers
    // ---------------------------------------------------------------------------------------------

    bool FileExists(const std::wstring& path)
    {
        DWORD attr = GetFileAttributesW(path.c_str());
        return attr != INVALID_FILE_ATTRIBUTES && !(attr & FILE_ATTRIBUTE_DIRECTORY);
    }

    bool DirExists(const std::wstring& path)
    {
        DWORD attr = GetFileAttributesW(path.c_str());
        return attr != INVALID_FILE_ATTRIBUTES && (attr & FILE_ATTRIBUTE_DIRECTORY);
    }

    std::wstring GetEnv(const wchar_t* name)
    {
        DWORD len = GetEnvironmentVariableW(name, NULL, 0);
        if (len == 0)
            return L"";
        std::vector<wchar_t> buf(len);
        DWORD got = GetEnvironmentVariableW(name, buf.data(), len);
        return got > 0 && got < len ? std::wstring(buf.data(), got) : L"";
    }

    void SetEnv(const wchar_t* name, const std::wstring& value) { SetEnvironmentVariableW(name, value.c_str()); }

    // Set and not "0": UTV_SOFTWARE_GL=1 means force software on every platform.
    bool EnvFlag(const wchar_t* name)
    {
        std::wstring v = GetEnv(name);
        return !v.empty() && v != L"0";
    }

    bool EqualsNoCase(const std::wstring& a, const wchar_t* b) { return _wcsicmp(a.c_str(), b) == 0; }

    std::wstring TrimTrailingSlashes(std::wstring path)
    {
        while (!path.empty() && (path.back() == L'\\' || path.back() == L'/'))
            path.pop_back();
        return path;
    }

    // The launcher's own path with symbolic links resolved (winget's portable command aliases are links).
    std::wstring ModulePath()
    {
        std::vector<wchar_t> buf(MAX_PATH);
        std::wstring path;
        for (;;)
        {
            DWORD len = GetModuleFileNameW(NULL, buf.data(), static_cast<DWORD>(buf.size()));
            if (len == 0)
                return L"";
            if (len < buf.size())
            {
                path.assign(buf.data(), len);
                break;
            }
            buf.resize(buf.size() * 2);
        }

        HANDLE file = CreateFileW(path.c_str(), 0, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL, OPEN_EXISTING, 0, NULL);
        if (file == INVALID_HANDLE_VALUE)
            return path;
        std::vector<wchar_t> finalPath(path.size() + MAX_PATH);
        DWORD len = GetFinalPathNameByHandleW(file, finalPath.data(), static_cast<DWORD>(finalPath.size()), FILE_NAME_NORMALIZED);
        CloseHandle(file);
        if (len == 0 || len >= finalPath.size())
            return path;
        std::wstring resolved(finalPath.data(), len);
        if (resolved.compare(0, 8, L"\\\\?\\UNC\\") == 0)
            return L"\\\\" + resolved.substr(8);
        if (resolved.compare(0, 4, L"\\\\?\\") == 0)
            return resolved.substr(4);
        return resolved;
    }

    std::wstring DirName(const std::wstring& path)
    {
        size_t slash = path.find_last_of(L"\\/");
        return slash == std::wstring::npos ? L"." : path.substr(0, slash);
    }

    std::wstring FullPath(const std::wstring& path)
    {
        wchar_t buf[MAX_PATH * 4];
        DWORD len = GetFullPathNameW(path.c_str(), MAX_PATH * 4, buf, NULL);
        return len > 0 && len < MAX_PATH * 4 ? std::wstring(buf, len) : path;
    }

    //
    //  The directory with the programs: the launcher's own, or ..\bin for the launchers in <install>\cmd.
    //  Only cmd goes on PATH (like Git for Windows), so the DLLs in bin never end up in other
    //  programs' DLL search.
    //
    std::wstring AppDirectory(const std::wstring& launcherDir)
    {
        if (FileExists(launcherDir + L"\\utv-bin.exe"))
            return launcherDir;
        std::wstring bin = FullPath(launcherDir + L"\\..\\bin");
        return FileExists(bin + L"\\utv-bin.exe") ? bin : launcherDir;
    }

    std::wstring BaseNameNoExe(const std::wstring& path)
    {
        size_t slash = path.find_last_of(L"\\/");
        std::wstring name = slash == std::wstring::npos ? path : path.substr(slash + 1);
        if (name.size() > 4 && _wcsicmp(name.c_str() + name.size() - 4, L".exe") == 0)
            name.resize(name.size() - 4);
        return name;
    }

    // "26.5", "26.5.0" and "v26.5" compare equal.
    std::vector<int> ParseVersion(const std::wstring& text)
    {
        std::vector<int> parts;
        size_t i = 0;
        while (i < text.size() && !iswdigit(text[i]))
            ++i;
        while (i < text.size() && iswdigit(text[i]))
        {
            int value = 0;
            while (i < text.size() && iswdigit(text[i]))
                value = value * 10 + (text[i++] - L'0');
            parts.push_back(value);
            if (i < text.size() && text[i] == L'.')
                ++i;
            else
                break;
        }
        while (!parts.empty() && parts.back() == 0)
            parts.pop_back();
        return parts;
    }

    bool SameVersion(const std::wstring& a, const std::wstring& b)
    {
        std::vector<int> pa = ParseVersion(a);
        return !pa.empty() && pa == ParseVersion(b);
    }

    // Version from a directory named like "OpenUTVDeps 26.5"; empty for any other name.
    std::wstring VersionFromDirName(const std::wstring& root)
    {
        std::wstring name = TrimTrailingSlashes(root);
        size_t slash = name.find_last_of(L"\\/");
        if (slash != std::wstring::npos)
            name = name.substr(slash + 1);
        if (_wcsnicmp(name.c_str(), L"OpenUTVDeps", 11) != 0)
            return L"";
        std::wstring version = name.substr(11);
        version.erase(0, version.find_first_not_of(L" -_v"));
        return ParseVersion(version).empty() ? L"" : version;
    }

    // Quote one argument so CommandLineToArgvW and the MSVC runtime read it back unchanged.
    void AppendQuotedArg(std::wstring& cmd, const std::wstring& arg)
    {
        if (!arg.empty() && arg.find_first_of(L" \t\n\v\"") == std::wstring::npos)
        {
            cmd += arg;
            return;
        }
        cmd += L'"';
        for (size_t i = 0;; ++i)
        {
            size_t backslashes = 0;
            while (i < arg.size() && arg[i] == L'\\')
            {
                ++i;
                ++backslashes;
            }
            if (i == arg.size())
            {
                cmd.append(backslashes * 2, L'\\');
                break;
            }
            if (arg[i] == L'"')
            {
                cmd.append(backslashes * 2 + 1, L'\\');
            }
            else
            {
                cmd.append(backslashes, L'\\');
            }
            cmd += arg[i];
        }
        cmd += L'"';
    }

    // The caller's arguments exactly as typed: the command line after the program name.
    std::wstring RawArguments()
    {
        const wchar_t* p = GetCommandLineW();
        if (!p)
            return L"";
        if (*p == L'"')
        {
            ++p;
            while (*p && *p != L'"')
                ++p;
            if (*p == L'"')
                ++p;
        }
        else
        {
            while (*p && *p != L' ' && *p != L'\t')
                ++p;
        }
        while (*p == L' ' || *p == L'\t')
            ++p;
        return p;
    }

    // ---------------------------------------------------------------------------------------------
    //  Reporting
    // ---------------------------------------------------------------------------------------------

    void ReportError(const std::wstring& heading, const std::wstring& details, const wchar_t* url)
    {
        fwprintf(stderr, L"OpenUTV: %ls\n%ls\n", heading.c_str(), details.c_str());
        if (url)
            fwprintf(stderr, L"%ls\n", url);
        fflush(stderr);

#if !UTV_CONSOLE_LAUNCHER
        // Looked up at run time: TaskDialogIndirect only exists in Common Controls 6.
        typedef HRESULT(WINAPI * TaskDialogIndirectFn)(const TASKDIALOGCONFIG*, int*, int*, BOOL*);
        HMODULE comctl = LoadLibraryW(L"comctl32.dll"); // version 6 through the manifest
        auto taskDialog = comctl ? reinterpret_cast<TaskDialogIndirectFn>(GetProcAddress(comctl, "TaskDialogIndirect")) : nullptr;

        TASKDIALOG_BUTTON buttons[] = {{1001, L"Open the download page"}, {IDCANCEL, L"Close"}};

        TASKDIALOGCONFIG tc;
        ZeroMemory(&tc, sizeof(tc));
        tc.cbSize = sizeof(tc);
        tc.dwFlags = TDF_ALLOW_DIALOG_CANCELLATION | (url ? TDF_USE_COMMAND_LINKS : 0);
        tc.dwCommonButtons = url ? 0 : TDCBF_CLOSE_BUTTON;
        tc.pszWindowTitle = L"OpenUTV";
        tc.pszMainIcon = TD_ERROR_ICON;
        tc.pszMainInstruction = heading.c_str();
        tc.pszContent = details.c_str();
        if (url)
        {
            tc.cButtons = 2;
            tc.pButtons = buttons;
            tc.nDefaultButton = 1001;
        }

        int pressed = 0;
        if (taskDialog && SUCCEEDED(taskDialog(&tc, &pressed, NULL, NULL)))
        {
            if (url && pressed == 1001)
                ShellExecuteW(NULL, L"open", url, NULL, NULL, SW_SHOWNORMAL);
        }
        else
        {
            std::wstring text = details + (url ? L"\n\nOpen the download page now?\n" + std::wstring(url) : L"");
            int choice = MessageBoxW(NULL, text.c_str(), heading.c_str(), MB_ICONERROR | (url ? MB_YESNO : MB_OK));
            if (url && choice == IDYES)
                ShellExecuteW(NULL, L"open", url, NULL, NULL, SW_SHOWNORMAL);
        }
        if (comctl)
            FreeLibrary(comctl);
#endif
    }

    // ---------------------------------------------------------------------------------------------
    //  OpenUTVDeps discovery
    // ---------------------------------------------------------------------------------------------

    struct Deps
    {
        std::wstring root;
        std::wstring bin;
        std::wstring python;
        std::wstring pyside;
        std::wstring version; // empty when unknown
        std::wstring source;  // where the candidate came from, for messages
    };

    // A complete OpenUTVDeps tree: the libraries, Python and the PySide6 Qt.
    bool ResolveDeps(const std::wstring& candidateRoot, Deps& deps)
    {
        std::wstring root = TrimTrailingSlashes(candidateRoot);
        if (root.empty())
            return false;

        // Installed MSI layout first, then a vcpkg tree in a development checkout.
        const std::wstring bases[] = {root, root + L"\\installed\\x64-windows"};
        for (const std::wstring& base : bases)
        {
            std::wstring python = base + L"\\tools\\python3";
            std::wstring pyside = python + L"\\Lib\\site-packages\\PySide6";
            if (FileExists(base + L"\\bin\\OpenImageIO.dll") && FileExists(python + L"\\python.exe")
                && FileExists(pyside + L"\\Qt6Core.dll"))
            {
                deps.root = root;
                deps.bin = base + L"\\bin";
                deps.python = python;
                deps.pyside = pyside;
                return true;
            }
        }
        return false;
    }

    std::wstring RegString(HKEY key, const wchar_t* value)
    {
        DWORD type = 0;
        DWORD size = 0;
        if (RegQueryValueExW(key, value, NULL, &type, NULL, &size) != ERROR_SUCCESS || (type != REG_SZ && type != REG_EXPAND_SZ))
            return L"";
        std::vector<wchar_t> buf(size / sizeof(wchar_t) + 1, L'\0');
        if (RegQueryValueExW(key, value, NULL, NULL, reinterpret_cast<LPBYTE>(buf.data()), &size) != ERROR_SUCCESS)
            return L"";
        return buf.data();
    }

    // OpenUTVDeps MSI installs, from the Installed Apps (Uninstall) registry.
    void AddInstalledDeps(std::vector<Deps>& candidates)
    {
        const HKEY hives[] = {HKEY_LOCAL_MACHINE, HKEY_CURRENT_USER};
        const wchar_t* paths[] = {L"SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall",
                                  L"SOFTWARE\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall"};
        for (HKEY hive : hives)
        {
            for (const wchar_t* path : paths)
            {
                HKEY uninstall = NULL;
                if (RegOpenKeyExW(hive, path, 0, KEY_READ, &uninstall) != ERROR_SUCCESS)
                    continue;
                wchar_t subkey[256];
                for (DWORD i = 0;; ++i)
                {
                    DWORD len = 256;
                    if (RegEnumKeyExW(uninstall, i, subkey, &len, NULL, NULL, NULL, NULL) != ERROR_SUCCESS)
                        break;
                    HKEY app = NULL;
                    if (RegOpenKeyExW(uninstall, subkey, 0, KEY_READ, &app) != ERROR_SUCCESS)
                        continue;
                    std::wstring name = RegString(app, L"DisplayName");
                    if (_wcsnicmp(name.c_str(), L"OpenUTVDeps", 11) == 0 || _wcsnicmp(name.c_str(), L"OpenUTV Dependencies", 20) == 0)
                    {
                        Deps d;
                        d.root = TrimTrailingSlashes(RegString(app, L"InstallLocation"));
                        d.version = RegString(app, L"DisplayVersion");
                        d.source = L"installed apps";
                        if (!d.root.empty())
                            candidates.push_back(d);
                    }
                    RegCloseKey(app);
                }
                RegCloseKey(uninstall);
            }
        }
    }

    void AddDirectoryMatches(std::vector<Deps>& candidates, const std::wstring& parent)
    {
        if (parent.empty())
            return;
        WIN32_FIND_DATAW fd;
        HANDLE find = FindFirstFileW((parent + L"\\OpenUTVDeps*").c_str(), &fd);
        if (find == INVALID_HANDLE_VALUE)
            return;
        do
        {
            if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)
            {
                Deps d;
                d.root = parent + L"\\" + fd.cFileName;
                d.version = VersionFromDirName(d.root);
                d.source = parent;
                candidates.push_back(d);
            }
        } while (FindNextFileW(find, &fd));
        FindClose(find);
    }

    enum class DepsResult
    {
        Found,
        Missing,
        WrongVersion
    };

    //
    //  UTV_DEPS_ROOT comes first (a development tree, or a location an earlier installer stored). Then
    //  the first complete install of exactly UTV_DEPS_VERSION wins, then a complete tree whose version
    //  is unknown (a development checkout). A tree of a known, different version is never used, not
    //  even from UTV_DEPS_ROOT: its libraries have other names or another ABI, and the user gets a
    //  message naming the version to install instead of a crash.
    //
    DepsResult FindDeps(const std::wstring& appDir, Deps& selected, std::vector<Deps>& wrongVersion)
    {
        std::wstring overrideRoot = GetEnv(L"UTV_DEPS_ROOT");
        if (!overrideRoot.empty())
        {
            Deps d;
            if (ResolveDeps(overrideRoot, d))
            {
                d.version = VersionFromDirName(d.root);
                d.source = L"UTV_DEPS_ROOT";
                if (d.version.empty() || SameVersion(d.version, UTV_DEPS_VERSION))
                {
                    selected = d;
                    return DepsResult::Found;
                }
                wrongVersion.push_back(d);
            }
            fwprintf(stderr, L"OpenUTV: ignoring UTV_DEPS_ROOT=%ls, which is not a complete OpenUTVDeps " UTV_DEPS_VERSION L" install\n",
                     overrideRoot.c_str());
        }

        std::vector<Deps> candidates;
        AddInstalledDeps(candidates);

        std::wstring msiRoot = GetEnv(L"OPENUTV_DEPS_ROOT");
        if (!msiRoot.empty())
        {
            Deps d;
            d.root = TrimTrailingSlashes(msiRoot);
            d.version = VersionFromDirName(d.root);
            d.source = L"OPENUTV_DEPS_ROOT";
            candidates.push_back(d);
        }

        AddDirectoryMatches(candidates, GetEnv(L"ProgramFiles"));
        std::wstring localAppData = GetEnv(L"LOCALAPPDATA");
        if (!localAppData.empty())
        {
            AddDirectoryMatches(candidates, localAppData + L"\\Programs");
            AddDirectoryMatches(candidates, localAppData);
        }

        // Development layouts next to a build tree.
        const wchar_t* relative[] = {L"\\deps", L"\\..\\deps", L"\\..\\..\\deps",
                                     L"\\..\\..\\utv-dependencies\\exported_deps\\utv-deps-windows-x64", L"\\..\\..\\utv-dependencies"};
        for (const wchar_t* rel : relative)
        {
            Deps d;
            d.root = appDir + rel;
            d.source = L"development tree";
            candidates.push_back(d);
        }

        const Deps* unknownVersion = nullptr;
        std::vector<Deps> complete;
        for (Deps& c : candidates)
        {
            Deps resolved;
            if (!ResolveDeps(c.root, resolved))
                continue;
            resolved.version = c.version;
            resolved.source = c.source;
            complete.push_back(resolved);
        }

        for (const Deps& c : complete)
        {
            if (SameVersion(c.version, UTV_DEPS_VERSION))
            {
                selected = c;
                return DepsResult::Found;
            }
        }
        for (const Deps& c : complete)
        {
            if (c.version.empty())
            {
                unknownVersion = &c;
                break;
            }
        }
        if (unknownVersion)
        {
            selected = *unknownVersion;
            return DepsResult::Found;
        }

        for (const Deps& c : complete)
        {
            bool seen = false;
            for (const Deps& w : wrongVersion)
                seen = seen || _wcsicmp(w.root.c_str(), c.root.c_str()) == 0;
            if (!seen)
                wrongVersion.push_back(c);
        }
        return wrongVersion.empty() ? DepsResult::Missing : DepsResult::WrongVersion;
    }

    // ---------------------------------------------------------------------------------------------
    //  Environment
    // ---------------------------------------------------------------------------------------------

    void ConfigureEnvironment(const std::wstring& appDir, const Deps& deps)
    {
        SetEnv(L"UTV_DEPS_ROOT", deps.root);
        SetEnv(L"OPENUTV_DEPS_ROOT", deps.root);
        std::wstring rootSlash = deps.root;
        std::replace(rootSlash.begin(), rootSlash.end(), L'\\', L'/');
        SetEnv(L"UTV_DEPS_ROOT_SLASH", rootSlash);
        SetEnv(L"OPENUTV_DEPS_ROOT_SLASH", rootSlash);
        SetEnv(L"UTV_HOME", appDir);
        SetEnv(L"OPENUTV_HOME", appDir);

        std::wstring path = appDir + L";" + deps.bin + L";" + deps.pyside;
        std::wstring shiboken = deps.python + L"\\Lib\\site-packages\\shiboken6";
        if (DirExists(shiboken))
            path += L";" + shiboken;
        path += L";" + deps.python + L";" + deps.python + L"\\Scripts";
        std::wstring inherited = GetEnv(L"PATH");
        if (!inherited.empty())
            path += L";" + inherited;
        SetEnv(L"PATH", path);

        //
        //  Always ours, even when the user's environment has these for another Python or Qt: the
        //  embedded Python and Qt cannot load another installation's standard library or plugins.
        //  PYTHONPATH is left alone, pipelines add their own modules through it.
        //
        SetEnv(L"PYTHONHOME", deps.python);
        SetEnv(L"QT_PLUGIN_PATH", deps.pyside + L"\\plugins");
        SetEnv(L"QT_QPA_PLATFORM_PLUGIN_PATH", deps.pyside + L"\\plugins\\platforms");
        SetEnv(L"QTWEBENGINEPROCESS_PATH", deps.pyside + L"\\QtWebEngineProcess.exe");
        SetEnv(L"QTWEBENGINE_RESOURCES_PATH", deps.pyside + L"\\resources");
        SetEnv(L"QTWEBENGINE_LOCALES_PATH", deps.pyside + L"\\translations\\qtwebengine_locales");
        SetEnv(L"QML2_IMPORT_PATH", deps.pyside + L"\\qml");
        SetEnv(L"QML_IMPORT_PATH", deps.pyside + L"\\qml");

        // Qt and UTV must resolve OpenGL from the same opengl32.dll, the forwarder next to the executables.
        SetEnv(L"QT_OPENGL", L"desktop");
        SetEnvironmentVariableW(L"QT_OPENGL_DLL", NULL);
    }

    // ---------------------------------------------------------------------------------------------
    //  OpenGL: GPU driver or Mesa
    // ---------------------------------------------------------------------------------------------

    //
    //  Creates a context through the system opengl32.dll on the display adapter. "GDI Generic" is the
    //  OpenGL 1.1 renderer Windows falls back to without a GPU driver (Hyper-V, VirtualBox without 3D,
    //  Microsoft Basic Display Adapter, some RDP sessions); it cannot run UTV's shaders.
    //
    bool HardwareOpenGLAvailable()
    {
        // Explicitly the system DLL: the application directory has the forwarding opengl32.dll.
        HMODULE gl = LoadLibraryExW(L"opengl32.dll", NULL, LOAD_LIBRARY_SEARCH_SYSTEM32);
        if (!gl)
            return false;

        typedef HGLRC(WINAPI * CreateContextFn)(HDC);
        typedef BOOL(WINAPI * MakeCurrentFn)(HDC, HGLRC);
        typedef BOOL(WINAPI * DeleteContextFn)(HGLRC);
        typedef const unsigned char*(WINAPI * GetStringFn)(unsigned int);

        auto createContext = reinterpret_cast<CreateContextFn>(GetProcAddress(gl, "wglCreateContext"));
        auto makeCurrent = reinterpret_cast<MakeCurrentFn>(GetProcAddress(gl, "wglMakeCurrent"));
        auto deleteContext = reinterpret_cast<DeleteContextFn>(GetProcAddress(gl, "wglDeleteContext"));
        auto getString = reinterpret_cast<GetStringFn>(GetProcAddress(gl, "glGetString"));

        bool hardware = false;
        HWND window = createContext && makeCurrent && deleteContext && getString
                          ? CreateWindowW(L"STATIC", L"OpenUTV GL probe", WS_POPUP, 0, 0, 1, 1, NULL, NULL, NULL, NULL)
                          : NULL;
        if (window)
        {
            HDC dc = GetDC(window);
            PIXELFORMATDESCRIPTOR pfd;
            ZeroMemory(&pfd, sizeof(pfd));
            pfd.nSize = sizeof(pfd);
            pfd.nVersion = 1;
            pfd.dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER;
            pfd.iPixelType = PFD_TYPE_RGBA;
            pfd.cColorBits = 32;
            int format = ChoosePixelFormat(dc, &pfd);
            if (format && SetPixelFormat(dc, format, &pfd))
            {
                HGLRC context = createContext(dc);
                if (context)
                {
                    if (makeCurrent(dc, context))
                    {
                        const char* name = reinterpret_cast<const char*>(getString(0x1F01));    // GL_RENDERER
                        const char* version = reinterpret_cast<const char*>(getString(0x1F02)); // GL_VERSION
                        std::vector<int> v;
                        if (version)
                        {
                            std::wstring wversion;
                            for (const char* c = version; *c; ++c)
                                wversion += static_cast<wchar_t>(static_cast<unsigned char>(*c));
                            v = ParseVersion(wversion);
                        }
                        v.resize(2, 0);
                        bool modernEnough = v[0] > 2 || (v[0] == 2 && v[1] >= 1);
                        hardware = name && !strstr(name, "GDI Generic") && modernEnough;
                        makeCurrent(NULL, NULL);
                    }
                    deleteContext(context);
                }
            }
            ReleaseDC(window, dc);
            DestroyWindow(window);
        }
        FreeLibrary(gl);
        return hardware;
    }

    bool IsSoftwareGLFlag(const wchar_t* arg) { return _wcsicmp(arg, L"--software-gl") == 0 || _wcsicmp(arg, L"-software-gl") == 0; }

    //
    //  Exports UTV_OPENGL=hardware|software (and UTV_OPENGL_SOFTWARE_DLL) for the opengl32.dll forwarder.
    //  A decision inherited from a parent process (the viewer starting utvio, a test) is kept.
    //
    void ConfigureOpenGL(const std::wstring& appDir, const Deps& deps, bool softwareFlag)
    {
        std::wstring mode = GetEnv(L"UTV_OPENGL");
        if (!EqualsNoCase(mode, L"software") && !EqualsNoCase(mode, L"hardware"))
        {
            // Quiet: render nodes without a GPU are normal, and scripts parse the tools' output.
            bool forced = softwareFlag || EnvFlag(L"UTV_SOFTWARE_GL") || EnvFlag(L"OPENUTV_SOFTWARE_GL")
                          || EqualsNoCase(GetEnv(L"QT_OPENGL"), L"software");
            mode = forced || !HardwareOpenGLAvailable() ? L"software" : L"hardware";
        }

        if (EqualsNoCase(mode, L"software") && !FileExists(GetEnv(L"UTV_OPENGL_SOFTWARE_DLL")))
        {
            const std::wstring mesa[] = {deps.pyside + L"\\opengl32sw.dll", appDir + L"\\opengl32sw.dll"};
            std::wstring found;
            for (const std::wstring& m : mesa)
            {
                if (found.empty() && FileExists(m))
                    found = m;
            }
            if (found.empty())
            {
                fwprintf(stderr, L"OpenUTV: software rendering requested but opengl32sw.dll (Mesa) was not found\n");
                mode = L"hardware";
            }
            else
            {
                SetEnv(L"UTV_OPENGL_SOFTWARE_DLL", found);
            }
        }
        SetEnv(L"UTV_OPENGL", mode);
    }

    // ---------------------------------------------------------------------------------------------
    //  Target
    // ---------------------------------------------------------------------------------------------

    struct Target
    {
        std::wstring path;
        bool usesOpenGL = false;
    };

    bool ResolveTarget(const std::wstring& appDir, const std::wstring& ownName, Target& target)
    {
        std::wstring binary = ownName + L"-bin";
        target.usesOpenGL = false;
        for (const Tool& t : kTools)
        {
            if (_wcsicmp(ownName.c_str(), t.name) == 0)
            {
                binary = t.binary;
                target.usesOpenGL = t.usesOpenGL;
                break;
            }
        }
        target.path = appDir + L"\\" + binary + L".exe";
        return FileExists(target.path);
    }

    // utv --run <command> [args...]: run any program with the OpenUTV environment.
    bool ResolveRunCommand(const std::wstring& appDir, const Deps& deps, const std::wstring& cmd, std::wstring& path)
    {
        const std::wstring candidates[] = {cmd,
                                           cmd + L".exe",
                                           appDir + L"\\" + cmd + L"-bin.exe",
                                           appDir + L"\\" + cmd + L".exe",
                                           appDir + L"\\" + cmd,
                                           deps.bin + L"\\" + cmd + L".exe",
                                           deps.python + L"\\" + cmd + L".exe",
                                           deps.python + L"\\Scripts\\" + cmd + L".exe"};
        for (const std::wstring& c : candidates)
        {
            if (FileExists(c))
            {
                path = c;
                return true;
            }
        }
        wchar_t found[MAX_PATH];
        if (SearchPathW(NULL, cmd.c_str(), L".exe", MAX_PATH, found, NULL) > 0)
        {
            path = found;
            return true;
        }
        return false;
    }

    // ---------------------------------------------------------------------------------------------
    //  Child process
    // ---------------------------------------------------------------------------------------------

#if UTV_CONSOLE_LAUNCHER
    // Ctrl+C goes to every process on the console. The tool handles it; the launcher waits for the tool
    // to exit and returns its exit code.
    BOOL WINAPI IgnoreInterrupt(DWORD type) { return type == CTRL_C_EVENT || type == CTRL_BREAK_EVENT; }
#endif

    //
    //  The child runs in a job that is closed with the launcher, so killing the launcher (a script's
    //  timeout, Task Manager) also ends the program it started. Processes the child starts break away
    //  silently: a browser or editor the viewer opens keeps running after the viewer exits.
    //
    HANDLE CreateKillOnCloseJob()
    {
        HANDLE job = CreateJobObjectW(NULL, NULL);
        if (!job)
            return NULL;
        JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits;
        ZeroMemory(&limits, sizeof(limits));
        limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE | JOB_OBJECT_LIMIT_SILENT_BREAKAWAY_OK;
        if (!SetInformationJobObject(job, JobObjectExtendedLimitInformation, &limits, sizeof(limits)))
        {
            CloseHandle(job);
            return NULL;
        }
        return job;
    }

    bool RunChild(const std::wstring& exe, const std::wstring& args, DWORD& exitCode, DWORD& error)
    {
        std::wstring cmdLine;
        AppendQuotedArg(cmdLine, exe);
        if (!args.empty())
            cmdLine += L" " + args;
        std::vector<wchar_t> cmdBuf(cmdLine.begin(), cmdLine.end());
        cmdBuf.push_back(L'\0');

        STARTUPINFOW si;
        ZeroMemory(&si, sizeof(si));
        si.cb = sizeof(si);
        si.dwFlags = STARTF_USESTDHANDLES;
        si.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
        si.hStdOutput = GetStdHandle(STD_OUTPUT_HANDLE);
        si.hStdError = GetStdHandle(STD_ERROR_HANDLE);

        // A missing or mismatched DLL fails the child with an exit code we can explain, instead of one
        // system dialog per missing library. The child inherits the error mode.
        SetErrorMode(GetErrorMode() | SEM_FAILCRITICALERRORS | SEM_NOOPENFILEERRORBOX);

        HANDLE job = CreateKillOnCloseJob();
        PROCESS_INFORMATION pi;
        ZeroMemory(&pi, sizeof(pi));
        if (!CreateProcessW(exe.c_str(), cmdBuf.data(), NULL, NULL, TRUE, CREATE_SUSPENDED, NULL, NULL, &si, &pi))
        {
            error = GetLastError();
            if (job)
                CloseHandle(job);
            return false;
        }
        if (job)
            AssignProcessToJobObject(job, pi.hProcess);
        ResumeThread(pi.hThread);
        CloseHandle(pi.hThread);

        WaitForSingleObject(pi.hProcess, INFINITE);
        exitCode = 0;
        GetExitCodeProcess(pi.hProcess, &exitCode);
        CloseHandle(pi.hProcess);
        if (job)
            CloseHandle(job);
        return true;
    }

    std::wstring DescribeDeps(const Deps& deps)
    {
        return L"OpenUTVDeps " + (deps.version.empty() ? std::wstring(L"(unknown version)") : deps.version) + L" at " + deps.root;
    }

} // namespace

int RunLauncher()
{
#if UTV_CONSOLE_LAUNCHER
    SetConsoleCtrlHandler(IgnoreInterrupt, TRUE);
#else
    // Started from cmd or PowerShell: print messages there, and let the viewer inherit the console
    // handles so "utv -help" works.
    HANDLE stdOut = GetStdHandle(STD_OUTPUT_HANDLE);
    if ((stdOut == NULL || stdOut == INVALID_HANDLE_VALUE) && AttachConsole(ATTACH_PARENT_PROCESS))
    {
        FILE* fp = nullptr;
        freopen_s(&fp, "CONOUT$", "w", stdout);
        freopen_s(&fp, "CONOUT$", "w", stderr);
        freopen_s(&fp, "CONIN$", "r", stdin);
    }
#endif

    const std::wstring exePath = ModulePath();
    const std::wstring appDir = AppDirectory(DirName(exePath));
    const std::wstring ownName = BaseNameNoExe(exePath);

    int argc = 0;
    LPWSTR* argv = CommandLineToArgvW(GetCommandLineW(), &argc);
    std::vector<std::wstring> args;
    for (int i = 1; argv && i < argc; ++i)
        args.push_back(argv[i]);
    if (argv)
        LocalFree(argv);

    Deps deps;
    std::vector<Deps> wrongVersion;
    switch (FindDeps(appDir, deps, wrongVersion))
    {
    case DepsResult::Found:
        break;
    case DepsResult::Missing:
        ReportError(
            L"OpenUTV needs OpenUTVDeps " UTV_DEPS_VERSION,
            L"The OpenUTVDeps " UTV_DEPS_VERSION L" runtime package (Qt, Python, FFmpeg, OpenColorIO, OpenEXR) was not found on this "
            L"computer. Install it from the download page, then start OpenUTV again.",
            kDepsReleasesUrl);
        return 1;
    case DepsResult::WrongVersion:
    {
        std::wstring found;
        for (const Deps& d : wrongVersion)
            found += L"\n  " + DescribeDeps(d);
        ReportError(L"OpenUTV needs OpenUTVDeps " UTV_DEPS_VERSION,
                    L"This OpenUTV build needs OpenUTVDeps " UTV_DEPS_VERSION L", but only other versions were found:" + found
                        + L"\n\nInstall OpenUTVDeps " UTV_DEPS_VERSION L" from the download page, then start OpenUTV again.",
                    kDepsReleasesUrl);
        return 1;
    }
    }

    ConfigureEnvironment(appDir, deps);

    Target target;
    std::wstring childArgs;
    bool softwareFlag = false;
    if (!args.empty() && args[0] == L"--run")
    {
        if (args.size() < 2 || !ResolveRunCommand(appDir, deps, args[1], target.path))
        {
            ReportError(L"Cannot run the command",
                        L"Usage: " + ownName + L" --run <command> [arguments...]\nCommand not found: "
                            + (args.size() < 2 ? std::wstring() : args[1]),
                        NULL);
            return 1;
        }
        for (size_t i = 2; i < args.size(); ++i)
        {
            if (!childArgs.empty())
                childArgs += L" ";
            AppendQuotedArg(childArgs, args[i]);
        }
    }
    else
    {
        if (!ResolveTarget(appDir, ownName, target))
        {
            // Never fall back to the viewer from a tool: a script running a tool would open viewers (#73).
            ReportError(L"OpenUTV installation is incomplete",
                        L"'" + ownName + L"' could not be started because " + target.path + L" is missing. Reinstall OpenUTV.", NULL);
            return 1;
        }

        // --software-gl is the launcher's option: forward everything else exactly as typed.
        softwareFlag = std::any_of(args.begin(), args.end(), [](const std::wstring& a) { return IsSoftwareGLFlag(a.c_str()); });
        if (softwareFlag)
        {
            for (const std::wstring& a : args)
            {
                if (IsSoftwareGLFlag(a.c_str()))
                    continue;
                if (!childArgs.empty())
                    childArgs += L" ";
                AppendQuotedArg(childArgs, a);
            }
        }
        else
        {
            childArgs = RawArguments();
        }
    }

    if (target.usesOpenGL)
        ConfigureOpenGL(appDir, deps, softwareFlag);

    DWORD exitCode = 0;
    DWORD error = 0;
    if (!RunChild(target.path, childArgs, exitCode, error))
    {
        wchar_t details[64];
        swprintf_s(details, L" (Windows error %lu)", error);
        ReportError(L"OpenUTV could not start a program", L"Failed to start " + target.path + details, NULL);
        return 1;
    }

    if (std::find(std::begin(kLoaderFailures), std::end(kLoaderFailures), exitCode) != std::end(kLoaderFailures))
    {
        wchar_t status[32];
        swprintf_s(status, L"0x%08lX", exitCode);
        std::wstring cause = SameVersion(deps.version, UTV_DEPS_VERSION)
                                 ? std::wstring(L"That installation looks incomplete or damaged.")
                                 : std::wstring(L"This build needs OpenUTVDeps " UTV_DEPS_VERSION L".");
        ReportError(L"OpenUTV could not start",
                    BaseNameNoExe(target.path) + L" failed to load a library it needs (" + status + L"). It was started with "
                        + DescribeDeps(deps) + L" (found through " + deps.source + L"). " + cause
                        + L"\n\nInstall OpenUTVDeps " UTV_DEPS_VERSION L" again from the download page.",
                    kDepsReleasesUrl);
    }

    return static_cast<int>(exitCode);
}

#if UTV_CONSOLE_LAUNCHER
int wmain() { return RunLauncher(); }
#else
int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) { return RunLauncher(); }
#endif

#endif
