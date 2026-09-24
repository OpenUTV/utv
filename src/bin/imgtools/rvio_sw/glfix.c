//
// Copyright (C) 2023  Autodesk, Inc. All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

#include <stdlib.h>

#ifdef PLATFORM_WINDOWS
#include <windows.h>
#endif

#include <GL/gl.h>
#include <GL/glext.h>

#if defined(__GNUC__) || defined(__clang__)
#define GL_WEAK __attribute__((weak))
#else
#define GL_WEAK
#endif

#ifdef PLATFORM_LINUX

GL_WEAK void glBlitFramebufferEXT(GLint srcX0, GLint srcY0, GLint srcX1, GLint srcY1, GLint dstX0, GLint dstY0, GLint dstX1, GLint dstY1,
                                  GLbitfield mask, GLenum filter)
{
    glBlitFramebuffer(srcX0, srcY0, srcX1, srcY1, dstX0, dstY0, dstX1, dstY1, mask, filter);
}

//
//  On linux, GL_NV_fence gets defined (not sure where), but the
//  corresponding symbols are not provided by MesaGL.  We don't
//  actually need them, so provide the symbols here. -- Alan
//

GL_WEAK void glSetFenceNV(GLuint u, GLenum e) {}

GL_WEAK void glFinishFenceNV(GLuint u) {}

GL_WEAK void glGenFencesNV(GLsizei s, GLuint* ip) {}

GL_WEAK void glDeleteFencesNV(GLsizei s, const GLuint* ip) {}

GL_WEAK GLboolean glTestFenceNV(GLuint u) { return GL_TRUE; }

#endif

#ifdef PLATFORM_DARWIN

//
//  Same as above but for AppleFence
//

GL_WEAK void glSetFenceAPPLE(unsigned int u, unsigned int e) {}

GL_WEAK void glFinishFenceAPPLE(unsigned int u) {}

GL_WEAK void glGenFencesAPPLE(size_t s, unsigned int* ip) {}

GL_WEAK void glDeleteFencesAPPLE(size_t s, const unsigned int* ip) {}

#endif
