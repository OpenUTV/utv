//
// Copyright (c) 2026 Seth Rosenthal.
// All rights reserved.
//
// SPDX-License-Identifier: Apache-2.0
//
#include <IPCore/HoverPreviewOverlayGL.h>
#include <IPCore/ImageRenderer.h>
#include <IPCore/RenderQuery.h>
#include <TwkGLF/GL.h>
#include <TwkGLF/GLPipeline.h>
#include <TwkGLF/GLState.h>
#include <TwkGLF/BasicGLProgram.h>
#include <TwkGLF/GLRenderPrimitives.h>
#include <TwkGLText/TwkGLText.h>
#include <TwkApp/VideoDevice.h>
#include <TwkMath/Frustum.h>
#include <TwkMath/Math.h>
#include <TwkMath/Vec2.h>
#include <algorithm>
#include <cmath>
#include <vector>

namespace IPCore
{
    using namespace std;
    using namespace TwkMath;
    using namespace TwkGLF;
    using namespace TwkGLText;

    namespace
    {

        //
        //  Panel design. Sizes are in points and are scaled by the device
        //  pixel ratio.
        //

        const float paddingTop = 8.0f; // thicker, so the rounded corners don't look pinched
        const float paddingSide = 4.0f;
        const float paddingBottom = 4.0f;
        const float labelRowHeight = 32.0f;
        const float labelPointSize = 16.0f;
        const float cornerRadius = 6.0f;
        const float arrowWidth = 14.0f;
        const float arrowHeight = 8.0f;
        const float outlineWidth = 1.0f;
        const float shadowRadius = 10.0f;
        const float shadowOffset = 4.0f;

        const float panelAlpha = 0.55f;
        const float shadowAlpha = 0.45f;
        const float foregroundGrey = 0.75f; // the timeline's foreground colour

        const int cornerSegments = 8;
        const int shadowLayers = 8;

        typedef vector<Vec2f> Path;

        //
        //  The panel outline, counterclockwise: a rounded rectangle with the
        //  arrow joined to its bottom edge, tip at (arrowX, tipY). The bottom
        //  edge stops at the arrow, so an outline drawn along this path has
        //  no line across the arrow's base.
        //

        Path panelPath(float x0, float y0, float x1, float y1, float radius, float arrowX, float arrowHalfWidth, float tipY)
        {
            Path path;
            const float quarter = Math<float>::pi() * 0.5f;

            const Vec2f centers[4] = {Vec2f(x1 - radius, y0 + radius), Vec2f(x1 - radius, y1 - radius), Vec2f(x0 + radius, y1 - radius),
                                      Vec2f(x0 + radius, y0 + radius)};

            path.push_back(Vec2f(arrowX + arrowHalfWidth, y0));

            for (int c = 0; c < 4; c++)
            {
                const float start = -quarter + c * quarter;

                for (int i = 0; i <= cornerSegments; i++)
                {
                    const float a = start + quarter * i / cornerSegments;
                    path.push_back(centers[c] + Vec2f(cos(a), sin(a)) * radius);
                }
            }

            path.push_back(Vec2f(arrowX - arrowHalfWidth, y0));
            path.push_back(Vec2f(arrowX, tipY));

            //
            //  The arrow's base can meet a corner when the arrow is pushed
            //  to the side. Drop repeated points, which would make
            //  zero-length edges.
            //

            Path unique;

            for (size_t i = 0; i < path.size(); i++)
            {
                const Vec2f& next = path[(i + 1) % path.size()];
                if (fabs(path[i].x - next.x) > 0.01f || fabs(path[i].y - next.y) > 0.01f)
                    unique.push_back(path[i]);
            }

            return unique;
        }

        //
        //  Moves each point of a closed counterclockwise path outwards
        //  (inwards if distance is negative) along the mitred normal of its
        //  two edges.
        //

        Path offsetPath(const Path& path, float distance)
        {
            const size_t n = path.size();
            Path result(n);

            for (size_t i = 0; i < n; i++)
            {
                const Vec2f& p = path[i];
                Vec2f d0 = p - path[(i + n - 1) % n];
                Vec2f d1 = path[(i + 1) % n] - p;
                d0.normalize();
                d1.normalize();

                const Vec2f n0(d0.y, -d0.x);
                const Vec2f n1(d1.y, -d1.x);
                Vec2f m = n0 + n1;
                m.normalize();

                const float c = std::max(dot(m, n0), 0.25f); // limits the mitre at sharp corners
                result[i] = p + m * (distance / c);
            }

            return result;
        }

