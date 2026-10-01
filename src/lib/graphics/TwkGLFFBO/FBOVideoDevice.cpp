//******************************************************************************
// Copyright (c) 2007 Tweak Inc.
// All rights reserved.
//
// SPDX-License-Identifier: Apache-2.0
//
//******************************************************************************

#include <TwkGLFFBO/FBOVideoDevice.h>
#include <TwkGLF/GL.h>
#include <TwkGLF/GLFBO.h>
#include <TwkExc/Exception.h>
#include <cstdlib>
#include <iostream>

#ifdef PLATFORM_LINUX
#include <GL/glx.h>
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <cstring>
#include <string>
#include <vector>
#endif

#ifdef PLATFORM_WINDOWS

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <gl/gl.h>
#include <gl/glu.h>

#undef WIN32_LEAN_AND_MEAN
#undef NOMINMAX

#include <gl/glew.h>
#endif

#ifdef PLATFORM_DARWIN
#include <OpenGL/CGLTypes.h>
#include <OpenGL/CGLRenderers.h>
#endif

namespace TwkGLF
{
    using namespace std;

#if defined(PLATFORM_LINUX)
    //
    //  Xlib's default error handler prints the error and exits the process.
    //  Log X protocol errors (with the failing request) and keep going, as Qt
    //  does; GL calls report their own failures.
    //
    static int fboXErrorHandler(Display* display, XErrorEvent* event)
    {
        char text[256] = {0};
        XGetErrorText(display, event->error_code, text, sizeof(text));
        cerr << "WARNING: X error: " << text << " (request " << int(event->request_code) << "." << int(event->minor_code) << ", resource 0x"
             << hex << event->resourceid << dec << ")" << endl;
        return 0;
    }
#endif
    using namespace TwkApp;

    bool FBOVideoDevice::m_swRendererOnMac = false;

#if defined(PLATFORM_DARWIN)
    struct FBOImp
    {
        FBOImp()
            : pfo(0)
            , npfo(0)
            , ctx(0)
        {
        }

        CGLPixelFormatObj pfo;
        GLint npfo;
        CGLContextObj ctx;
    };
#endif

#if defined(PLATFORM_LINUX)
    struct FBOImp
    {
        FBOImp()
            : display(0)
            , root(0)
            , vis(0)
            , tiny(0)
            , ctx(0)
            , useEGL(false)
            , eglDisplay(EGL_NO_DISPLAY)
            , eglContext(EGL_NO_CONTEXT)
            , eglSurface(EGL_NO_SURFACE)
        {
        }

        // GLX: used when an X display is available.
        Display* display;
        Window root;
        XVisualInfo* vis;
        Window tiny;
        GLXContext ctx;

        // EGL: used without an X display (render nodes, containers).
        bool useEGL;
        EGLDisplay eglDisplay;
        EGLContext eglContext;
        EGLSurface eglSurface;
    };

    static bool envIsSet(const char* name)
    {
        const char* value = getenv(name);
        return value && *value && strcmp(value, "0") != 0;
    }

    static bool hasExtension(const char* extensions, const char* name)
    {
        if (!extensions)
            return false;
        const size_t len = strlen(name);
        for (const char* p = strstr(extensions, name); p; p = strstr(p + len, name))
        {
            if ((p == extensions || p[-1] == ' ') && (p[len] == ' ' || p[len] == '\0'))
                return true;
        }
        return false;
    }

