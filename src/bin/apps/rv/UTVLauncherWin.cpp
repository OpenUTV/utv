//
// Copyright (C) 2026 Makai Systems and OpenUTV Contributors.
//
// SPDX-License-Identifier: Apache-2.0
//

#if defined(_WIN32)

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif

#ifndef NOMINMAX
#define NOMINMAX
#endif

#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0600
#endif

#include <windows.h>
#include <commctrl.h>
#include <shellapi.h>
#include <shlwapi.h>

#include <algorithm>
#include <cstdio>
#include <string>
#include <vector>

#pragma comment(lib, "comctl32.lib")
#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "shlwapi.lib")
#pragma comment(lib, "advapi32.lib")
#pragma comment(lib, "user32.lib")
#pragma comment(lib, "kernel32.lib")

#pragma comment( \
    linker,      \
    "\"/manifestdependency:type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'\"")

static const wchar_t DEPS_DOWNLOAD_URL[] = L"https://github.com/OpenUTV/utv-dependencies/releases/latest";

namespace
{

    bool FileExists(const std::wstring& path)
    {
        DWORD attr = GetFileAttributesW(path.c_str());
        return (attr != INVALID_FILE_ATTRIBUTES && !(attr & FILE_ATTRIBUTE_DIRECTORY));
    }

    bool DirExists(const std::wstring& path)
    {
        DWORD attr = GetFileAttributesW(path.c_str());
        return (attr != INVALID_FILE_ATTRIBUTES && (attr & FILE_ATTRIBUTE_DIRECTORY));
    }

    std::wstring GetAppDir()
    {
        std::vector<wchar_t> buffer(MAX_PATH);
        DWORD len = GetModuleFileNameW(NULL, buffer.data(), static_cast<DWORD>(buffer.size()));
        while (len >= buffer.size())
        {
            buffer.resize(buffer.size() * 2);
            len = GetModuleFileNameW(NULL, buffer.data(), static_cast<DWORD>(buffer.size()));
        }
        if (len == 0)
        {
            return L"";
        }
        PathRemoveFileSpecW(buffer.data());
        return std::wstring(buffer.data());
    }