        void setupPipeline(GLPipeline* glPipeline, const Mat44f& projection, int width, int height)
        {
            glPipeline->setProjection(projection);
            glPipeline->setModelview(Mat44f());
            glPipeline->setViewport(0, 0, width, height);
        }

        void setColor(GLPipeline* glPipeline, float grey, float alpha)
        {
            GLfloat color[] = {grey, grey, grey, alpha};
            glPipeline->setUniformFloat("uniformColor", 4, color);
        }

        void drawVertices(GLState* glState, vector<float>& data, GLenum mode)
        {
            PrimitiveData buffer(&data.front(), NULL, mode, data.size() / 2, 1, data.size() * sizeof(float));
            vector<VertexAttribute> attributeInfo;
            attributeInfo.push_back(VertexAttribute(string("in_Position"), GL_FLOAT, 2, 0, 0));
            RenderPrimitives renderprimitives(glState->activeGLProgram(), buffer, attributeInfo, glState->vboList());
            renderprimitives.setupAndRender();
        }

        //
        //  Fills a path that is star shaped around center.
        //

        void fillPath(GLState* glState, const Vec2f& center, const Path& path)
        {
            vector<float> data;
            data.reserve(2 * (path.size() + 2));
            data.push_back(center.x);
            data.push_back(center.y);

            for (size_t i = 0; i <= path.size(); i++)
            {
                const Vec2f& p = path[i % path.size()];
                data.push_back(p.x);
                data.push_back(p.y);
            }

            drawVertices(glState, data, GL_TRIANGLE_FAN);
        }

        //
        //  Draws the outline of a closed path as a strip of triangles, so
        //  its width is exact whatever line widths the GL supports.
        //

        void strokePath(GLState* glState, const Path& path, float width)
        {
            const Path outer = offsetPath(path, width * 0.5f);
            const Path inner = offsetPath(path, -width * 0.5f);

            vector<float> data;
            data.reserve(4 * (path.size() + 1));

            for (size_t i = 0; i <= path.size(); i++)
            {
                const size_t j = i % path.size();
                data.push_back(outer[j].x);
                data.push_back(outer[j].y);
                data.push_back(inner[j].x);
                data.push_back(inner[j].y);
            }

            drawVertices(glState, data, GL_TRIANGLE_STRIP);
        }

        void fillRectangle(GLState* glState, float x0, float y0, float x1, float y1)
        {
            vector<float> data = {x0, y0, x1, y0, x1, y1, x0, y1};
            drawVertices(glState, data, GL_QUADS);
        }

        void drawTexturedRectangle(GLState* glState, float x0, float y0, float x1, float y1)
        {
            float data[] = {0, 0, x0, y0, 1, 0, x1, y0, 1, 1, x1, y1, 0, 1, x0, y1};
            PrimitiveData buffer(data, NULL, GL_QUADS, 4, 1, sizeof(data));
            vector<VertexAttribute> attributeInfo;
            attributeInfo.push_back(VertexAttribute(string("in_Position"), GL_FLOAT, 2, 2 * sizeof(float), 4 * sizeof(float)));
            attributeInfo.push_back(VertexAttribute(string("in_TexCoord0"), GL_FLOAT, 2, 0, 4 * sizeof(float)));
            RenderPrimitives renderprimitives(glState->activeGLProgram(), buffer, attributeInfo, glState->vboList());
            renderprimitives.setupAndRender();
        }

        float textWidth(const string& text)
        {
            const Box2f bounds = GLtext::bounds(text);
            return bounds.max.x - bounds.min.x;
        }

        //
        //  Shortens text that is too wide by replacing its middle with
        //  "...", keeping the start and the end, which identify a source.
        //  The text is UTF-8 and TwkGLText assumes valid UTF-8, so it is
        //  only cut between characters, never inside one.
        //