    //
    //  GLX context on a hidden window. Needs an X display. Returns an empty
    //  string on success, otherwise the reason it failed.
    //
    static string initGLX(FBOImp* imp)
    {
        XSetWindowAttributes swa;
        int attrs[] = {GLX_BUFFER_SIZE, 32, GLX_RGBA, 0, GLX_STENCIL_SIZE, 1};

        XSetErrorHandler(fboXErrorHandler);
        imp->display = XOpenDisplay(0);
        if (!imp->display)
        {
            const char* display = getenv("DISPLAY");
            return string("cannot open X display '") + (display ? display : "") + "'";
        }

        imp->root = DefaultRootWindow(imp->display);
        imp->vis = glXChooseVisual(imp->display, DefaultScreen(imp->display), attrs);
        if (!imp->vis)
        {
            XCloseDisplay(imp->display);
            imp->display = 0;
            return "no suitable GLX visual";
        }

        swa.colormap = XCreateColormap(imp->display, imp->root, imp->vis->visual, AllocNone);
        swa.event_mask = ExposureMask | KeyPressMask;
        // The GLX visual's depth can differ from the root window's (e.g. a 32-bit ARGB visual on a 24-bit
        // screen); X then requires an explicit border pixel, or XCreateWindow fails with BadMatch.
        swa.border_pixel = 0;

        imp->tiny = XCreateWindow(imp->display, imp->root, 0, 0, 64, 64, 0, imp->vis->depth, InputOutput, imp->vis->visual,
                                  CWColormap | CWEventMask | CWBorderPixel, &swa);

        imp->ctx = glXCreateContext(imp->display, imp->vis, 0, True);
        if (!imp->ctx || !glXMakeCurrent(imp->display, imp->tiny, imp->ctx))
        {
            if (imp->ctx)
                glXDestroyContext(imp->display, imp->ctx);
            XDestroyWindow(imp->display, imp->tiny);
            XCloseDisplay(imp->display);
            imp->ctx = 0;
            imp->display = 0;
            return "cannot create or activate a GLX context";
        }

        return "";
    }

    //
    //  Bind the OpenGL API on an initialized EGL display and create a context
    //  that is current without a window: surfaceless if supported, otherwise
    //  on a tiny pbuffer.
    //
    static bool createEGLContext(FBOImp* imp, EGLDisplay display)
    {
        if (!eglBindAPI(EGL_OPENGL_API))
            return false;

        const EGLint configAttrs[] = {EGL_SURFACE_TYPE,
                                      EGL_PBUFFER_BIT,
                                      EGL_RENDERABLE_TYPE,
                                      EGL_OPENGL_BIT,
                                      EGL_RED_SIZE,
                                      8,
                                      EGL_GREEN_SIZE,
                                      8,
                                      EGL_BLUE_SIZE,
                                      8,
                                      EGL_ALPHA_SIZE,
                                      8,
                                      EGL_NONE};
        EGLConfig config;
        EGLint numConfigs = 0;
        if (!eglChooseConfig(display, configAttrs, &config, 1, &numConfigs) || numConfigs < 1)
            return false;

        EGLContext context = eglCreateContext(display, config, EGL_NO_CONTEXT, NULL);
        if (context == EGL_NO_CONTEXT)
            return false;

        EGLSurface surface = EGL_NO_SURFACE;
        if (!hasExtension(eglQueryString(display, EGL_EXTENSIONS), "EGL_KHR_surfaceless_context"))
        {
            const EGLint pbufferAttrs[] = {EGL_WIDTH, 16, EGL_HEIGHT, 16, EGL_NONE};
            surface = eglCreatePbufferSurface(display, config, pbufferAttrs);
        }

        if (!eglMakeCurrent(display, surface, surface, context))
        {
            if (surface != EGL_NO_SURFACE)
                eglDestroySurface(display, surface);
            eglDestroyContext(display, context);
            return false;
        }

        imp->eglDisplay = display;
        imp->eglContext = context;
        imp->eglSurface = surface;
        return true;
    }