    bool CheckDepsDir(const std::wstring& root, std::wstring& outBinDir, std::wstring& outPySideDir, std::wstring& outPythonDir)
    {
        if (root.empty())
        {
            return false;
        }

        // 1. Locate C++ binary directory
        std::wstring binCandidates[] = {root + L"\\bin", root + L"\\installed\\x64-windows\\bin", root};
        std::wstring foundBin;

        const std::wstring exactDlls[] = {L"\\OpenImageIO.dll", L"\\glew32.dll", L"\\OpenColorIO_2_5.dll", L"\\OpenEXR-3_4.dll",
                                          L"\\Imath-3_2.dll",   L"\\zlib1.dll",  L"\\Qt6Core.dll"};

        for (const auto& candBin : binCandidates)
        {
            for (const auto& dll : exactDlls)
            {
                if (FileExists(candBin + dll))
                {
                    foundBin = candBin;
                    break;
                }
            }
            if (!foundBin.empty())
            {
                break;
            }

            // Pattern fallback
            const wchar_t* patterns[] = {L"\\avcodec-*.dll", L"\\avutil-*.dll", L"\\OpenColorIO*.dll",
                                         L"\\OpenEXR*.dll",  L"\\Imath*.dll",   L"\\boost_*.dll"};
            for (const auto& pat : patterns)
            {
                WIN32_FIND_DATAW fd;
                HANDLE h = FindFirstFileW((candBin + pat).c_str(), &fd);
                if (h != INVALID_HANDLE_VALUE)
                {
                    foundBin = candBin;
                    FindClose(h);
                    break;
                }
            }
            if (!foundBin.empty())
            {
                break;
            }
        }

        if (foundBin.empty())
        {
            return false;
        }

        // 2. Locate Qt6 binaries (either in PySide6 or in bin or standard locations)
        std::wstring foundPySide;
        const std::wstring pySideCandidates[] = {root + L"\\tools\\python3\\Lib\\site-packages\\PySide6",
                                                 root + L"\\installed\\x64-windows\\tools\\python3\\Lib\\site-packages\\PySide6",
                                                 root + L"\\Lib\\site-packages\\PySide6"};
        for (const auto& cand : pySideCandidates)
        {
            if (FileExists(cand + L"\\Qt6Core.dll"))
            {
                foundPySide = cand;
                break;
            }
        }

        if (foundPySide.empty() && FileExists(foundBin + L"\\Qt6Core.dll"))
        {
            foundPySide = foundBin;
        }

        // Fallback: check QTDIR environment variable
        if (foundPySide.empty())
        {
            wchar_t qtDirEnv[MAX_PATH];
            if (GetEnvironmentVariableW(L"QTDIR", qtDirEnv, MAX_PATH) > 0)
            {
                std::wstring cand(qtDirEnv);
                if (FileExists(cand + L"\\bin\\Qt6Core.dll"))
                {
                    foundPySide = cand + L"\\bin";
                }
                else if (FileExists(cand + L"\\Qt6Core.dll"))
                {
                    foundPySide = cand;
                }
            }
        }

        // Fallback: search system PATH for Qt6Core.dll
        if (foundPySide.empty())
        {
            wchar_t foundQtPath[MAX_PATH];
            LPWSTR filePart = NULL;
            DWORD spRes = SearchPathW(NULL, L"Qt6Core.dll", NULL, MAX_PATH, foundQtPath, &filePart);
            if (spRes > 0 && spRes < MAX_PATH && filePart)
            {
                *filePart = L'\0';
                size_t pLen = wcslen(foundQtPath);
                if (pLen > 0 && foundQtPath[pLen - 1] == L'\\')
                {
                    foundQtPath[pLen - 1] = L'\0';
                }
                foundPySide = foundQtPath;
            }
        }

        // Fallback: check C:\Qt\6.*\msvc2022_64\bin
        if (foundPySide.empty())
        {
            WIN32_FIND_DATAW fd;
            HANDLE hFind = FindFirstFileW(L"C:\\Qt\\6.*", &fd);
            if (hFind != INVALID_HANDLE_VALUE)
            {
                do
                {
                    if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)
                    {
                        std::wstring cand = L"C:\\Qt\\" + std::wstring(fd.cFileName) + L"\\msvc2022_64\\bin";
                        if (FileExists(cand + L"\\Qt6Core.dll"))
                        {
                            foundPySide = cand;
                            break;
                        }
                    }
                } while (FindNextFileW(hFind, &fd));
                FindClose(hFind);
            }
        }

        if (foundPySide.empty())
        {
            return false;
        }

        // 3. Locate Python directory
        std::wstring foundPython;
        const std::wstring pythonCandidates[] = {root + L"\\tools\\python3", root + L"\\installed\\x64-windows\\tools\\python3",
                                                 root + L"\\python"};
        for (const auto& cand : pythonCandidates)
        {
            if (FileExists(cand + L"\\python.exe") || FileExists(cand + L"\\python314.dll") || DirExists(cand))
            {
                foundPython = cand;
                break;
            }
        }

        if (foundPython.empty() && (FileExists(foundBin + L"\\python.exe") || FileExists(foundBin + L"\\python314.dll")))
        {
            foundPython = foundBin;
        }

        if (foundPython.empty())
        {
            wchar_t pyHome[MAX_PATH];
            if (GetEnvironmentVariableW(L"PYTHONHOME", pyHome, MAX_PATH) > 0)
            {
                foundPython = pyHome;
            }
        }

        if (foundPython.empty())
        {
            wchar_t foundPyPath[MAX_PATH];
            LPWSTR filePart = NULL;
            DWORD spRes = SearchPathW(NULL, L"python.exe", NULL, MAX_PATH, foundPyPath, &filePart);
            if (spRes > 0 && spRes < MAX_PATH && filePart)
            {
                *filePart = L'\0';
                foundPython = foundPyPath;
            }
        }

