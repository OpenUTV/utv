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

    bool CheckDepsDir(const std::wstring& root, std::wstring& outBinDir)
    {
        if (root.empty())
        {
            return false;
        }

        // Check root\bin\Qt6Core.dll
        std::wstring binPath = root + L"\\bin";
        if (FileExists(binPath + L"\\Qt6Core.dll"))
        {
            outBinDir = binPath;
            return true;
        }

        // Check root\installed\x64-windows\bin\Qt6Core.dll (vcpkg export structure)
        std::wstring vcpkgBinPath = root + L"\\installed\\x64-windows\\bin";
        if (FileExists(vcpkgBinPath + L"\\Qt6Core.dll"))
        {
            outBinDir = vcpkgBinPath;
            return true;
        }

        return false;
    }

    bool FindDependencies(const std::wstring& appDir, std::wstring& outRootDir, std::wstring& outBinDir)
    {
        // 1. Environment variable OPENUTV_DEPS_ROOT
        DWORD len = GetEnvironmentVariableW(L"OPENUTV_DEPS_ROOT", NULL, 0);
        if (len > 0)
        {
            std::vector<wchar_t> buf(len);
            GetEnvironmentVariableW(L"OPENUTV_DEPS_ROOT", buf.data(), len);
            std::wstring envRoot(buf.data());
            if (CheckDepsDir(envRoot, outBinDir))
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
                if (CheckDepsDir(regRoot, outBinDir))
                {
                    outRootDir = regRoot;
                    RegCloseKey(hKey);
                    return true;
                }
            }
            RegCloseKey(hKey);
        }

        // 3. Known Program Files and standard install directories
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
            if (CheckDepsDir(directPath, outBinDir))
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
                            if (CheckDepsDir(candRoot, outBinDir))
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

        // 4. Relative paths from app directory (developer & portable installations)
        if (!appDir.empty())
        {
            std::vector<std::wstring> relCandidates = {appDir + L"\\deps", appDir + L"\\..\\deps", appDir + L"\\..\\..\\deps",
                                                       appDir + L"\\..\\..\\utv-dependencies\\exported_deps\\utv-deps-windows-x64",
                                                       appDir + L"\\..\\..\\utv-dependencies\\installed\\x64-windows"};
            for (const auto& cand : relCandidates)
            {
                if (CheckDepsDir(cand, outBinDir))
                {
                    outRootDir = cand;
                    return true;
                }
            }
        }

        // 5. Check if Qt6Core.dll is on the system PATH
        wchar_t foundPath[MAX_PATH];
        LPWSTR filePart = NULL;
        DWORD spRes = SearchPathW(NULL, L"Qt6Core.dll", NULL, MAX_PATH, foundPath, &filePart);
        if (spRes > 0 && spRes < MAX_PATH)
        {
            if (filePart)
            {
                *filePart = L'\0';
                size_t len = wcslen(foundPath);
                if (len > 0 && foundPath[len - 1] == L'\\')
                {
                    foundPath[len - 1] = L'\0';
                }
                outBinDir = foundPath;
                std::wstring binStr(foundPath);
                size_t lastSlash = binStr.find_last_of(L"\\/");
                if (lastSlash != std::wstring::npos)
                {
                    outRootDir = binStr.substr(0, lastSlash);
                }
                else
                {
                    outRootDir = binStr;
                }
                return true;
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

    if (!FindDependencies(appDir, depsRoot, depsBin))
    {
        ShowMissingDependenciesDialog();
        return 1;
    }

    // Configure DLL search directory
    SetDllDirectoryW(depsBin.c_str());

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

    std::wstring newPath = depsBin;

    // Add bundled Python to PATH if present
    std::wstring pythonDir = depsRoot + L"\\tools\\python3";
    if (!DirExists(pythonDir))
    {
        pythonDir = depsRoot + L"\\installed\\x64-windows\\tools\\python3";
    }
    if (DirExists(pythonDir))
    {
        newPath = pythonDir + L";" + pythonDir + L"\\Scripts;" + newPath;

        // Set PYTHONHOME if not explicitly specified
        if (GetEnvironmentVariableW(L"PYTHONHOME", NULL, 0) == 0)
        {
            SetEnvironmentVariableW(L"PYTHONHOME", pythonDir.c_str());
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
        std::vector<std::wstring> candidatePluginDirs = {depsRoot + L"\\plugins", depsRoot + L"\\plugins\\Qt",
                                                         depsRoot + L"\\installed\\x64-windows\\plugins", appDir + L"\\plugins\\Qt",
                                                         appDir + L"\\..\\plugins\\Qt"};
        std::wstring pluginPathEnv;
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