    //
    //  EGL context without a window system: no X server needed. Tries the GPU
    //  first (EGL device platform, e.g. NVIDIA or Mesa DRM render nodes), then
    //  Mesa's surfaceless platform (llvmpipe software rendering on machines
    //  without a GPU). softwareOnly skips the device platform. Returns an
    //  empty string on success, otherwise the reason it failed.
    //
    static string initEGL(FBOImp* imp, bool softwareOnly)
    {
        const char* clientExtensions = eglQueryString(EGL_NO_DISPLAY, EGL_EXTENSIONS);

        if (!softwareOnly && hasExtension(clientExtensions, "EGL_EXT_platform_device")
            && (hasExtension(clientExtensions, "EGL_EXT_device_enumeration") || hasExtension(clientExtensions, "EGL_EXT_device_base")))
        {
            typedef EGLBoolean (*QueryDevicesFunc)(EGLint, EGLDeviceEXT*, EGLint*);
            QueryDevicesFunc queryDevices = (QueryDevicesFunc)eglGetProcAddress("eglQueryDevicesEXT");

            EGLint numDevices = 0;
            if (queryDevices && queryDevices(0, NULL, &numDevices) && numDevices > 0)
            {
                vector<EGLDeviceEXT> devices(numDevices);
                queryDevices(numDevices, devices.data(), &numDevices);

                for (EGLint i = 0; i < numDevices; ++i)
                {
                    EGLDisplay display = eglGetPlatformDisplay(EGL_PLATFORM_DEVICE_EXT, devices[i], NULL);
                    if (display == EGL_NO_DISPLAY || !eglInitialize(display, NULL, NULL))
                        continue;
                    if (createEGLContext(imp, display))
                        return "";
                    eglTerminate(display);
                }
            }
        }

        if (hasExtension(clientExtensions, "EGL_MESA_platform_surfaceless"))
        {
            EGLDisplay display = eglGetPlatformDisplay(EGL_PLATFORM_SURFACELESS_MESA, EGL_DEFAULT_DISPLAY, NULL);
            if (display != EGL_NO_DISPLAY && eglInitialize(display, NULL, NULL))
            {
                if (createEGLContext(imp, display))
                    return "";
                eglTerminate(display);
            }
        }

        return "no usable EGL device or surfaceless platform (is a GPU driver or Mesa installed?)";
    }
#endif

#if defined(PLATFORM_WINDOWS)
    struct FBOImp
    {
        FBOImp()
            : deviceContext(0)
        {
        }

        // HPBUFFERARB pbuffer;
        HWND window;
        HDC deviceContext;
        HGLRC glContext;
        PIXELFORMATDESCRIPTOR format;
    };
#endif