        outBinDir = foundBin;
        outPySideDir = foundPySide;
        outPythonDir = foundPython;
        return true;
    }

    bool FindDependencies(const std::wstring& appDir, std::wstring& outRootDir, std::wstring& outBinDir, std::wstring& outPySideDir,
                          std::wstring& outPythonDir)
    {
        // 1. Environment variable OPENUTV_DEPS_ROOT
        DWORD len = GetEnvironmentVariableW(L"OPENUTV_DEPS_ROOT", NULL, 0);
        if (len > 0)
        {
            std::vector<wchar_t> buf(len);
            GetEnvironmentVariableW(L"OPENUTV_DEPS_ROOT", buf.data(), len);
            std::wstring envRoot(buf.data());
            if (CheckDepsDir(envRoot, outBinDir, outPySideDir, outPythonDir))
            {
                outRootDir = envRoot;
                return true;
            }
        }

        // 2. System Environment in registry (catches fresh MSI installations in existing shells)
        HKEY hKey = NULL;
        if (RegOpenKeyExW(HKEY_LOCAL_MACHINE, L"SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Environment", 0, KEY_READ, &hKey)
            == ERROR_SUCCESS)
        {
            wchar_t regVal[MAX_PATH];
            DWORD valSize = sizeof(regVal);
            DWORD valType = 0;
            if (RegQueryValueExW(hKey, L"OPENUTV_DEPS_ROOT", NULL, &valType, reinterpret_cast<LPBYTE>(regVal), &valSize) == ERROR_SUCCESS)
            {
                std::wstring regRoot(regVal);
                if (CheckDepsDir(regRoot, outBinDir, outPySideDir, outPythonDir))
                {
                    outRootDir = regRoot;
                    RegCloseKey(hKey);
                    return true;
                }
            }
            RegCloseKey(hKey);
        }

        // 3. User Environment in registry
        if (RegOpenKeyExW(HKEY_CURRENT_USER, L"Environment", 0, KEY_READ, &hKey) == ERROR_SUCCESS)
        {
            wchar_t regVal[MAX_PATH];
            DWORD valSize = sizeof(regVal);
            DWORD valType = 0;
            if (RegQueryValueExW(hKey, L"OPENUTV_DEPS_ROOT", NULL, &valType, reinterpret_cast<LPBYTE>(regVal), &valSize) == ERROR_SUCCESS)
            {
                std::wstring regRoot(regVal);
                if (CheckDepsDir(regRoot, outBinDir, outPySideDir, outPythonDir))
                {
                    outRootDir = regRoot;
                    RegCloseKey(hKey);
                    return true;
                }
            }
            RegCloseKey(hKey);
        }

        // 4. Windows Uninstall registry keys (detects any installed OpenUTVDeps MSI package)
        const HKEY rootKeys[] = {HKEY_LOCAL_MACHINE, HKEY_CURRENT_USER};
        const wchar_t* subKeyPaths[] = {L"SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall",
                                        L"SOFTWARE\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall"};

        for (HKEY rk : rootKeys)
        {
            for (const wchar_t* subPath : subKeyPaths)
            {
                HKEY hUninstall = NULL;
                if (RegOpenKeyExW(rk, subPath, 0, KEY_READ, &hUninstall) == ERROR_SUCCESS)
                {
                    DWORD subkeyCount = 0;
                    if (RegQueryInfoKeyW(hUninstall, NULL, NULL, NULL, &subkeyCount, NULL, NULL, NULL, NULL, NULL, NULL, NULL)
                        == ERROR_SUCCESS)
                    {
                        for (DWORD i = 0; i < subkeyCount; ++i)
                        {
                            wchar_t subkeyName[256];
                            DWORD nameLen = 256;
                            if (RegEnumKeyExW(hUninstall, i, subkeyName, &nameLen, NULL, NULL, NULL, NULL) == ERROR_SUCCESS)
                            {
                                HKEY hApp = NULL;
                                if (RegOpenKeyExW(hUninstall, subkeyName, 0, KEY_READ, &hApp) == ERROR_SUCCESS)
                                {
                                    wchar_t dispName[256];
                                    DWORD dispSize = sizeof(dispName);
                                    if (RegQueryValueExW(hApp, L"DisplayName", NULL, NULL, reinterpret_cast<LPBYTE>(dispName), &dispSize)
                                        == ERROR_SUCCESS)
                                    {
                                        if (wcsstr(dispName, L"OpenUTVDeps") != nullptr
                                            || wcsstr(dispName, L"OpenUTV Dependencies") != nullptr)
                                        {
                                            wchar_t installLoc[MAX_PATH];
                                            DWORD locSize = sizeof(installLoc);
                                            if (RegQueryValueExW(hApp, L"InstallLocation", NULL, NULL, reinterpret_cast<LPBYTE>(installLoc),
                                                                 &locSize)
                                                == ERROR_SUCCESS)
                                            {
                                                std::wstring loc(installLoc);
                                                while (!loc.empty() && (loc.back() == L'\\' || loc.back() == L'/'))
                                                {
                                                    loc.pop_back();
                                                }
                                                if (CheckDepsDir(loc, outBinDir, outPySideDir, outPythonDir))
                                                {
                                                    outRootDir = loc;
                                                    RegCloseKey(hApp);
                                                    RegCloseKey(hUninstall);
                                                    return true;
                                                }
                                            }
                                        }
                                    }
                                    RegCloseKey(hApp);
                                }
                            }
                        }
                    }
                    RegCloseKey(hUninstall);
                }
            }
        }

        // 5. Known Program Files and standard install directories
        std::vector<std::wstring> baseSearchDirs;
        wchar_t progFiles[MAX_PATH];
        if (GetEnvironmentVariableW(L"ProgramFiles", progFiles, MAX_PATH) > 0)
        {
            baseSearchDirs.push_back(progFiles);
        }
        baseSearchDirs.push_back(L"C:\\Program Files");

        wchar_t localAppData[MAX_PATH];
        if (GetEnvironmentVariableW(L"LOCALAPPDATA", localAppData, MAX_PATH) > 0)
        {
            baseSearchDirs.push_back(localAppData);
        }
        baseSearchDirs.push_back(L"C:");

        for (const auto& baseDir : baseSearchDirs)
        {
            std::wstring directPath = baseDir + L"\\OpenUTVDeps";
            if (CheckDepsDir(directPath, outBinDir, outPySideDir, outPythonDir))
            {
                outRootDir = directPath;
                return true;
            }

            // Wildcard search for versioned directories: OpenUTVDeps*
            WIN32_FIND_DATAW ffd;
            std::wstring searchPattern = baseDir + L"\\OpenUTVDeps*";
            HANDLE hFind = FindFirstFileW(searchPattern.c_str(), &ffd);
            if (hFind != INVALID_HANDLE_VALUE)
            {
                do
                {
                    if (ffd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)
                    {
                        if (wcscmp(ffd.cFileName, L".") != 0 && wcscmp(ffd.cFileName, L"..") != 0)
                        {
                            std::wstring candRoot = baseDir + L"\\" + ffd.cFileName;
                            if (CheckDepsDir(candRoot, outBinDir, outPySideDir, outPythonDir))
                            {
                                outRootDir = candRoot;
                                FindClose(hFind);
                                return true;
                            }
                        }
                    }
                } while (FindNextFileW(hFind, &ffd));
                FindClose(hFind);
            }
        }

        // 6. Relative paths from app directory (developer & portable installations)
        if (!appDir.empty())
        {
            std::vector<std::wstring> relCandidates = {appDir + L"\\deps", appDir + L"\\..\\deps", appDir + L"\\..\\..\\deps",
                                                       appDir + L"\\..\\..\\utv-dependencies\\exported_deps\\utv-deps-windows-x64",
                                                       appDir + L"\\..\\..\\utv-dependencies\\installed\\x64-windows"};
            for (const auto& cand : relCandidates)
            {
                if (CheckDepsDir(cand, outBinDir, outPySideDir, outPythonDir))
                {
                    outRootDir = cand;
                    return true;
                }
            }
        }

        // 7. Check if OpenImageIO.dll, glew32.dll, OpenColorIO, or Qt6Core.dll is on the system PATH
        const wchar_t* searchDlls[] = {L"OpenImageIO.dll", L"glew32.dll", L"OpenColorIO_2_5.dll", L"Qt6Core.dll"};
        for (const wchar_t* dll : searchDlls)
        {
            wchar_t foundPath[MAX_PATH];
            LPWSTR filePart = NULL;
            DWORD spRes = SearchPathW(NULL, dll, NULL, MAX_PATH, foundPath, &filePart);
            if (spRes > 0 && spRes < MAX_PATH && filePart)
            {
                *filePart = L'\0';
                size_t pathLen = wcslen(foundPath);
                if (pathLen > 0 && foundPath[pathLen - 1] == L'\\')
                {
                    foundPath[pathLen - 1] = L'\0';
                }
                std::wstring binStr(foundPath);
                std::wstring candRoot = binStr;
                size_t lastSlash = binStr.find_last_of(L"\\/");
                if (lastSlash != std::wstring::npos)
                {
                    candRoot = binStr.substr(0, lastSlash);
                }
                if (CheckDepsDir(candRoot, outBinDir, outPySideDir, outPythonDir))
                {
                    outRootDir = candRoot;
                    return true;
                }
                if (CheckDepsDir(binStr, outBinDir, outPySideDir, outPythonDir))
                {
                    outRootDir = binStr;
                    return true;
                }
            }
        }

        return false;
    }

    void ShowMissingDependenciesDialog()
    {
        // Write notification to stderr for terminal / script invocations
        fwprintf(stderr, L"OpenUTV: Required runtime dependencies (OpenUTVDeps) not found.\n");
        fwprintf(stderr, L"Please download and install OpenUTVDeps from: %s\n", DEPS_DOWNLOAD_URL);

        typedef HRESULT(WINAPI * TaskDialogIndirectFn)(const TASKDIALOGCONFIG* pTaskConfig, int* pnButton, int* pnRadioButton,
                                                       BOOL* pfVerificationFlagChecked);

        HMODULE hComCtl = LoadLibraryW(L"comctl32.dll");
        TaskDialogIndirectFn pTaskDialogIndirect = nullptr;
        if (hComCtl)
        {
            pTaskDialogIndirect = reinterpret_cast<TaskDialogIndirectFn>(GetProcAddress(hComCtl, "TaskDialogIndirect"));
        }

        bool shown = false;
        if (pTaskDialogIndirect)
        {
            TASKDIALOG_BUTTON buttons[] = {{1001, L"Download Dependencies\nOpen the OpenUTVDeps download page in your browser."},
                                           {IDCANCEL, L"Exit"}};

            TASKDIALOGCONFIG tc;
            ZeroMemory(&tc, sizeof(tc));
            tc.cbSize = sizeof(tc);
            tc.hwndParent = NULL;
            tc.dwFlags = TDF_USE_COMMAND_LINKS | TDF_ALLOW_DIALOG_CANCELLATION | TDF_POSITION_RELATIVE_TO_WINDOW;
            tc.dwCommonButtons = 0;
            tc.pszWindowTitle = L"OpenUTV";
            tc.pszMainIcon = TD_WARNING_ICON;
            tc.pszMainInstruction = L"OpenUTV Dependencies Required";
            tc.pszContent = L"OpenUTV requires the OpenUTVDeps runtime package (including Qt6, FFmpeg, Python, "
                            L"OpenColorIO, and OpenEXR) which was not found on this computer.\n\n"
                            L"Would you like to open the OpenUTVDeps download page now?";
            tc.cButtons = 2;
            tc.pButtons = buttons;
            tc.nDefaultButton = 1001;

            int nButton = 0;
            HRESULT hr = pTaskDialogIndirect(&tc, &nButton, NULL, NULL);
            if (SUCCEEDED(hr))
            {
                shown = true;
                if (nButton == 1001)
                {
                    ShellExecuteW(NULL, L"open", DEPS_DOWNLOAD_URL, NULL, NULL, SW_SHOWNORMAL);
                }
            }
        }

        if (!shown)
        {
            int res = MessageBoxW(NULL,
                                  L"OpenUTV requires the OpenUTVDeps runtime package (including Qt6, FFmpeg, Python, "
                                  L"OpenColorIO, and OpenEXR) which was not found on this computer.\n\n"
                                  L"Would you like to open the OpenUTVDeps download page now?",
                                  L"OpenUTV - Dependencies Required", MB_ICONEXCLAMATION | MB_YESNO | MB_DEFBUTTON1);
            if (res == IDYES)
            {
                ShellExecuteW(NULL, L"open", DEPS_DOWNLOAD_URL, NULL, NULL, SW_SHOWNORMAL);
            }
        }

        if (hComCtl)
        {
            FreeLibrary(hComCtl);
        }
    }

} // namespace

