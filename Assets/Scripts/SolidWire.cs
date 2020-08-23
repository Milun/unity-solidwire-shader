using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class SolidWire : MonoBehaviour
{
    private ComputeBuffer vertsPosRWBuffer; // RWBuffer. Will store the calculated clip pos of all vertices in an array for later use (values are set by the shader).
    private ComputeBuffer triIdxBuffer;     // Store each tri's 3 vert indexes (mesh.triangles) as uint3s.
    private ComputeBuffer triAdjBuffer;     // Storing each tri's 3 adjacent tri indexes (or -1 if there's no adjacent tri on an edge).

    private int triIdxCount;
    private Mesh mesh;
    private Material material;              // Reference to the SolidWire material.

    // Start is called before the first frame update
    void Start()
    {
        InitMeshMaterial(); // Get the mesh and material.

        uint[] tris = (uint[])(object)mesh.triangles;
        triIdxCount = tris.Length;

        // triIdxBuffer
        // ============
        // Store the indexes of verts for all tris.
        int triIdxStride = System.Runtime.InteropServices.Marshal.SizeOf(typeof(uint)) * 3;
        triIdxBuffer = new ComputeBuffer(triIdxCount, triIdxStride, ComputeBufferType.Default);
        uint[,] triVecs = new uint[triIdxCount/3,3];
        for (uint i = 0; i < triIdxCount; i += 3) {
            triVecs[i/3,0] = tris[i];
            triVecs[i/3,1] = tris[i+1];
            triVecs[i/3,2] = tris[i+2];
        }
        triIdxBuffer.SetData(triVecs);
        material.SetBuffer("triIdxBuffer", triIdxBuffer);
        material.SetInt("triIdxCount", triIdxCount);

        // triAdjBuffer
        // ============
        // Store the indexes of adjacent tris.
        int triAdjStride = System.Runtime.InteropServices.Marshal.SizeOf(typeof(int)) * 3;
        triAdjBuffer = new ComputeBuffer(triIdxCount/3, triAdjStride, ComputeBufferType.Default);
        int[,] triAdjs = new int[triIdxCount/3,3];

        /**
         * Normally, the vert indexes of tris are affected by the UV map, meaning that a single vert can have multiple indexes in some cases.
         * The meshes therefore NEED TO HAVE THE CUSTOM SOLIDWIRE BLENDER SCRIPT APPLIED in order for this to work.
         * The Blender script will assign a vert's mesh index to its UV.x value.
         * That way all the verts in mesh.vertices will know their both their UV index, and their index in the mesh.
         */
        uint[] meshTris = new uint[triIdxCount];
        for (int i = 0; i < triIdxCount; i++)
        {
            meshTris[i] = (uint)mesh.uv[tris[i]].x;
        }

        // Now, for each tri, find its adjacent vertices.
        for (int i = 0; i < triIdxCount; i += 3)
        {
            var adj = GetAdjacentTris(meshTris, i);
            triAdjs[i / 3, 0] = adj[0];
            triAdjs[i / 3, 1] = adj[1];
            triAdjs[i / 3, 2] = adj[2];
        }

        triAdjBuffer.SetData(triAdjs);
        material.SetBuffer("triAdjBuffer", triAdjBuffer);

        // vertsPosRWBuffer
        // ================
        int vertCount = mesh.vertexCount * 2; // Weird bug: If mesh.vertexCount is used for the buffer, it won't be enough.
                                              // Not sure how to get the actual number, so * 2 added as a quickfix for now.

        int vertsPosStride = System.Runtime.InteropServices.Marshal.SizeOf(typeof(Vector4));
        vertsPosRWBuffer = new ComputeBuffer(vertCount, vertsPosStride, ComputeBufferType.Default);
        material.SetBuffer("vertsPosBuffer", vertsPosRWBuffer);
    }

    /// <summary>
    /// 
    /// </summary>
    /// <param name="meshTris"></param>
    /// <param name="curTriVertIdx">Index of the first vert in the tri.</param>
    /// <returns></returns>
    private int[] GetAdjacentTris(uint[] meshTris, int curTriVertIdx)
    {
        int t0 = -1; // Adjacent tri 1.
        int t1 = -1; // Adjacent tri 2.
        int t2 = -1; // Adjacent tri 3.

        uint v0 = meshTris[curTriVertIdx];
        uint v1 = meshTris[curTriVertIdx+1];
        uint v2 = meshTris[curTriVertIdx+2];

        for (int i = 0; i < meshTris.Length; i+= 3)
        {
            if (i == curTriVertIdx) continue; // The tri being checked isn't adjacent to itself.

            // Index of the 3 verts that make up the current tri being checked.
            uint[] t = new uint[] { meshTris[i], meshTris[i + 1], meshTris[i + 2] };

            // This tri is adjacent to edge0.
            if (t0 < 0)
            {
                if (CheckTriContainsEdge(t, new uint[] {v0, v1 })){
                    t0 = i / 3;
                    continue;
                }
            }

            // This tri is adjacent to edge1.
            if (t1 < 0)
            {
                if (CheckTriContainsEdge(t, new uint[] { v1, v2 }))
                {
                    t1 = i / 3;
                    continue;
                }
            }

            // This tri is adjacent to edge2.
            if (t2 < 0)
            {
                if (CheckTriContainsEdge(t, new uint[] { v2, v0 }))
                {
                    t2 = i / 3;
                    continue;
                }
            }
        }

        int[] output = new int[] { t0, t1, t2 };
        //if (output[0] > 128) output[0] = 128;
        //if (output[1] > 128) output[1] = 128;
        //if (output[2] > 128) output[2] = 128;
        //Debug.Log(t0 + " " + t1 + " " + t2);

        return output;
    }

    /// <summary>
    /// Returns true if the tri made up of triVertIdxs contains both of the provided edge verts.
    /// </summary>
    /// <param name="triVertIdxs"></param>
    /// <param name="edgeVertIdxs"></param>
    /// <returns></returns>
    private bool CheckTriContainsEdge(uint[] triVertIdxs, uint[] edgeVertIdxs)
    {
        if (!Array.Exists(triVertIdxs, e => e == edgeVertIdxs[0])) return false;
        if (!Array.Exists(triVertIdxs, e => e == edgeVertIdxs[1])) return false;
        return true;
    }

    /// <summary>
    /// Assigns the mesh and material the GameObject uses. Auto detects whether it's a skinned mesh or not.
    /// </summary>
    /// <returns></returns>
    private void InitMeshMaterial()
    {
        // Skinned
        var skinnedMeshRenderer = GetComponent<SkinnedMeshRenderer>();
        if (skinnedMeshRenderer)
        {
            mesh = skinnedMeshRenderer.sharedMesh;
            material = skinnedMeshRenderer.material;
            return;
        }

        // Non-skinned
        mesh = GetComponent<MeshFilter>().sharedMesh;
        material = GetComponent<MeshRenderer>().material;
    }

    // Update is called once per frame
    void Update()
    {
        // Clear the RWBuffer each frame.
        Graphics.ClearRandomWriteTargets();
        material.SetPass(0);
        material.SetBuffer("vertsPosRWBuffer", vertsPosRWBuffer);
        Graphics.SetRandomWriteTarget(1, vertsPosRWBuffer, false);
    }

    void OnDestroy()
    {
        vertsPosRWBuffer.Release();
        triIdxBuffer.Release();
        triAdjBuffer.Release();
    }
}