    FBOVideoDevice::FBOVideoDevice(VideoModule* m, int w, int h, bool alpha, int numFBOs)
        : GLVideoDevice(m, "fbo-rb", GLVideoDevice::ImageOutput)
        , m_width(w)
        , m_height(h)
        , m_alpha(alpha)
    {
        m_imp = new FBOImp();

        //--------------------------------------------------
        // platform specific stuff

#if defined(PLATFORM_DARWIN)

        unsigned long hwAttrs[] = {kCGLPFAAccelerated,
                                   kCGLPFAColorFloat, /* color buffers store floating point pixels */
                                   kCGLPFAColorSize,
                                   3 * 16,
                                   kCGLPFAAlphaSize,
                                   1 * 16,
                                   0};

        unsigned long swAttrs[] = {kCGLPFAAllRenderers,
                                   kCGLPFARendererID,
                                   kCGLRendererAppleSWID,
                                   kCGLPFAColorFloat, /* color buffers store floating point pixels */
                                   kCGLPFAColorSize,
                                   3 * 32,
                                   kCGLPFAAlphaSize,
                                   1 * 32,
                                   0};

        const bool forceSoftware = m_swRendererOnMac || getenv("UTV_SOFTWARE_GL");
        unsigned long* attrs = forceSoftware ? swAttrs : hwAttrs;
        CGLError err = CGLChoosePixelFormat((CGLPixelFormatAttribute*)attrs, &m_imp->pfo, &m_imp->npfo);

        //
        //  No accelerated renderer (e.g. headless VMs, CI runners, render
        //  nodes without a GPU): fall back to Apple's software renderer rather
        //  than failing outright.
        //
        if ((err != kCGLNoError || !m_imp->pfo) && !forceSoftware)
        {
            cout << "WARNING: no accelerated OpenGL pixel format (" << CGLErrorString(err) << "), using the software renderer" << endl;
            err = CGLChoosePixelFormat((CGLPixelFormatAttribute*)swAttrs, &m_imp->pfo, &m_imp->npfo);
        }

        if (err != kCGLNoError || !m_imp->pfo)
        {
            cout << "ERROR: choosing pixel format: " << CGLErrorString(err) << endl;
            exit(-1);
        }

        if (CGLError err = CGLCreateContext(m_imp->pfo, 0, &m_imp->ctx))
        {
            cout << "ERROR: create context: " << CGLErrorString(err) << endl;
            exit(-1);
        }

        // cout << "DEBUG: made the context" << endl;

        if (CGLError err = CGLSetCurrentContext(m_imp->ctx))
        {
            cout << "ERROR: CGLSetCurrentContext " << CGLErrorString(err) << endl;
            exit(-1);
        }

#endif

#if defined(PLATFORM_LINUX)
        //
        //  Offscreen GL context. With an X display, GLX; without one (render
        //  nodes, containers), EGL with no window system. UTV_GL_PLATFORM=glx|egl
        //  forces one; UTV_SOFTWARE_GL or LIBGL_ALWAYS_SOFTWARE selects software
        //  rendering.
        //
        const char* platformEnv = getenv("UTV_GL_PLATFORM");
        const string platform = platformEnv ? platformEnv : "";
        if (!platform.empty() && platform != "glx" && platform != "egl")
        {
            cout << "WARNING: ignoring unknown UTV_GL_PLATFORM=" << platform << " (expected glx or egl)" << endl;
        }

        if (envIsSet("UTV_SOFTWARE_GL"))
            setenv("LIBGL_ALWAYS_SOFTWARE", "1", 1);
        const bool softwareOnly = envIsSet("LIBGL_ALWAYS_SOFTWARE");

        const char* displayEnv = getenv("DISPLAY");
        const bool haveDisplay = displayEnv && *displayEnv;
        const bool tryGLX = platform == "glx" || (platform != "egl" && haveDisplay);
        const bool tryEGL = platform != "glx";

        string glxError, eglError;
        bool ready = false;

        if (tryGLX)
        {
            glxError = initGLX(m_imp);
            ready = glxError.empty();
        }

        if (!ready && tryEGL)
        {
            eglError = initEGL(m_imp, softwareOnly);
            ready = eglError.empty();
            m_imp->useEGL = ready;
        }

        if (!ready)
        {
            cout << "ERROR: cannot create an offscreen OpenGL context." << endl;
            if (!glxError.empty())
                cout << "ERROR:   GLX: " << glxError << endl;
            if (!eglError.empty())
                cout << "ERROR:   EGL: " << eglError << endl;
            exit(-1);
        }

#ifdef TWK_USE_GLEW
        if (GLenum err = TWK_GLEW_INIT(NULL))
        {
            cout << "ERROR: GLEW initialization failed: " << glewGetErrorString(err) << endl;
            exit(-1);
        }
#endif

        if (envIsSet("UTV_GL_DEBUG"))
        {
            const GLubyte* renderer = glGetString(GL_RENDERER);
            cout << "INFO: offscreen OpenGL context: " << (m_imp->useEGL ? "EGL (no X display)" : "GLX") << ", renderer "
                 << (renderer ? (const char*)renderer : "unknown") << endl;
        }
#endif

#if defined(PLATFORM_WINDOWS)

        HINSTANCE hInstance = GetModuleHandle(0);
        assert(hInstance != NULL);
        static const char className[] = "fbopbuffer";
        WNDCLASS wc;

#ifdef UNICODE
        potato
#else
        int a = 0;
#endif

            if (!GetClassInfo(hInstance, className, &wc))
        {
            wc.style = CS_OWNDC;
            wc.lpfnWndProc = DefWindowProc;
            wc.cbClsExtra = 0;
            wc.cbWndExtra = 0;
            wc.hInstance = hInstance;
            wc.hIcon = LoadIcon(NULL, IDI_APPLICATION);
            wc.hCursor = LoadCursor(NULL, IDC_ARROW);
            wc.hbrBackground = NULL;
            wc.lpszMenuName = NULL;
            wc.lpszClassName = className;

            if (!RegisterClass(&wc))
            {
                int registerClassFailed = 0;
                assert(registerClassFailed == 1);
            }
        }

        m_imp->window = CreateWindow(className, 0, 0, 0, 0, 0, 0, 0, 0, hInstance, 0);
        assert(m_imp->window != NULL);

        m_imp->deviceContext = GetDC(m_imp->window);
        assert(m_imp->deviceContext != NULL);

        // m_imp->pbuffer = wglCreatePbufferARB()

        m_imp->format.nSize = sizeof(PIXELFORMATDESCRIPTOR);
        m_imp->format.nVersion = 1;
        m_imp->format.dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER | PFD_GENERIC_ACCELERATED;
        m_imp->format.iPixelType = PFD_TYPE_RGBA;
        m_imp->format.cColorBits = 32;
        m_imp->format.cRedBits = 8;
        m_imp->format.cRedShift = 0;
        m_imp->format.cGreenBits = 8;
        m_imp->format.cGreenShift = 0;
        m_imp->format.cBlueBits = 8;
        m_imp->format.cBlueShift = 0;
        m_imp->format.cAlphaBits = 8;
        m_imp->format.cAlphaShift = 0;
        m_imp->format.cAccumBits = 0;
        m_imp->format.cAccumRedBits = 0;
        m_imp->format.cAccumGreenBits = 0;
        m_imp->format.cAccumBlueBits = 0;
        m_imp->format.cAccumAlphaBits = 0;
        m_imp->format.cDepthBits = 0;
        m_imp->format.cStencilBits = 8;
        m_imp->format.cAuxBuffers = 0;
        m_imp->format.iLayerType = PFD_MAIN_PLANE;
        m_imp->format.bReserved = 0;
        m_imp->format.dwLayerMask = 0;
        m_imp->format.dwVisibleMask = 0;
        m_imp->format.dwDamageMask = 0;

        int result = ChoosePixelFormat(m_imp->deviceContext, &m_imp->format);
        SetPixelFormat(m_imp->deviceContext, result, &m_imp->format);

        m_imp->glContext = wglCreateContext(m_imp->deviceContext);
        assert(m_imp->glContext != NULL);

        wglMakeCurrent(m_imp->deviceContext, m_imp->glContext);
        assert(wglGetCurrentContext() != NULL);
        glewInit(NULL);
#endif

        for (int i = 0; i < numFBOs; ++i)
        {
            if (glGenFramebuffersEXT != nullptr)
            {
                m_fbos.push_back(new GLFBO(w, h, m_alpha ? GL_RGBA16F_ARB : GL_RGB16F_ARB));
                m_fbos.back()->newColorRenderBuffer();
            }
        }
        if (!m_fbos.empty())
        {
            setDefaultFBOIndex(0);
        }
        else
        {
            m_defaultFBOIndex = -1;
            m_fbo = nullptr;
        }
    }

