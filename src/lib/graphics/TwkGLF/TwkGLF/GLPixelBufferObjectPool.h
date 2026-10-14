///*****************************************************************************/
// Copyright (c) 2019 Autodesk, Inc.
// All rights reserved.
//
// SPDX-License-Identifier: Apache-2.0
//
//*****************************************************************************/

#ifndef __TwkGLF__GLPixelBufferObjectPool__h__
#define __TwkGLF__GLPixelBufferObjectPool__h__

#include <TwkGLF/GLPixelBufferObject.h>

namespace TwkGLF
{

    void InitPBOPools();
    void UninitPBOPools();

    //
    //  Delete the pools' PBOs now, with the GL context that made them (or
    //  one sharing with it) current. Otherwise they are only deleted by the
    //  pools' static destructors at exit, when the GL library may already
    //  have shut down (Mesa crashes then). No PBO from the pools may be in
    //  use.
    //

    void DeletePBOPoolBuffers();

    class GLPixelBufferObjectFromPool
    {
    public:
        GLPixelBufferObjectFromPool(GLPixelBufferObject::PackDir dir, unsigned int num_bytes);
        ~GLPixelBufferObjectFromPool();

        void bind();
        void unbind();

        void* map();
        void* getMappedPtr();
        void unmap();

        unsigned int getSize() const;
        void copyBufferData(void* data, unsigned size);
        GLPixelBufferObject::PackDir getPackDir() const;

    private:
        class PBOWrap* _pPBOWrap;
    };

} // namespace TwkGLF

#endif // __TwkGLF__GLPixelBufferObjectPool__h__