        string fitText(const string& text, float maxWidth)
        {
            if (textWidth(text) <= maxWidth)
                return text;

            vector<size_t> starts; // byte offset of each character

            for (size_t i = 0; i < text.size(); i++)
            {
                if ((static_cast<unsigned char>(text[i]) & 0xC0) != 0x80)
                    starts.push_back(i);
            }

            starts.push_back(text.size());
            const size_t count = starts.size() - 1;

            if (count < 2)
                return "...";

            for (size_t keep = count - 1; keep > 0; keep--)
            {
                const string shortened = text.substr(0, starts[(keep + 1) / 2]) + "..." + text.substr(starts[count - keep / 2]);

                if (textWidth(shortened) <= maxWidth)
                    return shortened;
            }

            return "...";
        }

    } // namespace

    HoverPreviewOverlayGL::HoverPreviewOverlayGL()
        : m_tipX(0)
        , m_tipY(0)
        , m_imageWidth(0)
        , m_imageHeight(0)
        , m_opacity(0)
    {
    }

    void HoverPreviewOverlayGL::setPosition(float tipX, float tipY)
    {
        m_tipX = tipX;
        m_tipY = tipY;
    }

    void HoverPreviewOverlayGL::setImageSize(float width, float height)
    {
        m_imageWidth = width;
        m_imageHeight = height;
    }

    void HoverPreviewOverlayGL::setOpacity(float opacity) { m_opacity = std::min(std::max(opacity, 0.0f), 1.0f); }

    void HoverPreviewOverlayGL::render(const ImageRenderer* renderer, const TwkApp::VideoDevice* device) const
    {
        if (m_opacity <= 0.0f || m_imageWidth <= 0.0f || m_imageHeight <= 0.0f)
            return;

        if (!device)
            return;

        //
        //  The renderer drew the preview into a texture earlier in this
        //  render (the root renders texture outputs before the display
        //  groups, see RootIPNode::evaluate()). There is none until the
        //  cache threads have evaluated the frame.
        //

        RenderQuery::TaggedTextureImagesMap textures;
        RenderQuery(renderer).taggedTextureImages(textures);

        RenderQuery::TaggedTextureImagesMap::const_iterator texture = textures.find("hoverPreview");
        if (texture == textures.end())
            return;

        //
        //  Layout, from the arrow tip up: arrow, bottom padding, label row,
        //  image, top padding. The panel stays inside the framebuffer; the
        //  arrow keeps pointing at the tip, but stays clear of the corners.
        //

        const int width = int(device->internalWidth());
        const int height = int(device->internalHeight());
        const float scale = device->devicePixelRatio();

        const float radius = cornerRadius * scale;
        const float arrowHalfWidth = arrowWidth * scale * 0.5f;
        const float labelHeight = labelRowHeight * scale;
        const float panelWidth = m_imageWidth + 2.0f * paddingSide * scale;
        const float panelHeight = paddingBottom * scale + labelHeight + m_imageHeight + paddingTop * scale;

        const float panelX0 = std::max(0.0f, std::min(m_tipX - panelWidth * 0.5f, width - panelWidth));
        const float panelY0 = m_tipY + arrowHeight * scale;
        const float panelX1 = panelX0 + panelWidth;
        const float panelY1 = panelY0 + panelHeight;
        const float arrowX = std::max(panelX0 + radius + arrowHalfWidth, std::min(m_tipX, panelX1 - radius - arrowHalfWidth));

        const float imageX0 = panelX0 + paddingSide * scale;
        const float imageY0 = panelY0 + paddingBottom * scale + labelHeight;
        const float imageX1 = imageX0 + m_imageWidth;
        const float imageY1 = imageY0 + m_imageHeight;

        const Path path = panelPath(panelX0, panelY0, panelX1, panelY1, radius, arrowX, arrowHalfWidth, m_tipY);
        const Vec2f center(arrowX, (panelY0 + panelY1) * 0.5f);

        Frustumf frustum;
        frustum.window(0, width, 0, height, -1, 1, true);
        const Mat44f projection = frustum.matrix();

        GLState* glState = renderer->getGLState();
        GLPipeline* glPipeline = glState->useGLProgram(defaultGLProgram());
        setupPipeline(glPipeline, projection, width, height);

        glEnable(GL_BLEND);
        glBlendFuncSeparate(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA, GL_ONE, GL_ONE_MINUS_SRC_ALPHA);

        //
        //  Soft shadow: layers of the outline grown by up to the shadow
        //  radius. Where all the layers overlap they add up to the shadow
        //  alpha, and the shadow fades out towards its edge.
        //

        const float layerAlpha = 1.0f - pow(1.0f - shadowAlpha * m_opacity, 1.0f / shadowLayers);
        Path shadow = path;

        for (size_t i = 0; i < shadow.size(); i++)
            shadow[i].y -= shadowOffset * scale;

        setColor(glPipeline, 0.0f, layerAlpha);

        for (int i = 1; i <= shadowLayers; i++)
        {
            fillPath(glState, center - Vec2f(0, shadowOffset * scale), offsetPath(shadow, shadowRadius * scale * i / shadowLayers));
        }

        //
        //  Translucent panel, and an opaque black matte behind the image so
        //  letterboxing shows, as it does in the viewer.
        //

        setColor(glPipeline, 0.0f, panelAlpha * m_opacity);
        fillPath(glState, center, path);

        setColor(glPipeline, 0.0f, m_opacity);
        fillRectangle(glState, imageX0, imageY0, imageX1, imageY1);

        //
        //  Image. The texture's own alpha is not meaningful here, so it is
        //  blended with a constant alpha, which also applies the fade.
        //

        glPipeline = glState->useGLProgram(textureGLProgram());
        setupPipeline(glPipeline, projection, width, height);
        GLint textureUnit = 0;
        glPipeline->setUniformInt("texture0", 1, &textureUnit);
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, texture->second.textureID);
        glBlendColor(0.0f, 0.0f, 0.0f, m_opacity);
        glBlendFunc(GL_CONSTANT_ALPHA, GL_ONE_MINUS_CONSTANT_ALPHA);
        drawTexturedRectangle(glState, imageX0, imageY0, imageX1, imageY1);
        glBindTexture(GL_TEXTURE_2D, 0);
        glBlendFuncSeparate(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA, GL_ONE, GL_ONE_MINUS_SRC_ALPHA);