    FBOVideoDevice::~FBOVideoDevice()
    {
        makeCurrent();

        if (m_imp)
        {
#if defined(PLATFORM_DARWIN)
            CGLDestroyContext(m_imp->ctx);
#endif

#if defined(PLATFORM_LINUX)
            if (m_imp->useEGL)
            {
                eglMakeCurrent(m_imp->eglDisplay, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
                if (m_imp->eglSurface != EGL_NO_SURFACE)
                    eglDestroySurface(m_imp->eglDisplay, m_imp->eglSurface);
                eglDestroyContext(m_imp->eglDisplay, m_imp->eglContext);
                eglTerminate(m_imp->eglDisplay);
            }
            else
            {
                glXMakeCurrent(m_imp->display, None, 0);
                glXDestroyContext(m_imp->display, m_imp->ctx);
                XDestroyWindow(m_imp->display, m_imp->tiny);
                XCloseDisplay(m_imp->display);
            }
#endif
        }

        delete m_imp;
    }

    size_t FBOVideoDevice::width() const { return m_width; }

    size_t FBOVideoDevice::height() const { return m_height; }

    void FBOVideoDevice::redraw() const {}

    void FBOVideoDevice::bind() const
    {
        if (defaultFBO())
        {
            defaultFBO()->bind();
        }
    }

    void FBOVideoDevice::unbind() const
    {
        if (defaultFBO())
        {
            defaultFBO()->unbind();
        }
    }

    GLFBO* FBOVideoDevice::defaultFBO() { return m_fbo; }

    const GLFBO* FBOVideoDevice::defaultFBO() const { return m_fbo; }

    void FBOVideoDevice::makeCurrent() const
    {
#ifdef PLATFORM_DARWIN
        CGLSetCurrentContext(m_imp->ctx);
#endif

#ifdef PLATFORM_WINDOWS
        wglMakeCurrent(m_imp->deviceContext, m_imp->glContext);
#endif

#ifdef PLATFORM_LINUX
        if (m_imp->useEGL)
            eglMakeCurrent(m_imp->eglDisplay, m_imp->eglSurface, m_imp->eglSurface, m_imp->eglContext);
        else
            glXMakeCurrent(m_imp->display, m_imp->tiny, m_imp->ctx);
#endif

        if (defaultFBO())
        {
            bind();
        }

        GLVideoDevice::makeCurrent();
    }

    std::string FBOVideoDevice::hardwareIdentification() const { return "fbo-rb"; }

    //----------------------------------------------------------------------

} // namespace TwkGLF
