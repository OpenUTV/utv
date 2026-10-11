//
//  Copyright (c) 2012 Tweak Software.
//  All rights reserved.
//
// Modified in 2026 by Seth Rosenthal for timeline hover preview.
//
//  SPDX-License-Identifier: Apache-2.0
//
//
#include <IPCore/RootIPNode.h>
#include <IPCore/GroupIPNode.h>
#include <IPCore/IPGraph.h>

namespace IPCore
{
    using namespace std;

    RootIPNode::RootIPNode(const string& name, const NodeDefinition* def, IPGraph* graph, GroupIPNode* group)
        : IPNode(name, def, graph, 0)
    {
        setWritable(false);
        setUnconstrainedInputs(true);
    }

    RootIPNode::~RootIPNode() {}

    IPImage* RootIPNode::evaluate(const Context& context)
    {
        const IPNodes& nodes = inputs();
        if (nodes.empty())
            return IPImage::newNoImage(this, "No Input");
        IPImage* root = new IPImage(this, IPImage::GroupType, 0, 0, 1.0, IPImage::NoBuffer);

        //
        //  Images rendered into textures for the UI (the audio waveform,
        //  texture output groups such as the hover preview) go first, so
        //  their textures exist by the time the display groups draw the
        //  UI. The order of the inputs themselves is left alone: the first
        //  input also answers the root's range and size queries.
        //

        vector<IPImage*> others;

        try
        {
            for (size_t i = 0; i < nodes.size(); i++)
            {
                if (IPImage* img = nodes[i]->evaluate(context))
                {
                    if (img->destination == IPImage::OutputTexture)
                        root->appendChild(img);
                    else
                        others.push_back(img);
                }
            }
        }
        catch (exception& exc)
        {
            //
            //  If we have evaluated any children, those FBs will have been
            //  checked out of the cache.  They must be checked back in or they
            //  will not be properly dereferenced and we'll never be able to
            //  delete them.
            //

            TWK_CACHE_LOCK(graph()->cache(), "root exc");
            graph()->cache().checkInAndDelete(root);
            for (size_t i = 0; i < others.size(); i++)
                graph()->cache().checkInAndDelete(others[i]);
            TWK_CACHE_UNLOCK(graph()->cache(), "root exc");
            throw;
        }

        for (size_t i = 0; i < others.size(); i++)
            root->appendChild(others[i]);

        return root;
    }

    IPImageID* RootIPNode::evaluateIdentifier(const Context& context)
    {
        const IPNodes& nodes = inputs();
        if (nodes.empty())
            return 0;

        IPImageID* idnode = new IPImageID;
        IPImageID* next = 0;

        for (int i = 0; i < nodes.size(); i++)
        {
            IPImageID* child = inputs()[i]->evaluateIdentifier(context);
            if (child)
            {
                if (next)
                    next->next = child;
                next = child;
                if (!i)
                    idnode->children = child;
            }
        }

        return idnode;
    }

} // namespace IPCore
