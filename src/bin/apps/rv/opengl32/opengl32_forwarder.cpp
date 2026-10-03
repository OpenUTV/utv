//
// Copyright (C) 2026 Makai Systems and OpenUTV Contributors.
//
// SPDX-License-Identifier: Apache-2.0
//

//
//  opengl32.dll forwarder, installed next to utv-bin.exe and the other OpenGL programs.
//
//  The programs import opengl32.dll, and Windows loads it from the application directory first. This
//  DLL then picks the real implementation for the process, on the first OpenGL call:
//
//    UTV_OPENGL=hardware (or unset)  the system opengl32.dll, which drives the GPU
//    UTV_OPENGL=software             Mesa llvmpipe (opengl32sw.dll), for machines without an OpenGL driver
//
//  UTV_SOFTWARE_GL=1 also selects Mesa when UTV_OPENGL is unset. The launcher sets UTV_OPENGL after
//  probing the GPU, and the processes the viewer starts inherit it.
//
//  Every module in the process gets the same implementation: our executables and DLLs, glu32.dll, Qt
//  (which loads "opengl32.dll" by name) and GDI (SetPixelFormat and SwapBuffers call into it). So the
//  choice is made per process, without copying Mesa into the installation directory.
//
//  Functions the implementation does not export (Mesa has no Glmf* metafile functions) return zero.
//

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif

#include <windows.h>

#include <atomic>
#include <string>

typedef unsigned int GLenum;
typedef unsigned char GLboolean;
typedef unsigned int GLbitfield;
typedef signed char GLbyte;
typedef short GLshort;
typedef int GLint;
typedef int GLsizei;
typedef unsigned char GLubyte;
typedef unsigned short GLushort;
typedef unsigned int GLuint;
typedef float GLfloat;
typedef float GLclampf;
typedef double GLdouble;
typedef double GLclampd;
typedef void GLvoid;

namespace
{

    enum FunctionId
    {

#define OPENGL32_FUNCTION(ret, name, params, args) id_##name,
#include "opengl32_functions.inc"
#undef OPENGL32_FUNCTION
        FunctionCount
    };

    const char* const kNames[] = {
#define OPENGL32_FUNCTION(ret, name, params, args) #name,
#include "opengl32_functions.inc"
#undef OPENGL32_FUNCTION
    };

    FARPROC g_functions[FunctionCount];
    INIT_ONCE g_once = INIT_ONCE_STATIC_INIT;
    std::atomic<bool> g_ready(false);

    std::wstring GetEnv(const wchar_t* name)
    {
        wchar_t buf[MAX_PATH * 2];
        DWORD len = GetEnvironmentVariableW(name, buf, static_cast<DWORD>(sizeof(buf) / sizeof(buf[0])));
        return len > 0 && len < sizeof(buf) / sizeof(buf[0]) ? std::wstring(buf, len) : std::wstring();
    }

    bool WantSoftware()
    {
        std::wstring mode = GetEnv(L"UTV_OPENGL");
        if (_wcsicmp(mode.c_str(), L"software") == 0)
            return true;
        if (_wcsicmp(mode.c_str(), L"hardware") == 0)
            return false;
        std::wstring force = GetEnv(L"UTV_SOFTWARE_GL");
        return !force.empty() && force != L"0";
    }

    std::wstring OwnDirectory()
    {
        HMODULE self = NULL;
        wchar_t path[MAX_PATH];
        if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                                reinterpret_cast<LPCWSTR>(&OwnDirectory), &self))
            return L"";
        DWORD len = GetModuleFileNameW(self, path, MAX_PATH);
        if (len == 0 || len >= MAX_PATH)
            return L"";
        std::wstring dir(path, len);
        size_t slash = dir.find_last_of(L"\\/");
        return slash == std::wstring::npos ? L"" : dir.substr(0, slash);
    }

    HMODULE LoadFrom(const std::wstring& path)
    {
        if (path.empty() || GetFileAttributesW(path.c_str()) == INVALID_FILE_ATTRIBUTES)
            return NULL;
        return LoadLibraryExW(path.c_str(), NULL, LOAD_WITH_ALTERED_SEARCH_PATH);
    }

    // Mesa as shipped with PySide6 in OpenUTVDeps.
    std::wstring DepsMesa(const wchar_t* rootVariable)
    {
        std::wstring root = GetEnv(rootVariable);
        return root.empty() ? root : root + L"\\tools\\python3\\Lib\\site-packages\\PySide6\\opengl32sw.dll";
    }

    HMODULE LoadMesa()
    {
        const std::wstring candidates[] = {GetEnv(L"UTV_OPENGL_SOFTWARE_DLL"), OwnDirectory() + L"\\opengl32sw.dll",
                                           DepsMesa(L"UTV_DEPS_ROOT"), DepsMesa(L"OPENUTV_DEPS_ROOT")};
        for (const std::wstring& c : candidates)
        {
            if (HMODULE mesa = LoadFrom(c))
                return mesa;
        }
        OutputDebugStringW(L"opengl32 forwarder: software OpenGL requested but opengl32sw.dll was not found\n");
        return NULL;
    }

    HMODULE LoadSystem()
    {
        // By full path: a plain "opengl32.dll" would be this DLL again.
        wchar_t dir[MAX_PATH];
        UINT len = GetSystemDirectoryW(dir, MAX_PATH);
        if (len == 0 || len >= MAX_PATH)
            return NULL;
        return LoadFrom(std::wstring(dir, len) + L"\\opengl32.dll");
    }

    BOOL CALLBACK Resolve(PINIT_ONCE, PVOID, PVOID*)
    {
        HMODULE implementation = WantSoftware() ? LoadMesa() : NULL;
        if (!implementation)
            implementation = LoadSystem();
        if (implementation)
        {
            for (int i = 0; i < FunctionCount; ++i)
                g_functions[i] = GetProcAddress(implementation, kNames[i]);
        }
        return TRUE;
    }

    inline FARPROC Function(FunctionId id)
    {
        if (!g_ready.load(std::memory_order_acquire))
        {
            InitOnceExecuteOnce(&g_once, Resolve, NULL, NULL);
            g_ready.store(true, std::memory_order_release);
        }
        return g_functions[id];
    }

} // namespace

//
//  utv_<name> is exported as <name> (opengl32.def): defining the real names here would clash with the
//  dllimport declarations of the WGL functions in windows.h.
//
#define OPENGL32_FUNCTION(ret, name, params, args)         \
    extern "C" ret WINAPI utv_##name params                \
    {                                                      \
        typedef ret Result;                                \
        typedef Result(WINAPI* Fn) params;                 \
        Fn fn = reinterpret_cast<Fn>(Function(id_##name)); \
        if (!fn)                                           \
            return Result();                               \
        return fn args;                                    \
    }
#include "opengl32_functions.inc"
#undef OPENGL32_FUNCTION