int RunLauncher()
{
    // Try to attach to parent console if running from cmd.exe or PowerShell
    AttachConsole(ATTACH_PARENT_PROCESS);

    std::wstring appDir = GetAppDir();
    std::wstring depsRoot;
    std::wstring depsBin;
    std::wstring depsPySide;
    std::wstring depsPython;

    if (!FindDependencies(appDir, depsRoot, depsBin, depsPySide, depsPython))
    {
        ShowMissingDependenciesDialog();
        return 1;
    }

    // Configure DLL search directory
    SetDllDirectoryW(depsBin.c_str());

    typedef BOOL(WINAPI * SetDefaultDllDirectoriesFn)(DWORD);
    typedef DLL_DIRECTORY_COOKIE(WINAPI * AddDllDirectoryFn)(PCWSTR);
    HMODULE hKernel32 = GetModuleHandleW(L"kernel32.dll");
    if (hKernel32)
    {
        SetDefaultDllDirectoriesFn pSetDefaultDllDirs =
            reinterpret_cast<SetDefaultDllDirectoriesFn>(GetProcAddress(hKernel32, "SetDefaultDllDirectories"));
        AddDllDirectoryFn pAddDllDir = reinterpret_cast<AddDllDirectoryFn>(GetProcAddress(hKernel32, "AddDllDirectory"));
        if (pSetDefaultDllDirs && pAddDllDir)
        {
            pSetDefaultDllDirs(LOAD_LIBRARY_SEARCH_DEFAULT_DIRS | LOAD_LIBRARY_SEARCH_USER_DIRS);
            pAddDllDir(depsBin.c_str());
            if (!depsPySide.empty())
            {
                pAddDllDir(depsPySide.c_str());
            }
            std::wstring shibokenDir = depsPySide + L"\\..\\shiboken6";
            if (DirExists(shibokenDir))
            {
                pAddDllDir(shibokenDir.c_str());
            }
            if (!depsPython.empty())
            {
                pAddDllDir(depsPython.c_str());
            }
            if (!appDir.empty())
            {
                pAddDllDir(appDir.c_str());
            }
        }
    }

    // Export OPENUTV_DEPS_ROOT and OPENUTV_DEPS_ROOT_SLASH for runtime child processes
    SetEnvironmentVariableW(L"OPENUTV_DEPS_ROOT", depsRoot.c_str());
    std::wstring rootSlash = depsRoot;
    std::replace(rootSlash.begin(), rootSlash.end(), L'\\', L'/');
    SetEnvironmentVariableW(L"OPENUTV_DEPS_ROOT_SLASH", rootSlash.c_str());

    // Prepend dependency paths to process PATH
    std::wstring currentPath;
    DWORD pathLen = GetEnvironmentVariableW(L"PATH", NULL, 0);
    if (pathLen > 0)
    {
        std::vector<wchar_t> pathBuf(pathLen);
        GetEnvironmentVariableW(L"PATH", pathBuf.data(), pathLen);
        currentPath = pathBuf.data();
    }

    std::wstring newPath = appDir + L";" + depsBin;
    if (!depsPySide.empty())
    {
        newPath = newPath + L";" + depsPySide;
        std::wstring shibokenDir = depsPySide + L"\\..\\shiboken6";
        if (DirExists(shibokenDir))
        {
            newPath = newPath + L";" + shibokenDir;
        }
    }
    if (!depsPython.empty())
    {
        newPath = newPath + L";" + depsPython + L";" + depsPython + L"\\Scripts";

        // Set PYTHONHOME if not explicitly specified
        if (GetEnvironmentVariableW(L"PYTHONHOME", NULL, 0) == 0)
        {
            SetEnvironmentVariableW(L"PYTHONHOME", depsPython.c_str());
        }
    }

    if (!currentPath.empty())
    {
        newPath = newPath + L";" + currentPath;
    }
    SetEnvironmentVariableW(L"PATH", newPath.c_str());

    // Configure QT_PLUGIN_PATH if not explicitly specified
    if (GetEnvironmentVariableW(L"QT_PLUGIN_PATH", NULL, 0) == 0)
    {
        std::wstring pluginPathEnv;
        std::vector<std::wstring> candidatePluginDirs;
        if (!depsPySide.empty() && DirExists(depsPySide + L"\\plugins"))
        {
            candidatePluginDirs.push_back(depsPySide + L"\\plugins");
        }
        candidatePluginDirs.push_back(depsRoot + L"\\plugins");
        candidatePluginDirs.push_back(depsRoot + L"\\plugins\\Qt");
        candidatePluginDirs.push_back(appDir + L"\\plugins\\Qt");

        for (const auto& pDir : candidatePluginDirs)
        {
            if (DirExists(pDir))
            {
                if (!pluginPathEnv.empty())
                {
                    pluginPathEnv += L";";
                }
                pluginPathEnv += pDir;
            }
        }
        if (!pluginPathEnv.empty())
        {
            SetEnvironmentVariableW(L"QT_PLUGIN_PATH", pluginPathEnv.c_str());
        }
    }

    // Configure QtWebEngine and QML paths if PySide6 Qt is used
    if (!depsPySide.empty())
    {
        if (GetEnvironmentVariableW(L"QTWEBENGINEPROCESS_PATH", NULL, 0) == 0)
        {
            std::wstring wep = depsPySide + L"\\QtWebEngineProcess.exe";
            if (FileExists(wep))
            {
                SetEnvironmentVariableW(L"QTWEBENGINEPROCESS_PATH", wep.c_str());
            }
        }
        if (GetEnvironmentVariableW(L"QTWEBENGINE_RESOURCES_PATH", NULL, 0) == 0)
        {
            std::wstring res = depsPySide + L"\\resources";
            if (DirExists(res))
            {
                SetEnvironmentVariableW(L"QTWEBENGINE_RESOURCES_PATH", res.c_str());
            }
        }
        if (GetEnvironmentVariableW(L"QTWEBENGINE_LOCALES_PATH", NULL, 0) == 0)
        {
            std::wstring loc = depsPySide + L"\\translations\\qtwebengine_locales";
            if (DirExists(loc))
            {
                SetEnvironmentVariableW(L"QTWEBENGINE_LOCALES_PATH", loc.c_str());
            }
        }
        if (GetEnvironmentVariableW(L"QML2_IMPORT_PATH", NULL, 0) == 0)
        {
            std::wstring qml = depsPySide + L"\\qml";
            if (DirExists(qml))
            {
                SetEnvironmentVariableW(L"QML2_IMPORT_PATH", qml.c_str());
                SetEnvironmentVariableW(L"QML_IMPORT_PATH", qml.c_str());
            }
        }
    }

    // Check for software OpenGL fallback flag or requirement
    const wchar_t* rawCommandLine = GetCommandLineW();
    if (rawCommandLine && (wcsstr(rawCommandLine, L"--software-gl") != nullptr || wcsstr(rawCommandLine, L"-software-gl") != nullptr))
    {
        SetEnvironmentVariableW(L"QT_OPENGL", L"software");
        if (!FileExists(appDir + L"\\opengl32.dll"))
        {
            if (FileExists(appDir + L"\\opengl32sw.dll"))
            {
                CopyFileW((appDir + L"\\opengl32sw.dll").c_str(), (appDir + L"\\opengl32.dll").c_str(), FALSE);
            }
            else if (!depsPySide.empty() && FileExists(depsPySide + L"\\opengl32sw.dll"))
            {
                CopyFileW((depsPySide + L"\\opengl32sw.dll").c_str(), (appDir + L"\\opengl32.dll").c_str(), FALSE);
            }
        }
    }

    // Locate core application executable: utv-bin.exe (or rv-bin.exe)
    std::wstring targetExe = appDir + L"\\utv-bin.exe";
    if (!FileExists(targetExe))
    {
        targetExe = appDir + L"\\rv-bin.exe";
        if (!FileExists(targetExe))
        {
            MessageBoxW(NULL, L"Unable to locate utv-bin.exe or rv-bin.exe in the application directory.", L"OpenUTV Launcher Error",
                        MB_ICONERROR | MB_OK);
            return 1;
        }
    }

    // Build command line preserving all caller arguments
    std::wstring cmdLine = L"\"" + targetExe + L"\"";
    const wchar_t* rawCmd = GetCommandLineW();
    if (rawCmd)
    {
        const wchar_t* p = rawCmd;
        while (*p == L' ' || *p == L'\t')
        {
            p++;
        }
        if (*p == L'"')
        {
            p++;
            while (*p && *p != L'"')
            {
                p++;
            }
            if (*p == L'"')
            {
                p++;
            }
        }
        else
        {
            while (*p && *p != L' ' && *p != L'\t')
            {
                p++;
            }
        }
        while (*p == L' ' || *p == L'\t')
        {
            p++;
        }
        if (*p)
        {
            cmdLine += L" ";
            cmdLine += p;
        }
    }

    std::vector<wchar_t> cmdBuf(cmdLine.begin(), cmdLine.end());
    cmdBuf.push_back(L'\0');

    STARTUPINFOW si;
    PROCESS_INFORMATION pi;
    ZeroMemory(&si, sizeof(si));
    si.cb = sizeof(si);
    ZeroMemory(&pi, sizeof(pi));

    si.dwFlags |= STARTF_USESTDHANDLES;
    si.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
    si.hStdOutput = GetStdHandle(STD_OUTPUT_HANDLE);
    si.hStdError = GetStdHandle(STD_ERROR_HANDLE);

    BOOL created = CreateProcessW(targetExe.c_str(), cmdBuf.data(), NULL, NULL, TRUE, 0, NULL, NULL, &si, &pi);

    if (!created)
    {
        DWORD err = GetLastError();
        wchar_t errMsg[256];
        swprintf_s(errMsg, 256, L"Failed to launch core application (utv-bin.exe).\nError code: %lu", err);
        MessageBoxW(NULL, errMsg, L"OpenUTV Launcher Error", MB_ICONERROR | MB_OK);
        return 1;
    }

    CloseHandle(pi.hThread);
    WaitForSingleObject(pi.hProcess, INFINITE);

    DWORD exitCode = 0;
    GetExitCodeProcess(pi.hProcess, &exitCode);
    CloseHandle(pi.hProcess);

    return static_cast<int>(exitCode);
}

int wmain(int argc, wchar_t* argv[]) { return RunLauncher(); }

int WINAPI wWinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, PWSTR lpCmdLine, int nCmdShow) { return RunLauncher(); }

#endif // defined(_WIN32)
