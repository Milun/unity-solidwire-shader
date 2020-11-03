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
    private Material[] materials;           // Reference to the SolidWire material(s).

    private static int maxVertCount = 0;    // All instances of the shader will set the size of the RWBuffer globally.
                                            // I don't know how (or if you can) have different RWBuffer sizes for each instance of the material,
                                            // so for now, they'll all take on the largest size.
                                            // (Wasteful I know. I hope there's a way around this in the future).

    // Start is called before the first frame update
    void Start()
    {
        InitMeshMaterial(); // Get the mesh and material.

        uint[] tris = (uint[])(object)mesh.triangles;
        triIdxCount = tris.Length;

        /*Debug.Log(mesh.subMeshCount);
        for (var i = 0; i < mesh.subMeshCount; i++) { 
            Debug.Log("v: " + mesh.GetSubMesh(i).indexStart);
        }*/

        //Debug.Log("LENGTH: " + triIdxCount);

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
        

        // vertsPosRWBuffer
        // ================
        // Probably bad implementation:
        // I don't think it's possible to have the vertPosBuffer have a different size for each individual mesh.
        // As such, if a mesh with 30 verts is created after one with 180, then the 180 vert mesh will have its buffer set to 30 (and won't draw every edge as a result)!
        // My (hopefully temporary) solution is to just have all instances of the shader use the maximum buffer size required as a result.
        if (mesh.vertexCount > maxVertCount) maxVertCount = mesh.vertexCount;
        int vertCount = maxVertCount;

        int vertsPosStride = System.Runtime.InteropServices.Marshal.SizeOf(typeof(Vector4));
        vertsPosRWBuffer = new ComputeBuffer(vertCount, vertsPosStride, ComputeBufferType.Default);

        foreach (var mat in materials)
        {
            mat.SetBuffer("triIdxBuffer", triIdxBuffer);
            mat.SetInt("triIdxCount", triIdxCount);
            mat.SetBuffer("triAdjBuffer", triAdjBuffer);
            mat.SetBuffer("vertsPosBuffer", vertsPosRWBuffer);
        }
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
        //if (t0 > triIdxCount) Debug.Log("UH OH");
        //Debug.Log(output[0] + ", " + output[1] + ", " + output[2]);
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
            materials = skinnedMeshRenderer.materials;
            return;
        }

        // Non-skinned
        mesh = GetComponent<MeshFilter>().sharedMesh;
        materials = GetComponent<MeshRenderer>().materials;
    }

    // Update is called once per frame
    void Update()
    {
        // Clear the RWBuffer each frame.
        //Graphics.ClearRandomWriteTargets();
        foreach(var m in materials) { 
            m.SetPass(2);
            m.SetBuffer("vertsPosRWBuffer", vertsPosRWBuffer);
        }
        Graphics.SetRandomWriteTarget(1, vertsPosRWBuffer, false);
    }

    void OnDestroy()
    {
        vertsPosRWBuffer.Release();
        triIdxBuffer.Release();
        triAdjBuffer.Release();

        vertsPosRWBuffer.Dispose();
        triIdxBuffer.Dispose();
        triAdjBuffer.Dispose();
    }
}