        //
        //  Outline of the panel and the arrow
        //

        glPipeline = glState->useGLProgram(defaultGLProgram());
        setupPipeline(glPipeline, projection, width, height);
        setColor(glPipeline, foregroundGrey, m_opacity);
        strokePath(glState, path, outlineWidth * scale);

        //
        //  Label, centred in its row. TwkGLText draws with the fixed
        //  function pipeline, so load the same matrices into it (as
        //  PaintCommand does for text), and restore them afterwards. The
        //  text size is shared with the UI's text drawing, so restore it.
        //

        if (!m_label.empty())
        {
            glMatrixMode(GL_PROJECTION);
            glPushMatrix();
            glMatrixMode(GL_MODELVIEW);
            glPushMatrix();

            glPipeline->useCurrentProjectionGL2();
            glPipeline->useCurrentModelviewGL2();

            {
                GLState::FixedFunctionPipeline FFP(glState);
                FFP.setViewport(0, 0, width, height);
                glEnable(GL_TEXTURE_2D);

                const int previousSize = GLtext::size();
                GLtext::size(int(labelPointSize * scale + 0.5f));

                const string label = fitText(m_label, m_imageWidth);
                const float ascender = GLtext::globalAscenderHeight();
                const float descender = GLtext::globalDescenderHeight(); // negative
                const float rowY0 = panelY0 + paddingBottom * scale;
                const float x = imageX0 + (m_imageWidth - textWidth(label)) * 0.5f;
                const float y = rowY0 + (labelHeight - (ascender - descender)) * 0.5f - descender;

                GLtext::color(foregroundGrey, foregroundGrey, foregroundGrey, m_opacity);
                GLtext::writeAt(x, y, label);
                GLtext::size(previousSize);

                glDisable(GL_TEXTURE_2D);
            }

            glMatrixMode(GL_PROJECTION);
            glPopMatrix();
            glMatrixMode(GL_MODELVIEW);
            glPopMatrix();
        }

        glDisable(GL_BLEND);
        glState->useGLProgram(defaultGLProgram());
    }

} // namespace IPCore
