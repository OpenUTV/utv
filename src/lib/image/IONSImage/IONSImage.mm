//******************************************************************************
// Copyright (c) 2001-2004 Tweak Inc. All rights reserved.
// 
// SPDX-License-Identifier: Apache-2.0
// 
//******************************************************************************
#include <IONSImage/IONSImage.h>
#include <iostream>
#include <string>
#include <stl_ext/string_algo.h>
#include <TwkMath/Mat44.h>
#include <TwkMath/Iostream.h>
#include <TwkFB/Operations.h>
#include <TwkFB/Exception.h>
#include <objc/objc-class.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSBitmapImageRep.h>
#import <ImageIO/ImageIO.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/NSString.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSData.h>
#import <Foundation/NSEnumerator.h>
#import <Foundation/NSDictionary.h>

namespace TwkFB {
using namespace std;
using namespace TwkMath;

static bool manageMemory = false;

struct FormatDescription
{
    const char* ext;
    const char* desc;
};

static FormatDescription formats[] =
{ 
    {"bmp", "Windows Bitmap"},
    {"pict", "Apple PICT Image"},
    {"pic",  "Pixar Image"},
    {"eps",  "Encapsulated Postscript"},
    {"epi",  "Encapsulated Postscript Interchange"},
    {"epsi",  "Encapsulated Postscript Interchange"},
    {"epsf",  "Encapsulated Postscript"},
    {"ps",  "Postscript"},
    {"fax",  "FAX Dump"},
    {"ico",  "Icon"},
    {"cur",  "Windows Cursor"},
    {"gif",  "Graphics Interchange Format"},
    {"fpx",  "FlashPix"},
    {"fpix",  "FlashPix"},
    {"pnt",  "MacPaint"},
    {"pntg",  "MacPaint"},
    {"mac",  "MacPaint"},
    {"psd",  "PhotoShop"},
    {"targa",  "TARGA"},
    {"tga",  "TARGA"},
    {"qtif",  "Quicktime Image"},
    {"qti",  "Quicktime Image"},
    {"mrw",  "Minolta Photo Raw"},
    {"icns",  "OS X Icons"},
    {"orf",  "Olympus Photo Raw"},
    {"raf",  "Fuji Photo Raw"},
    {"crw",  "Canon Photo Raw"},
    {"nef",  "Nikon Electronic Format"},
    {"srf",  "SONY Photo Raw"},
    {"dng",  "Adobe Digital Negative"},
    {"cr2",  "Canon Photo Raw"},
    {"hdr",  "Radiance Map File"},
    {"xbm",  "X-Windows Bitmap"},
    {"dcr",  "Kodak Photo Raw"},
    {"pct",  "Apple PICT Image"},
{0, 0}
};

void IONSImage::useLocalMemoryPool()
{
    manageMemory = true;
}

IONSImage::IONSImage() : FrameBufferIO("NSImage", "o") // after OIIO (n)
{
    NSAutoreleasePool *pool = manageMemory ? [[NSAutoreleasePool alloc] init] : nil;
    unsigned int cap = ImageRead;

    NSArray* array = [NSImage imageUnfilteredFileTypes];
    StringPairVector codecs;
    
    for (int i=0; i < [array count]; i++)
    {
        string s = [[array objectAtIndex: i] UTF8String];
        if (s[0] >= 'A' && s[0] <= 'Z' || s[0] == '\'') continue;
        if (s == "pdf" || s == "PDF") continue;

        const char* desc = "";
        
        for (FormatDescription* d = formats; d->ext; d++)
        {
            if (s == d->ext) { desc = d->desc; break; }
        }

        addType(s, desc, cap, codecs);
    }

    if (pool) [pool release];
}

IONSImage::~IONSImage() {}

string
IONSImage::about() const
{ 
    return "NSImage";
}

static NSImage*
readNSImage(const char *name, bool getreps=true)
{
    NSString *aFile = [[NSString alloc] initWithUTF8String: name];
    NSImage *image  = [[NSImage alloc] initWithContentsOfFile: aFile];
    [aFile release];
    return image;
}

static void
addDictToFB(NSDictionary* dict, FrameBuffer& fb, const std::string& prefix)
{
    @try
    {
        for (NSString* key in dict)
        {
            id val = [dict objectForKey:key];
            std::string fullKey = prefix.empty() ? [key UTF8String] : (prefix + "/" + [key UTF8String]);
            if ([val isKindOfClass:[NSNumber class]])
            {
                fb.newAttribute(fullKey, std::string([[val stringValue] UTF8String]));
            }
            else if ([val isKindOfClass:[NSString class]])
            {
                fb.newAttribute(fullKey, std::string([val UTF8String]));
            }
            else if ([val isKindOfClass:[NSArray class]])
            {
                NSArray* a = (NSArray*)val;
                std::string s = "";
                for (NSUInteger i = 0; i < [a count]; ++i)
                {
                    if (i > 0) s += ", ";
                    id elem = [a objectAtIndex:i];
                    NSString* sv = [elem respondsToSelector:@selector(stringValue)] ? [elem stringValue] : [elem description];
                    if (sv) s += [sv UTF8String];
                }
                fb.newAttribute(fullKey, s);
            }
        }
    }
    @catch (NSException* ex)
    {
    }
}

static void
populateImageIOAttributes(NSDictionary* props, FrameBuffer& fb, const std::string& filename, size_t w, size_t h, int samples, int bpc)
{
    @try
    {
        if (NSString* profileName = [props objectForKey:(id)kCGImagePropertyProfileName])
        {
            fb.newAttribute("ColorSpaceProfile", std::string([profileName UTF8String]));
            if (!fb.hasAttribute("ColorSpace"))
            {
                fb.newAttribute("ColorSpace", std::string([profileName UTF8String]));
            }
        }
        std::string pixFmt = (samples == 4) ? "RGBA" : (samples == 3 ? "RGB" : (samples == 1 ? "Y" : "Custom"));
        pixFmt += std::to_string(bpc);
        fb.newAttribute("PixelFormat", pixFmt);
        fb.newAttribute("Codec", std::string("Apple ImageIO"));
        fb.newAttribute("File", filename);

        if (NSDictionary* exif = [props objectForKey:(id)kCGImagePropertyExifDictionary])
        {
            addDictToFB(exif, fb, "EXIF");
            addDictToFB(exif, fb, "");
        }
        if (NSDictionary* tiff = [props objectForKey:(id)kCGImagePropertyTIFFDictionary])
        {
            addDictToFB(tiff, fb, "TIFF");
            if (id make = [tiff objectForKey:@"Make"]) fb.newAttribute("Make", std::string([[make description] UTF8String]));
            if (id model = [tiff objectForKey:@"Model"]) fb.newAttribute("Model", std::string([[model description] UTF8String]));
            if (id soft = [tiff objectForKey:@"Software"]) fb.newAttribute("Software", std::string([[soft description] UTF8String]));
        }
        if (NSDictionary* gps = [props objectForKey:(id)kCGImagePropertyGPSDictionary])
        {
            addDictToFB(gps, fb, "GPS");
        }
        if (NSDictionary* apple = [props objectForKey:(id)kCGImagePropertyMakerAppleDictionary])
        {
            addDictToFB(apple, fb, "MakerApple");
        }
    }
    @catch (NSException* ex)
    {
    }
}

void
IONSImage::getImageInfo(const std::string& filename, FBInfo& fbi) const
{
    NSAutoreleasePool *pool = manageMemory ? [[NSAutoreleasePool alloc] init] : nil;

    // Fast path: use CGImageSource directly to read headers in <1ms without decoding pixels
    CFURLRef url = CFURLCreateFromFileSystemRepresentation(kCFAllocatorDefault,
                                                           (const UInt8*)filename.c_str(),
                                                           filename.length(), false);
    if (url)
    {
        CGImageSourceRef src = CGImageSourceCreateWithURL(url, NULL);
        if (src)
        {
            if (CGImageSourceGetCount(src) > 0)
            {
                NSDictionary *options = @{(id)kCGImageSourceShouldCache: @NO};
                NSDictionary *props = (NSDictionary*)CGImageSourceCopyPropertiesAtIndex(src, 0, (CFDictionaryRef)options);
                if (props)
                {
                    size_t pw = [[props objectForKey:(id)kCGImagePropertyPixelWidth] unsignedLongValue];
                    size_t ph = [[props objectForKey:(id)kCGImagePropertyPixelHeight] unsignedLongValue];
                    int orient = [[props objectForKey:(id)kCGImagePropertyOrientation] intValue];
                    if (orient >= 5 && orient <= 8)
                    {
                        fbi.width = ph;
                        fbi.height = pw;
                    }
                    else
                    {
                        fbi.width = pw;
                        fbi.height = ph;
                    }

                    int depth = [[props objectForKey:(id)kCGImagePropertyDepth] intValue];
                    if (depth <= 0) depth = 8;

                    NSString* colorModel = [props objectForKey:(id)kCGImagePropertyColorModel];
                    int samples = 4;
                    if ([colorModel isEqualToString:@"RGB"]) samples = 4;
                    else if ([colorModel isEqualToString:@"Gray"]) samples = 1;
                    else if ([colorModel isEqualToString:@"CMYK"]) samples = 4;
                    fbi.numChannels = samples;

                    populateImageIOAttributes(props, fbi.proxy, filename, fbi.width, fbi.height, samples, depth);

                    switch (depth)
                    {
                        case 1:  fbi.dataType = FrameBuffer::BIT; break;
                        case 8:  fbi.dataType = FrameBuffer::UCHAR; break;
                        case 16: fbi.dataType = FrameBuffer::USHORT; break;
                        case 32: fbi.dataType = FrameBuffer::FLOAT; break;
                        default: fbi.dataType = FrameBuffer::UCHAR; break;
                    }

                    [props release];
                    CFRelease(src);
                    CFRelease(url);
                    if (pool) [pool release];
                    return;
                }
            }
            CFRelease(src);
        }
        CFRelease(url);
    }

    // Fallback path: legacy NSImage
    if (NSImage* image = readNSImage(filename.c_str()))
    {
        NSBitmapImageRep *rep = (NSBitmapImageRep *)[[image representations] objectAtIndex:0];
	NSSize size         = [rep size];
        fbi.numChannels     = [rep samplesPerPixel];
        fbi.width           = [rep pixelsWide];
        fbi.height          = [rep pixelsHigh];

        NSString *colorSpace = [rep colorSpaceName];
        if (colorSpace)
        {
            fbi.proxy.newAttribute("NSImage/colorSpaceName", std::string([colorSpace UTF8String]));
            fbi.proxy.newAttribute("ColorSpace", std::string([colorSpace UTF8String]));
        }
        int gsamples = [rep samplesPerPixel];
        int gbbs = [rep bitsPerSample];
        std::string gPixFmt = (gsamples == 4) ? "RGBA" : (gsamples == 3 ? "RGB" : (gsamples == 1 ? "Y" : "Custom"));
        gPixFmt += std::to_string(gbbs);
        fbi.proxy.newAttribute("PixelFormat", gPixFmt);
        fbi.proxy.newAttribute("Codec", std::string("Apple ImageIO / NSImage"));
        fbi.proxy.newAttribute("File", filename);

        [image autorelease];

        switch ([rep bitsPerSample])
        {
          case 1:
              fbi.dataType = FrameBuffer::BIT;
              break;
          case 8: 
              fbi.dataType = FrameBuffer::UCHAR; 
              break;
          case 16: 
              fbi.dataType = FrameBuffer::USHORT; 
              break;
          case 32: 
              fbi.dataType = FrameBuffer::FLOAT; 
              break;
          default:
              if (pool) [pool release];
              TWK_THROW_STREAM(Exception, "NSImage: Sorry, unsupported bit depth: "
                               << [rep bitsPerSample]);
        }

        if (pool) [pool release];
    }
    else
    {
        if (pool) [pool release];
        TWK_THROW_STREAM(UnsupportedException, "NSImage: not supported");
    }
}


void
IONSImage::readImage(FrameBuffer& fb,
                     const std::string& filename,
                     const ReadRequest& request) const
{
    NSAutoreleasePool *pool = manageMemory ? [[NSAutoreleasePool alloc] init] : nil;

    // Fast path: hardware-accelerated decoding via ImageIO / CGImageSource
    CFURLRef url = CFURLCreateFromFileSystemRepresentation(kCFAllocatorDefault,
                                                           (const UInt8*)filename.c_str(),
                                                           filename.length(), false);
    if (url)
    {
        CGImageSourceRef src = CGImageSourceCreateWithURL(url, NULL);
        if (src)
        {
            if (CGImageSourceGetCount(src) > 0)
            {
                NSDictionary *props = (NSDictionary*)CGImageSourceCopyPropertiesAtIndex(src, 0, NULL);
                size_t pw = props ? [[props objectForKey:(id)kCGImagePropertyPixelWidth] unsignedLongValue] : 0;
                size_t ph = props ? [[props objectForKey:(id)kCGImagePropertyPixelHeight] unsignedLongValue] : 0;
                size_t maxDim = std::max(pw, ph);
                if (maxDim == 0) maxDim = 16384;

                NSDictionary *options = @{
                    (id)kCGImageSourceCreateThumbnailWithTransform: @YES,
                    (id)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
                    (id)kCGImageSourceThumbnailMaxPixelSize: @(maxDim)
                };
                CGImageRef cg = CGImageSourceCreateThumbnailAtIndex(src, 0, (CFDictionaryRef)options);
                if (cg)
                {
                    size_t w = CGImageGetWidth(cg);
                    size_t h = CGImageGetHeight(cg);
                    size_t bpc = CGImageGetBitsPerComponent(cg);
                    size_t bpp = CGImageGetBitsPerPixel(cg);
                    size_t bpr = CGImageGetBytesPerRow(cg);
                    int samples = (bpc > 0) ? (bpp / bpc) : 4;

                    switch (bpc)
                    {
                        case 1:
                        case 8:
                            fb.restructure(w, h, 0, samples, FrameBuffer::UCHAR);
                            break;
                        case 16:
                            fb.restructure(w, h, 0, samples, FrameBuffer::USHORT);
                            break;
                        case 32:
                            fb.restructure(w, h, 0, samples, FrameBuffer::FLOAT);
                            break;
                        default:
                            CGImageRelease(cg);
                            if (props) [props release];
                            CFRelease(src);
                            CFRelease(url);
                            if (pool) [pool release];
                            TWK_THROW_STREAM(UnsupportedException,
                                             "Sorry, unsupported bit depth, trying to read file "
                                             << filename);
                    }

                    CGDataProviderRef dp = CGImageGetDataProvider(cg);
                    CFDataRef data = dp ? CGDataProviderCopyData(dp) : NULL;
                    if (data)
                    {
                        const unsigned char* ptr = CFDataGetBytePtr(data);
                        typedef unsigned char byte;
                        for (size_t row = 0; row < h; row++)
                        {
                            memcpy(fb.scanline<byte>(h - row - 1),
                                   ptr + (row * bpr),
                                   fb.scanlineSize());
                        }
                        CFRelease(data);
                    }

                    CGColorSpaceRef cs = CGImageGetColorSpace(cg);
                    if (cs)
                    {
                        CFStringRef csName = CGColorSpaceCopyName(cs);
                        if (csName)
                        {
                            const char* cstr = CFStringGetCStringPtr(csName, kCFStringEncodingUTF8);
                            if (cstr) fb.newAttribute("ColorSpace", std::string(cstr));
                            CFRelease(csName);
                        }
                    }

                    if (props)
                    {
                        populateImageIOAttributes(props, fb, filename, w, h, samples, bpc);
                        [props release];
                    }

                    CGImageRelease(cg);
                    CFRelease(src);
                    CFRelease(url);
                    if (pool) [pool release];
                    return;
                }
                if (props) [props release];
            }
            CFRelease(src);
        }
        CFRelease(url);
    }

    // Fallback path: legacy NSImage
    if (NSImage* image = readNSImage(filename.c_str()))
    {
        NSBitmapImageRep* rep = nil;
        for (NSImageRep* r in [image representations])
        {
            if ([r isKindOfClass:[NSBitmapImageRep class]])
            {
                NSBitmapImageRep* b = (NSBitmapImageRep*)r;
                if ([b bitmapData] != NULL)
                {
                    rep = b;
                    break;
                }
            }
        }
        if (!rep)
        {
            rep = [NSBitmapImageRep imageRepWithData: [image TIFFRepresentation]];
        }

	NSSize size             = [rep size];
	unsigned char* buffer   = [rep bitmapData];
	int samples             = [rep samplesPerPixel];
        int bbs                 = [rep bitsPerSample];
        int bpp                 = [rep bitsPerPixel];
        size_t rowSize          = [rep bytesPerRow];
        size_t w                = [rep pixelsWide];
        size_t h                = [rep pixelsHigh];
        int componentsPerPixel  = (bbs > 0) ? (bpp / bbs) : samples;

        switch (bbs)
        {
          case 1:
          case 8: 
              fb.restructure(w, h, 0, samples, FrameBuffer::UCHAR ); 
              break;
          case 16: 
              fb.restructure(w, h, 0, samples, FrameBuffer::USHORT ); 
              break;
          case 32: 
              fb.restructure(w, h, 0, samples, FrameBuffer::FLOAT ); 
              break;
          default:
              TWK_THROW_STREAM(UnsupportedException,
                               "Sorry, unsupported bit depth, trying to read file "
                               << filename);
        }

	if ([rep isPlanar])
        {
            TWK_THROW_STREAM(UnsupportedException,
                             "Planar images are not yet supported, reading "
                             << filename);
        }
        else
        {
            typedef unsigned char byte;

            //
            //  Copy the scanlines unpacking pixels if padded (e.g. RGBX -> RGB)
            //

            if (componentsPerPixel > samples && samples == 3 && bbs == 8)
            {
                for (size_t row = 0; row < h; row++)
                {
                    const byte* src = buffer + (row * rowSize);
                    byte* dst = fb.scanline<byte>(h - row - 1);
                    for (size_t col = 0; col < w; ++col)
                    {
                        dst[0] = src[0];
                        dst[1] = src[1];
                        dst[2] = src[2];
                        dst += 3;
                        src += componentsPerPixel;
                    }
                }
            }
            else if (componentsPerPixel > samples && samples == 3 && bbs == 16)
            {
                for (size_t row = 0; row < h; row++)
                {
                    const unsigned short* src = reinterpret_cast<const unsigned short*>(buffer + (row * rowSize));
                    unsigned short* dst = fb.scanline<unsigned short>(h - row - 1);
                    for (size_t col = 0; col < w; ++col)
                    {
                        dst[0] = src[0];
                        dst[1] = src[1];
                        dst[2] = src[2];
                        dst += 3;
                        src += componentsPerPixel;
                    }
                }
            }
            else if (componentsPerPixel > samples && samples == 3 && bbs == 32)
            {
                for (size_t row = 0; row < h; row++)
                {
                    const float* src = reinterpret_cast<const float*>(buffer + (row * rowSize));
                    float* dst = fb.scanline<float>(h - row - 1);
                    for (size_t col = 0; col < w; ++col)
                    {
                        dst[0] = src[0];
                        dst[1] = src[1];
                        dst[2] = src[2];
                        dst += 3;
                        src += componentsPerPixel;
                    }
                }
            }
            else
            {
                for (int row = 0; row < h; row++)
                {
                    memcpy(fb.scanline<byte>(h - row - 1), 
                           buffer + (row * rowSize),
                           fb.scanlineSize());
                }
            }
        }
        
        NSString *colorSpace = [rep colorSpaceName];
        if (colorSpace)
        {
            fb.newAttribute("NSImage/ColorSpaceName", std::string([colorSpace UTF8String]));
            fb.newAttribute("ColorSpace", std::string([colorSpace UTF8String]));
        }
        std::string pixFmt = (samples == 4) ? "RGBA" : (samples == 3 ? "RGB" : (samples == 1 ? "Y" : "Custom"));
        pixFmt += std::to_string(bbs);
        fb.newAttribute("PixelFormat", pixFmt);
        fb.newAttribute("Codec", std::string("Apple ImageIO / NSImage"));
        fb.newAttribute("File", filename);

	NSArray* ireps = [image representations];
	id item = [ireps objectAtIndex: 0];

	if ([item isKindOfClass: [NSBitmapImageRep class]])
        {
#if 1
            @try
            {
                if (NSDictionary* d = [item valueForProperty: NSImageEXIFData])
                {
                    NSEnumerator *e = [d keyEnumerator];
                    NSString* key;
                    
                    while ((key = [e nextObject])) 
                    {
                        id val = [d objectForKey: key];

                        if ([val isKindOfClass: [NSNumber class]])
                        {
                            NSString* sv = [val stringValue];
                            fb.newAttribute(std::string([key UTF8String]),
                                            std::string([sv UTF8String]));
                        }
                        else if ([val isKindOfClass: [NSString class]])
                        {
                            NSString* sv = val;
                            fb.newAttribute(std::string([key UTF8String]),
                                            std::string([sv UTF8String]));
                        }
                        else if ([val isKindOfClass: [NSArray class]])
                        {
                            NSArray* a = val;
                            string v = "";
                            for (NSUInteger ai = 0; ai < [a count]; ++ai)
                            {
                                id elem = [a objectAtIndex: ai];
                                NSString* sv = [elem respondsToSelector: @selector(stringValue)] ? [elem stringValue] : [elem description];
                                if (sv)
                                {
                                    if (ai > 0) v += ", ";
                                    v += [sv UTF8String];
                                }
                            }
                            fb.newAttribute(std::string([key UTF8String]), v);
                        }
                    }
                }
            }
            @catch (NSException* ex)
            {
                // Gracefully ignore any EXIF parsing issues
            }
#endif
        }

        [image autorelease];
    }

    if (pool) [pool release];
}


void
IONSImage::writeImage(const FrameBuffer& img,
                      const std::string& filename,
                      const WriteRequest& request) const
{
    throw UnsupportedException();
}


}  //  End namespace TwkFB
