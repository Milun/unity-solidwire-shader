// Upgrade NOTE: replaced 'mul(UNITY_MATRIX_MVP,*)' with 'UnityObjectToClipPos(*)'

// Upgrade NOTE: replaced '_Object2World' with 'unity_ObjectToWorld'

// Upgrade NOTE: replaced 'mul(UNITY_MATRIX_MVP,*)' with 'UnityObjectToClipPos(*)'

// Upgrade NOTE: replaced 'mul(UNITY_MATRIX_MVP,*)' with 'UnityObjectToClipPos(*)'

Shader "Custom/SolidWire"
{
    Properties
    {
        _WireStrength("Wire strength", Range(0.1, 5.0)) = 1.5
        _WireThickness("Wire thickness", Range(0.1, 4.0)) = 1.0
        _LooseWireThicknessMulti("Loose wire thickness multi", Range(0.0, 3.0)) = 1.25
        [MaterialToggle] _AdjustThickness("Adjust thickness based on color brightness.", Float) = 0 // Darker colours appear "thinner"; this attempts to balance them by making the lines thicker.
        _Colorize("Colorize", Color) = (0,0,0,1)
        //_WireCornerSize("Wire corner size", RANGE(0, 1000)) = 800
        //_WireCornerStrength("Wire corner strength", RANGE(0.0, 10.0)) = 1.5
        //_AlbedoColor("Albedo color", Color) = (0,0,0,1)
    }
        SubShader
    {
        //Tags { "RenderType"="Opaque" "IgnoreProjector" = "True" "PreviewType" = "Plane" }
        Tags { "RenderType" = "Transparent" "IgnoreProjector" = "True" /*"PreviewType" = "Plane"*/ }
        Blend SrcAlpha OneMinusSrcAlpha
        LOD 200
        Cull Back
        //ZWrite Off
        //ZTest On

        /**
         * Unity Editor outline pass.
         * This pass exists to add a basic outline to the mesh while in edit mode (so that the basic shape of the mesh is visible).
         * It won't be drawn while the game is running.
         */
        Pass
        {
            Name "EditorWire"

            Cull Front
        //ZWrite Off

        CGPROGRAM
        #include "UnityCG.cginc"
        #pragma vertex vert
        #pragma fragment frag
        #pragma geometry geom
        //#pragma surface surf Lambert alpha

        static const float PREVIEW_THICKNESS = 1.5;

        struct appdata
        {
            float4 vertex : POSITION;
            float2 uv : TEXCOORD0;
            float4 color : COLOR0;
        };

        struct v2g
        {
            float4 pos : POSITION;
            float4 color : COLOR0;
            int isPreview : COLOR1;
        };

        struct g2f
        {
            float4 pos : SV_POSITION;
            float4 color : COLOR0;
        };

        int triIdxCount;

        v2g vert(appdata v)
        {
            v2g o;

            // Get the normal clip pos.
            o.pos = UnityObjectToClipPos(v.vertex);
            o.color = v.color;

            // Not in editor mode; continue.
            if (triIdxCount != 0) {
                o.isPreview = 0;
                return o;
            }

            // (Doubt this is the best way to determine this).
            // The Unity assets preview is set to draw this material as a plane.
            // Determine whether the shader is currently rendering that plane by checking if its vertices are at abs(0.5).
            // NOTE: If there's a mesh with exactly these coordinates in the Scene view, it will also be affected by this in the editor.
            //       (It will be rendered correctly when the game runs).
            o.isPreview = (abs(v.vertex.x) == 0.5 && abs(v.vertex.y) == 0.5) ? 1 : 0;

            return o;
        }

        // For whatever reason, triangleadj works, while triangle doesn't.
        float _WireThickness;
        [maxvertexcount(6)]
        void geom(triangleadj v2g IN[6], inout TriangleStream<g2f> triangleStream)
        {
            g2f o = (g2f)0;

            if (triIdxCount != 0) return; // Don't draw unless in edit mode.

            // Check if this geom is being rendered inside of the Asset preview.
            if (IN[0].isPreview != 1 || IN[1].isPreview != 1 || IN[2].isPreview != 1) {

                // This is a tri drawn inside the Scene view.
                o.pos = IN[0].pos;
                o.color = IN[0].color;
                triangleStream.Append(o);

                o.pos = IN[1].pos;
                o.color = IN[0].color;
                triangleStream.Append(o);

                o.pos = IN[2].pos;
                o.color = IN[0].color;
                triangleStream.Append(o);
            }
            else {
                // This is a tri drawn inside the Asset preview. Render it differently.
                o.pos = IN[0].pos;
                o.color = IN[0].color;
                o.pos.x *= -PREVIEW_THICKNESS * _WireThickness;
                o.pos.y *= PREVIEW_THICKNESS * _WireThickness;
                o.pos.w *= 1.01;
                triangleStream.Append(o);

                o.pos = IN[1].pos * 2.1;
                o.color = IN[0].color;
                o.pos.x *= -PREVIEW_THICKNESS * _WireThickness;
                o.pos.y *= PREVIEW_THICKNESS * _WireThickness;
                o.pos.w *= 1.01;
                triangleStream.Append(o);

                o.pos = IN[2].pos * 2.1;
                o.color = IN[0].color;
                o.pos.x *= -PREVIEW_THICKNESS * _WireThickness;
                o.pos.y *= PREVIEW_THICKNESS * _WireThickness;
                o.pos.w *= 1.01;
                triangleStream.Append(o);
            }
        }

        float _WireStrength;
        fixed4 frag(g2f IN) : SV_Target
        {
            return IN.color * _WireStrength;
        }
        ENDCG
    }

        /**
         * Body pass
         * This pass draws the mesh in pure black with its vertices slighty contracted.
         * The body is used to obscure edges that would be hidden behind the mesh normally.
         */
        Pass
        {
            Name "Body"

            Cull Back

            CGPROGRAM
            #include "UnityCG.cginc"
            #pragma vertex vert
            #pragma fragment frag alpha
            #pragma geometry geom
            #pragma target 5.0 // RWStructuredBuffer needs this.

            struct appdata
            {
                float4 vertex : POSITION;
                float4 normal : NORMAL;
                float2 uv : TEXCOORD0;
                float4 color: COLOR0;
                uint vertexId : SV_VertexID;
            };

            struct v2g
            {
                float4 pos : POSITION;
                float4 normal : NORMAL;
                float4 color: COLOR1;
                int2 idxType : COLOR0; // x = vert mesh index (ignored bu .shader. Used by .cs) | y = vert edge type (used by shader): -1 | 0 | 1 | 2
            };

            struct g2f
            {
                float4 pos : SV_POSITION;
            };


            v2g vert(appdata v)
            {
                v2g o;

                /**
                * Reduce the size of the solid body along its normals so that it doesn't cause z-fighting with the Wire pass,
                * but still obscures any lines which would normally be obscured by geometry closer to the camera.
                */

                //Convert the vert to world space.
                /*float4 vert = mul(unity_ObjectToWorld, v.vertex);
                // Subtract the object's world position from it (keep it centered around 0,0, to keep the perspective the same).
                vert.z *= 0.1;
                // Convert vert back to local space
                vert = mul(unity_WorldToObject, vert);
                o.pos = UnityObjectToClipPos(vert);*/

                o.pos = UnityObjectToClipPos(v.vertex);

                o.pos.xy *= o.pos.w;
                o.pos.xy /= 20;

                // Get the normal clip pos.
                //o.pos = UnityObjectToClipPos(v.vertex);
                o.normal = normalize(v.normal);
                o.color = v.color;

                float4 posExt = UnityObjectToClipPos(v.vertex.xyz - normalize(v.normal));
                float4 diff = o.pos - posExt;
                o.normal = -normalize(diff);

                o.idxType = (int2)v.uv;

                return o;
            }

            float _WireThickness;
            int triIdxCount;

            float4 GetOffsetThickness() {

                float wireThickness = (_WireThickness) / _ScreenParams.x;
                wireThickness *= triIdxCount == 0 ? 2 : 1.25; // If in editor, contract slightly more (to make the lines more visible).
                //float ratio = _ScreenParams.x / _ScreenParams.y;

                return wireThickness;
            }

            // For whatever reason, triangleadj works, while triangle doesn't.
            [maxvertexcount(6)]
            void geom(triangleadj v2g IN[6], inout TriangleStream<g2f> triangleStream)
            {
                /**
                * Check if a vert in this tri marks it as a "placeholder" tri.
                * "Placeholder" tris are added by the Blender script in order to allow loose edges in meshes to be easily imported by Unity.
                * (By default, Unity removes the loose parts of a mesh).
                */

                if (IN[0].idxType.y < 0) return;
                if (IN[1].idxType.y < 0) return;
                if (IN[2].idxType.y < 0) return;

                g2f o = (g2f)0;

                float wireThickness = GetOffsetThickness();

                float4 off0 = IN[0].normal * wireThickness * IN[0].pos.w;
                float4 off1 = IN[1].normal * wireThickness * IN[1].pos.w;
                float4 off2 = IN[2].normal * wireThickness * IN[2].pos.w;
                /*off0.y *= ratio;
                off1.y *= ratio;
                off2.y *= ratio;*/

                // This is a real tri. Render it.
                o.pos = IN[0].pos + off0;
                triangleStream.Append(o);

                o.pos = IN[1].pos + off1;
                triangleStream.Append(o);

                o.pos = IN[2].pos + off2;
                triangleStream.Append(o);
            }

            fixed4 frag(g2f IN) : SV_Target
            {
                return fixed4(0,0,0,1);
            }
            ENDCG
        }

            /**
             * Wire pass
             * Draws the wire edges of the mesh. See readme / Github repo for more information.
             */
            Pass
            {
                Name "Wire"
                Cull Off
                Blend OneMinusDstColor One  // Disable this to make the lines solid. Enable to make them overlap (more accurate to vector consoles).
                ZWrite On

                CGPROGRAM
                #include "UnityCG.cginc"
                #pragma vertex vert
                #pragma fragment frag
                #pragma geometry geom
                #pragma target 5.0 // RWStructuredBuffer needs this.

                struct appdata
                {
                    float4 vertex : POSITION;
                    float2 uv : TEXCOORD0;
                    float4 color: COLOR0;
                    uint vertexId : SV_VertexID;
                };

                struct v2g
                {
                    float4 pos : SV_POSITION;
                    float4 color : COLOR0;
                    int2 idxType : COLOR1; // x = vert mesh index (ignored bu .shader. Used by .cs) | y = vert edge type (used by shader): -1 | 0 | 1 | 2
                };

                struct g2f
                {
                    float4 pos : SV_POSITION;
                    float4 color: COLOR0;
                    float3 dist : TEXCOORD0; // Used to calculate corner highlights.
                };

                /// Vert
                /// ====

                // Store the calculated clip pos of all vertices in an array for later use.
                uniform RWStructuredBuffer<float4> vertsPosRWBuffer : register(u1);

                v2g vert(appdata v)
                {
                    v2g o;

                    // Consistent perspective
                    // --------------------------
                    // Get the whole object's world position.
                    float4 wPos = mul(unity_ObjectToWorld, float4(0, 0, 0, -1));
                    //Convert the vert to world space.
                    float4 vert = mul(unity_ObjectToWorld, v.vertex);
                    // Subtract the object's world position from it (keep it centered around 0,0, to keep the perspective the same).
                    //vert.xy += wPos.xy;
                    vert.z += wPos.z;
                    //vert.z *= 0.1;
                    vert.z -= wPos.z;
                    // Convert vert back to local space
                    vert = mul(unity_WorldToObject, vert);
                    o.pos = UnityObjectToClipPos(vert);

                    //o.pos.xy *= o.pos.w;
                    //o.pos.xy /= 20;

                    //o.pos = UnityObjectToClipPos(v.vertex);
                    //o.pos /= abs(o.pos.w);

                    //o.pos += wPos;

                    // --------------------------


                    o.idxType.x = (int)v.vertexId; // Store the REAL index of the vert (the index set by the Blender export script is used by .cs only).
                    o.idxType.y = (int)v.uv.y;

                    o.color = v.color;
                    //o.screenPos = ComputeScreenPos(o.pos);

                    // Store the Screen position of the vert in the buffer.
                    // THIS FIXED THE STUPID BLINKING EDGE PROBLEM?
                    vertsPosRWBuffer[v.vertexId] = o.pos;

                    // TBA: Set the color palette index value here somehow.

                    // Store the Screen position of the vert in the buffer.
                    //vertsPosRWBuffer[v.vertexId] = o.pos;

                    return o;
                }

                /// Geom
                /// ====

                // Stores each tri's 3 vert indexes (mesh.triangles) as uint3s.
                StructuredBuffer<uint3> triIdxBuffer;
                // triIdxBuffer.Length;
                int triIdxCount;

                // Stores each tri's 3 adjacent tri indexes (or -1 if there's no adjacent tri on an edge).
                StructuredBuffer<int3> triAdjBuffer;

                // Get the index of a tri that has the following vert indexes.
                uint getTriIdx(uint v1idx, uint v2idx, uint v3idx) {

                    for (int i = 0; i < triIdxCount; i++)
                    {
                        uint3 t = triIdxBuffer[i];
                        if (v1idx != t.x && v1idx != t.y && v1idx != t.z) continue;
                        if (v2idx != t.x && v2idx != t.y && v2idx != t.z) continue;
                        if (v3idx != t.x && v3idx != t.y && v3idx != t.z) continue;
                        return i;
                    }

                    return -1;
                }

                float _WireThickness;
                float _AdjustThickness;
                float _LooseWireThicknessMulti;
                float4 _Colorize;
                void appendEdge(float4 p1, float4 p2, float4 _color, float edgeLength, bool isLoose, inout TriangleStream<g2f> OUT)
                {
                    // TODO: STOP THE ERROR BEING THROWN WHEN THERE'S NO MATERIALS.

                    float4 color = _color;
                    if (_Colorize.r != 0 || _Colorize.g != 0 || _Colorize.b != 0) color = _Colorize;

                    float wireThickness = _WireThickness;

                    // Experimental: increase wire width slightly based on luminance.
                    if (_AdjustThickness && triIdxCount != 0) {
                        float luminance = 0.299 * color.r + 0.587 * color.g + 0.114 * color.b;
                        float l = 1 - luminance;
                        wireThickness += l * l * 3;
                    }

                    // If the edge is loose, make it slightly thicker (stylistic choice).
                    wireThickness = (wireThickness * (isLoose ? _LooseWireThicknessMulti : 1.0)) / _ScreenParams.x;

                    // Have the wireThickness be the same amount of pixels REGARDLESS of the viewport size.
                    // Note: this will make the wires thicker on smaller resolutions.
                    //wireThickness *= _ScreenParams.x / 10.0;

                    g2f o = (g2f)0;

                    // Ensure that the line thickness is even regardless of screen size and rotation.
                    float ratio = _ScreenParams.x / _ScreenParams.y;
                    //ratio = 1;

                    float2 _t = normalize((p2.xy * p1.w) - (p1.xy * p2.w)); // Important to swap the .w multiplication.
                    float2 t = float2(_t.y, -_t.x); // Line tangent
                    float4 n = normalize(p2 - p1);  // Line normal

                    // NEXT THING TO TAKE CARE OF: Shared colours (look at the rooster's neck).
                    // A good intensity for default is probably like 0.8 - 0.9.
                    // Also, maybe the line intensity can be done if I do something like multiply the rgb of the colour by intensity to make it brighter, but have all colours be 0.5 (so they'll overlap each other and increase intensity?).


                    // P1
                    // ----------------------------------------
                    float4 c1 = p1; // Corner1
                    float4 c2 = p1; // Corner2
                    float2 off1 = (-t) * p1.w * wireThickness;
                    float2 off2 = (t)*p1.w * wireThickness;
                    off1.y *= ratio;
                    off2.y *= ratio;
                    c1.xy += off1;
                    c2.xy += off2;
                    float4 w1 = n * p1.w * wireThickness;
                    w1.y *= ratio;
                    c1 -= w1;
                    c2 -= w1;

                    // P2
                    // ----------------------------------------
                    float4 c3 = p2; // Corner3
                    float4 c4 = p2; // Corner4
                    float2 t3 = (-t) * p2.w * wireThickness;
                    float2 t4 = (t)*p2.w * wireThickness;
                    t3.y *= ratio;
                    t4.y *= ratio;
                    c3.xy += t3;
                    c4.xy += t4;
                    float4 w2 = n * p2.w * wireThickness;
                    w2.y *= ratio;
                    c3 += w2;
                    c4 += w2;


                    // Corner rounding (used by the frag shader).
                    // LOOK UP HOW THE OTHER GUY DID IT
                    // LOOK UP HOW THE OTHER GUY DID IT
                    // LOOK UP HOW THE OTHER GUY DID IT
                    // LOOK UP HOW THE OTHER GUY DID IT
                    // LOOK UP HOW THE OTHER GUY DID IT
                    // LOOK UP HOW THE OTHER GUY DID IT
                    // LOOK UP HOW THE OTHER GUY DID IT IN 2D
                    float3 d0;
                    d0.xy = float2(edgeLength, 0.0) * p1.w; //* cornerSize;
                    d0.z = 1.0 / p1.w;

                    float3 d1;
                    d1.xy = float2(0.0, edgeLength) * p2.w; // *cornerSize;
                    d1.z = 1.0 / p2.w;

                    o.pos = c1;
                    o.color = color;
                            o.dist = d0;
                    OUT.Append(o);

                    o.pos = c2;
                    o.color = color;
                            o.dist = d0;
                    OUT.Append(o);

                    o.pos = c3;
                    o.color = color;
                            o.dist = d1;
                    OUT.Append(o);

                    o.pos = c4;
                    o.color = color;
                            o.dist = d1;
                    OUT.Append(o);

                    OUT.RestartStrip();
                }

                // FIXME: Each tri's culling is checked multiple times at the moment (redundant).
                bool isTriCulled(float2 p0, float2 p1, float2 p2)
                {
                    float a = 0;
                    a += (p1.x - p0.x) * (p1.y + p0.y);
                    a += (p2.x - p1.x) * (p2.y + p1.y);
                    a += (p0.x - p2.x) * (p0.y + p2.y);

                    return a > 0;
                }

                bool isTriCulledByIdx(uint triIdx)
                {
                    uint3 t = triIdxBuffer[triIdx];

                    float2 p0 = vertsPosRWBuffer[t.x].xy / vertsPosRWBuffer[t.x].w;
                    float2 p1 = vertsPosRWBuffer[t.y].xy / vertsPosRWBuffer[t.y].w;
                    float2 p2 = vertsPosRWBuffer[t.z].xy / vertsPosRWBuffer[t.z].w;

                    return isTriCulled(p0, p1, p2);
                }

                bool isEdgeDrawn(int adjTriIdx, uint edgeType) {

                    // If the type value is <= 0, then never draw the edge.
                    if (edgeType <= 0) return false;

                    // If the type value is 2, then always draw the edge.
                    if (edgeType == 2) return true;

                    // If there's no adjacent face (adjTriIdx == -1), or if the adjacent face is showing its backface, then draw the edge.
                    if (adjTriIdx < 0 || isTriCulledByIdx(adjTriIdx)) return true;

                    // Otherwise, don't draw it.
                    return false;
                }

                // For some reason, the following only workds with Unity's unimplemented triangleadj.
                // I tried using triangle instead, and it gave different results.
                fixed4 _WireColor0;
                fixed4 _WireColor1;
                fixed4 _WireColor2;
                [maxvertexcount(12)] // Important to accomodate for the maximum amount of lines being rendered with tristip (which is 4x3).
                void geom(triangleadj v2g IN[6], inout TriangleStream<g2f> OUT)
                {
                    // Used to calculate corner highlights.
                    float2 p0 = IN[0].pos.xy / IN[0].pos.w;
                    float2 p1 = IN[1].pos.xy / IN[1].pos.w;
                    float2 p2 = IN[2].pos.xy / IN[2].pos.w;
                    float edge0Length = length(p1 - p0);
                    float edge1Length = length(p2 - p1);
                    float edge2Length = length(p0 - p2);

                    // TODO: Allow for loose edges to have the NEVER draw type.

                    // Loose edges
                    // ===========
                    if (IN[0].idxType.y < 0) {
                        appendEdge(IN[1].pos, IN[2].pos, IN[0].color, edge1Length, true, OUT);
                        return;
                    }
                    if (IN[1].idxType.y < 0) {
                        appendEdge(IN[2].pos, IN[0].pos, IN[1].color, edge2Length, true, OUT);
                        return;
                    }
                    if (IN[2].idxType.y < 0) {
                        appendEdge(IN[0].pos, IN[1].pos, IN[2].color, edge0Length, true, OUT);
                        return;
                    }

                    /*float test = isTriCulledTest(p0, p1, p2);
                    if (test < 0) color = float4(1,0,0,1);
                    if (test == 0) color = float4(0,1,0,1);
                    if (test > 0) color = float4(0,0,1,1);*/

                    /*bool triCulled = isTriCulled(
                        (IN[1].screenPos.xy / IN[1].screenPos.w) * _ScreenParams.xy,
                        (IN[0].screenPos.xy / IN[0].screenPos.w) * _ScreenParams.xy,
                        (IN[2].screenPos.xy / IN[2].screenPos.w) * _ScreenParams.xy
                    );*/
                    bool triCulled = isTriCulled(p0, p1, p2);
                    // If this tri is culled, skip it.
                    //float test2 = 0.001;
                    //if (edge0Length > test2&& edge1Length > test2&& edge2Length > test2) {
                    if (triCulled) return;
                    //}

                    // Main edges
                    // ==========
                    uint triIdx = getTriIdx(IN[0].idxType.x, IN[1].idxType.x, IN[2].idxType.x); // Index of this tri.
                    //triIdx -= 1;
                    int3 adj = triAdjBuffer[triIdx]; // Indexes of the 3 adjacent tris to this one (or -1 if there's no tri on a specific side).

                    //bool test = false;

                    // edge0
                    if (isEdgeDrawn(adj.x, IN[1].idxType.y)) {
                        appendEdge(IN[0].pos, IN[1].pos, IN[1].color, edge0Length, false, OUT);
                    }

                    if (isEdgeDrawn(adj.y, IN[2].idxType.y)) {
                        appendEdge(IN[1].pos, IN[2].pos, IN[2].color, edge1Length, false, OUT);
                    }

                    if (isEdgeDrawn(adj.z, IN[0].idxType.y)) {
                        appendEdge(IN[2].pos, IN[0].pos, IN[0].color, edge2Length, false, OUT);
                    }
                }

                /// Frag
                /// ====
                float _WireStrength;
                fixed4 frag(g2f IN) : SV_Target
                {
                    //float minDistanceToCorner = min(IN.dist[0], IN.dist[1]) * IN.dist[2];

                    // Normal line color.
                    //if (minDistanceToCorner > 0.9) {
                        half4 color = (half4)IN.color * _WireStrength;
                        //color.a = 0.9;
                        //color.a = 0.5;
                        //color = half4(1,1,1,1);
                        //color.a = 0.2;
                        return color;
                        //}

                        // Corner highlight color.
                        /*half4 cornerColor = (half4)IN.color;
                        cornerColor.xyz += half3(0.2,0.2,0.2); // Corners are slightly lighter.
                        //cornerColor.a = 0.2;

                        return (half4)cornerColor * _WireStrength * _WireCornerStrength;*/
                    }

                    ENDCG
                }
    }
}
