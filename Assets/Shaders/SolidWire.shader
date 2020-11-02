Shader "Custom/SolidWire"
{
    Properties
    {
        _WireColor ("Wire color", Color) = (1,1,1,1) 
        _WireStrength ("Wire strength", Range(0.1, 5.0)) = 1.5 
        _WireCornerSize("Wire corner size", RANGE(0, 1000)) = 800
        _WireCornerStrength("Wire corner strength", RANGE(0.0, 10.0)) = 1.5
        //_AlbedoColor("Albedo color", Color) = (0,0,0,1)
    }
    SubShader
    {
        //Tags { "RenderType"="Opaque" "IgnoreProjector" = "True" "PreviewType" = "Plane" }
        Tags { "Queue" = "Transparent" "RenderType" = "Transparent" "IgnoreProjector" = "True" "PreviewType" = "Plane" }
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

            static const float PREVIEW_THICKNESS = 1.5;

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2g
            {
                float4 pos : POSITION;
                int isPreview : COLOR0;
            };

            struct g2f
            {
                float4 pos : SV_POSITION;
            };

            int triIdxCount;

            v2g vert (appdata v)
            {
                v2g o;

                // Get the normal clip pos.
                o.pos = UnityObjectToClipPos(v.vertex);

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
            [maxvertexcount(6)]
            void geom(triangleadj v2g IN[6], inout TriangleStream<g2f> triangleStream)
            {
                g2f o = (g2f)0;

                if (triIdxCount != 0) return; // Don't draw unless in edit mode.

                // Check if this geom is being rendered inside of the Asset preview.
                if (IN[0].isPreview != 1 || IN[1].isPreview != 1 || IN[2].isPreview != 1) {
                   
                    // This is a tri drawn inside the Scene view.
                    o.pos = IN[0].pos;
                    triangleStream.Append(o);

                    o.pos = IN[1].pos;
                    triangleStream.Append(o);

                    o.pos = IN[2].pos;
                    triangleStream.Append(o);
                }
                else {
                    // This is a tri drawn inside the Asset preview. Render it differently.
                    o.pos = IN[0].pos;
                    o.pos.x *= -PREVIEW_THICKNESS;
                    o.pos.y *= PREVIEW_THICKNESS;
                    o.pos.w *= 1.01;
                    triangleStream.Append(o);

                    o.pos = IN[1].pos * 2.1;
                    o.pos.x *= -PREVIEW_THICKNESS;
                    o.pos.y *= PREVIEW_THICKNESS;
                    o.pos.w *= 1.01;
                    triangleStream.Append(o);

                    o.pos = IN[2].pos * 2.1;
                    o.pos.x *= -PREVIEW_THICKNESS;
                    o.pos.y *= PREVIEW_THICKNESS;
                    o.pos.w *= 1.01;
                    triangleStream.Append(o);
                }
            }

            fixed4 _WireColor;
            float _WireStrength;
            fixed4 frag(g2f IN) : SV_Target
            {
                return _WireColor * _WireStrength;
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

            CGPROGRAM
            #include "UnityCG.cginc"
            #pragma vertex vert
            #pragma fragment frag alpha
            #pragma geometry geom

            struct appdata
            {
                float4 vertex : POSITION;
                float4 normal : NORMAL;
                float2 uv : TEXCOORD0;
            };

            struct v2g
            {
                float4 pos : POSITION;
                int2 idxType : COLOR0; // x = vert mesh index (ignored bu .shader. Used by .cs) | y = vert edge type (used by shader): -1 | 0 | 1 | 2
            };

            struct g2f
            {
                float4 pos : SV_POSITION;
            };

            int triIdxCount;
            v2g vert (appdata v)
            {
                v2g o;
                
                /**
                * Reduce the size of the solid body along its normals so that it doesn't cause z-fighting with the Wire pass,
                * but still obscures any lines which would normally be obscured by geometry closer to the camera.
                */

                //float multiplier = unity_OrthoParams.x * 0.1;

                // * I needed to ensure that the contraction of the verts was consistant regardless of mesh scale, so I did this.
                // There's probably a better way to do this, but this works for now.

                // Get the normal clip pos.
                o.pos = UnityObjectToClipPos(v.vertex);

                // Get what the clip pos would be if the vert was moved along its normal by 1.
                float4 posExt = UnityObjectToClipPos(v.vertex.xyz - normalize(v.normal));

                // Create a vector between the two pos vectors...
                float4 diff = o.pos - posExt;

                float editorMulti = triIdxCount == 0 ? 4 : 1;

                // ...and then make it consistant regardless of size.
                o.pos -= normalize(diff) * 0.001 * editorMulti * o.pos.w;
                //o.pos -= normalize(diff) * 0.005;

                o.idxType = (int2)v.uv;

                return o;
            }

            // For whatever reason, triangleadj works, while triangle doesn't.
            [maxvertexcount(6)]
            void geom(triangleadj v2g IN[6], inout TriangleStream<g2f> triangleStream)
            {
                g2f o = (g2f)0;

                /**
                * Check if a vert in this tri marks it as a "placeholder" tri.
                * "Placeholder" tris are added by the Blender script in order to allow loose edges in meshes to be easily imported by Unity.
                * (By default, Unity removes the loose parts of a mesh).
                */ 
                if (IN[0].idxType.y < 0) return;
                if (IN[1].idxType.y < 0) return;
                if (IN[2].idxType.y < 0) return;

                //if (IN[0].pos.x > 3) return;

                // This is a real tri. Render it.
                o.pos = IN[0].pos;
                triangleStream.Append(o);

                o.pos = IN[1].pos;
                triangleStream.Append(o);

                o.pos = IN[2].pos;
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
                uint vertexId : SV_VertexID;
            };

            struct v2g
            {
                float4 pos : SV_POSITION;
                int2 idxType : COLOR0; // x = vert mesh index (ignored bu .shader. Used by .cs) | y = vert edge type (used by shader): -1 | 0 | 1 | 2
            };

            struct g2f
            {
                float4 pos : SV_POSITION;
                float3 dist : TEXCOORD0; // Used to calculate corner highlights.
            };

            /// Vert
            /// ====

            // Store the calculated clip pos of all vertices in an array for later use.
            RWStructuredBuffer<float4> vertsPosRWBuffer : register(u1);
            
            v2g vert(appdata v)
            {
                v2g o;

                o.pos = UnityObjectToClipPos(v.vertex);

                o.idxType.x = (int)v.vertexId; // Store the REAL index of the vert (the index set by the Blender export script is used by .cs only).
                o.idxType.y = (int)v.uv.y;

                // TBA: Set the color palette index value here somehow.

                // Store the Screen position of the vert in the buffer.
                vertsPosRWBuffer[v.vertexId] = o.pos;

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

            float _WireCornerSize;

            void appendEdge(float4 p1, float4 p2, float edgeLength, float cornerSize, inout LineStream<g2f> OUT)
            {
                g2f o = (g2f)0;

                o.pos = p1;
                o.dist.xy = float2(edgeLength, 0.0) * o.pos.w * cornerSize;
                o.dist.z = 1.0 / o.pos.w;
                OUT.Append(o);

                o.pos = p2;
                o.dist.xy = float2(0.0, edgeLength) * o.pos.w * cornerSize;
                o.dist.z = 1.0 / o.pos.w;
                OUT.Append(o);

                // New
                /*OUT.RestartStrip();

                o.pos = p1;
                o.pos.xy += float2(1,1) * 0.002 * o.pos.w;
                o.dist.xy = float2(edgeLength, 0.0) * o.pos.w * cornerSize;
                o.dist.z = 1.0 / o.pos.w;
                OUT.Append(o);

                o.pos = p2;
                o.pos.xy += float2(1, 1) * 0.002 * o.pos.w;
                o.dist.xy = float2(0.0, edgeLength) * o.pos.w * cornerSize;
                o.dist.z = 1.0 / o.pos.w;
                OUT.Append(o);*/

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

                //if (t.x >= 256 || t.y >= 256 || t.z >= 256) return true;
                //return false;

                float2 p0 = vertsPosRWBuffer[t.x].xy / vertsPosRWBuffer[t.x].w;
                float2 p1 = vertsPosRWBuffer[t.y].xy / vertsPosRWBuffer[t.y].w;
                float2 p2 = vertsPosRWBuffer[t.z].xy / vertsPosRWBuffer[t.z].w;

                return isTriCulled(p0, p1, p2);
            }

            bool isEdgeDrawn(int adjTriIdx, uint edgeType){

                // If the type value is <= 0, then never draw the edge.
                if (edgeType <= 0) return false;

                // If the type value is 2, then always draw the edge.
                if (edgeType == 2) return true;

                // If there's no adjacent face (-1), or if the adjacent face is showing its backface, then draw the edge.
                if (adjTriIdx < 0 || isTriCulledByIdx(adjTriIdx)) return true;

                // Otherwise, don't draw it.
                return false;
            }

            // For some reason, the following only workds with Unity's unimplemented triangleadj.
            // I tried using triangle instead, and it gave different results.
            [maxvertexcount(6)]
            void geom(triangleadj v2g IN[6], inout LineStream<g2f> OUT)
            {
                // Used to calculate corner highlights.
                float2 p0 = IN[0].pos.xy / IN[0].pos.w;
                float2 p1 = IN[1].pos.xy / IN[1].pos.w;
                float2 p2 = IN[2].pos.xy / IN[2].pos.w;
                float edge0Length = length(p1 - p0);
                float edge1Length = length(p2 - p1);
                float edge2Length = length(p0 - p2);
                float cornerSize = 1000 - _WireCornerSize;

                // Loose edges
                // ===========
                if (IN[0].idxType.y < 0){
                    appendEdge(IN[1].pos, IN[2].pos, edge1Length, cornerSize, OUT);
                    return;
                }
                if (IN[1].idxType.y < 0){
                    appendEdge(IN[2].pos, IN[0].pos, edge2Length, cornerSize, OUT);
                    return;
                }
                if (IN[2].idxType.y < 0){
                    appendEdge(IN[0].pos, IN[1].pos, edge0Length, cornerSize, OUT);
                    return;
                }

                bool triCulled = isTriCulled(p0, p1, p2);
                // If this tri is culled, skip it.
                if (triCulled) return;

                // Main edges
                // ==========
                uint triIdx = getTriIdx(IN[0].idxType.x, IN[1].idxType.x, IN[2].idxType.x); // Index of this tri.
                int3 adj = triAdjBuffer[triIdx]; // Indexes of the 3 adjacent tris to this one (or -1 if there's no tri on a specific side).

                // edge0
                if (isEdgeDrawn(adj.x, IN[1].idxType.y)){
                    appendEdge(IN[0].pos, IN[1].pos, edge0Length, cornerSize, OUT);
                }
                if (isEdgeDrawn(adj.y, IN[2].idxType.y)){
                    appendEdge(IN[1].pos, IN[2].pos, edge1Length, cornerSize, OUT);
                }
                if (isEdgeDrawn(adj.z, IN[0].idxType.y)){
                    appendEdge(IN[2].pos, IN[0].pos, edge2Length, cornerSize, OUT);
                }
            }

            /// Frag
            /// ====
            fixed4 _WireColor;
            float _WireStrength;
            float _WireCornerStrength;
            fixed4 frag(g2f IN) : SV_Target
            {
                float minDistanceToCorner = min(IN.dist[0], IN.dist[1]) * IN.dist[2];
                
                // Normal line color.
                if (minDistanceToCorner > 0.9) {
                    half4 color = (half4)_WireColor * _WireStrength;
                    //color.a = 0.2;
                    return color;
                }

                // Corner highlight color.
                half4 cornerColor = (half4)_WireColor;
                cornerColor.xyz += half3(0.2,0.2,0.2); // Corners are slightly lighter.
                //cornerColor.a = 0.2;

                return (half4)cornerColor * _WireStrength * _WireCornerStrength;
            }

            ENDCG
        }
    }
}
