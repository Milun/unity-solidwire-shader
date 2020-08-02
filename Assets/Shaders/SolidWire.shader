Shader "Custom/SolidWire"
{
    Properties
    {
        _WireColor ("Wire color", Color) = (1,1,1,1) 
        _WireHighlight("Wire tip highlight strength", RANGE(0, 10)) = 3
        _AlbedoColor("Albedo color", Color) = (0,0,0,1)
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100
        Cull Back

        Pass
        {
            Name "Body"

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma geometry geom

            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float4 normal : NORMAL;
                float2 uv : TEXCOORD0;
            };

            struct v2g
            {
                float4 pos : POSITION;
                float2 idxType : TEXCOORD0; // x = vert mesh index | y = vert edge type: -1 | 0 | 1 | 2
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
                v.vertex.xyz -= normalize(v.normal) * 0.04; 
                o.pos = UnityObjectToClipPos(v.vertex);
                o.idxType = v.uv;

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
    }
}
