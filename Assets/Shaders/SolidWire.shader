Shader "Custom/SolidWire"
{
    Properties
    {
        _WireColor ("Wire color", Color) = (1,1,1,1) 
        _WireStrength ("Wire strength", Range(0.1, 5.0)) = 1.5 
        _WireCornerSize("Wire corner size", RANGE(0, 1000)) = 800
        _WireCornerStrength("Wire corner strength", RANGE(0.0, 10.0)) = 1.5
        _AlbedoColor("Albedo color", Color) = (0,0,0,1)
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 200
        Cull Back

        Pass
        {
            Name "Body"

            CGPROGRAM
            #include "UnityCG.cginc"
            #pragma vertex vert
            #pragma fragment frag
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
                int2 idxType : TEXCOORD0; // x = vert mesh index (ignored bu .shader. Used by .cs) | y = vert edge type (used by shader): -1 | 0 | 1 | 2
            };

            struct g2f
            {
                float4 pos : SV_POSITION;
            };

            v2g vert (appdata v)
            {
                v2g o;
                
                /**
                * Reduce the size of the solid body along its normals so that it doesn't cause z-fighting with the Wire pass,
                * but still obscures any lines which would normally be obscured by geometry closer to the camera.
                */
                v.vertex.xyz -= normalize(v.normal) * 0.0005; 
                o.pos = UnityObjectToClipPos(v.vertex);
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

                // This is a real tri. Render it.
                o.pos = IN[0].pos;
                triangleStream.Append(o);

                o.pos = IN[1].pos;
                triangleStream.Append(o);

                o.pos = IN[2].pos;
                triangleStream.Append(o);
            }

            fixed4 _AlbedoColor;
            fixed4 frag(g2f IN) : SV_Target
            {
                return _AlbedoColor.rgba;
            }
            ENDCG
        }

        Pass
        {
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
                int2 idxType : TEXCOORD0; // x = vert mesh index (ignored bu .shader. Used by .cs) | y = vert edge type (used by shader): -1 | 0 | 1 | 2
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

                g2f o = (g2f)0;

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
                    return (half4)_WireColor * _WireStrength;
                }

                // Corner highlight color.
                half4 cornerColor = (half4)_WireColor;
                cornerColor.xyz += half3(0.2,0.2,0.2); // Corners are slightly lighter.

                return (half4)cornerColor * _WireStrength * _WireCornerStrength;
            }

            ENDCG
        }
    }
}
