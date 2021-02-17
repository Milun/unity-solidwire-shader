using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class SolidWire : MonoBehaviour
{
    private ComputeBuffer vertsPosRWBuffer; // RWBuffer. Will store the calculated clip pos of all vertices in an array for later use (values are set by the shader).
    [SerializeField][HideInInspector] private ComputeBuffer triIdxBuffer;     // Store each tri's 3 vert indexes (mesh.triangles) as uint3s.
    [SerializeField][HideInInspector] private ComputeBuffer triAdjBuffer;     // Storing each tri's 3 adjacent tri indexes (or -1 if there's no adjacent tri on an edge).

    private Material[] materials;           // Reference to the SolidWire material(s).

    // The following are calculated when the mesh is imported.
    [SerializeField][HideInInspector] private uint[] triVerts;      // mesh.triangles.
    [SerializeField][HideInInspector] private int[] triAdjs;        // Array of triangle adjacencies (in groups of 3s).

    [SerializeField][HideInInspector] private int triIdxCount;
    [SerializeField][HideInInspector] private Mesh mesh;

    private static int maxVertCount = 0;    // All instances of the shader will set the size of the RWBuffer globally.
                                            // I don't know how (or if you can) have different RWBuffer sizes for each instance of the material,
                                            // so for now, they'll all take on the largest size.
                                            // (Wasteful I know. I hope there's a way around this in the future).

    public GameObject LineObject;

    // Start is called before the first frame update
    void Start()
    {
        materials = GetMaterials();

        // triIdxBuffer
        // ============
        // Store the indexes of verts for all tris.
        int triIdxStride = System.Runtime.InteropServices.Marshal.SizeOf(typeof(uint)) * 3;
        triIdxBuffer = new ComputeBuffer(triIdxCount, triIdxStride, ComputeBufferType.Default);
        triIdxBuffer.SetData(triVerts);

        // triAdjBuffer
        // ============
        // Store the indexes of adjacent tris.
        int triAdjStride = System.Runtime.InteropServices.Marshal.SizeOf(typeof(int)) * 3;
        triAdjBuffer = new ComputeBuffer(triIdxCount / 3, triAdjStride, ComputeBufferType.Default);
        triAdjBuffer.SetData(triAdjs);

        // vertsPosRWBuffer
        // ================
        // Probably bad implementation:
        // I don't think it's possible to have the vertPosBuffer have a different size for each individual mesh.
        // As such, if a mesh with 30 verts is created after one with 180, then the 180 vert mesh will have its buffer set to 30 (and won't draw every edge as a result)!
        // My (hopefully temporary) solution is to just have all instances of the shader use the maximum buffer size required as a result.
        if (mesh.vertexCount > maxVertCount) maxVertCount = mesh.vertexCount;
        int vertCount = maxVertCount;
        //vertCount = mesh.vertexCount;

        int vertsPosStride = System.Runtime.InteropServices.Marshal.SizeOf(typeof(Vector4));
        vertsPosRWBuffer = new ComputeBuffer(vertCount, vertsPosStride, ComputeBufferType.Default);

        foreach (var mat in materials)
        {
            mat.SetBuffer("triIdxBuffer", triIdxBuffer);
            mat.SetInt("triIdxCount", triIdxCount);
            mat.SetBuffer("triAdjBuffer", triAdjBuffer);
            mat.SetBuffer("vertsPosBuffer", vertsPosRWBuffer);
        }

        //Explode();
    }

    /// <summary>
    /// Called by the SolidWirePostprocessor.
    /// </summary>
    public void Postprocess()
	{
        mesh = GetMesh(); // Get the mesh and material.

        triVerts = (uint[])(object)mesh.triangles;
        triIdxCount = triVerts.Length;

        triAdjs = new int[triIdxCount];

        /**
         * Normally, the vert indexes of tris are affected by the UV map, meaning that a single vert can have multiple indexes in some cases.
         * The meshes therefore NEED TO HAVE THE CUSTOM SOLIDWIRE BLENDER SCRIPT APPLIED in order for this to work.
         * The Blender script will assign a vert's mesh index to its UV.x value.
         * That way all the verts in mesh.vertices will know their both their UV index, and their index in the mesh.
         */
        uint[] meshTris = new uint[triIdxCount];
        for (int i = 0; i < triIdxCount; i++)
        {
            meshTris[i] = (uint)mesh.uv[triVerts[i]].x;
        }

        // Now, for each tri, find its adjacent vertices.
        for (int i = 0; i < triIdxCount; i += 3)
        {
            var adj = GetAdjacentTris(meshTris, i);
            triAdjs[i] = adj[0];
            triAdjs[i + 1] = adj[1];
            triAdjs[i + 2] = adj[2];
        }
    }

    /// <summary>
    /// 
    /// </summary>
    /// <param name="meshTris"></param>
    /// <param name="curTriVertIdx">Index of the first vert in the tri.</param>
    /// <returns></returns>
    /// EXTREMELY COSTLY! NEEDS TO BE DONE BETTER.
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

        return output;
    }

    /*public void Test2()
	{
        Debug.Log("Wubba");
	}*/

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
    private Mesh GetMesh()
    {
        // Skinned
        var skinnedMeshRenderer = GetComponent<SkinnedMeshRenderer>();
        if (skinnedMeshRenderer) {
            return skinnedMeshRenderer.sharedMesh;
        }

        // Non-skinned
        return GetComponent<MeshFilter>().sharedMesh;
    }

    private Material[] GetMaterials()
    {
        // Skinned
        var skinnedMeshRenderer = GetComponent<SkinnedMeshRenderer>();
        if (skinnedMeshRenderer) {
            return skinnedMeshRenderer.materials;
        }

        // Non-skinned
        return GetComponent<MeshRenderer>().materials;
    }

    bool IsTriCulled(Vector2 p0, Vector2 p1, Vector2 p2)
    {
        float a = 0;
        a += (p1.x - p0.x) * (p1.y + p0.y);
        a += (p2.x - p1.x) * (p2.y + p1.y);
        a += (p0.x - p2.x) * (p0.y + p2.y);

        return a > 0;
    }

    Vector2 XY(Vector4 v)
	{
        return new Vector2(v.x, v.y);
	}

    bool IsTriCulledByIdx(int triIdx, Vector4[] clipPositions)
    {
        uint v0 = triVerts[triIdx];
        uint v1 = triVerts[triIdx+1];
        uint v2 = triVerts[triIdx+2];

        Vector2 p0 = XY(clipPositions[v0]) / clipPositions[v0].w;
        Vector2 p1 = XY(clipPositions[v1]) / clipPositions[v1].w;
        Vector2 p2 = XY(clipPositions[v2]) / clipPositions[v2].w;

        return IsTriCulled(p0, p1, p2);
    }

    /// <summary>
    /// Experimental (creates an object for every visible line on the frame that it's called).
    /// </summary>
    private void Explode()
	{
        if (!LineObject) return;

        // Clip positions for each of the vertices.
        Vector4[] clipPositions = new Vector4[maxVertCount];
        vertsPosRWBuffer.GetData(clipPositions);

        // For all tris, determine which are currently being culled.
        bool[] trisCulled = new bool[triVerts.Length / 3];
        for (int i = 0; i < triVerts.Length; i += 3)
        {
            bool isCulled = IsTriCulledByIdx(i, clipPositions);
            trisCulled[i / 3] = isCulled;
        }

        var colors = mesh.colors;
        var verts = mesh.vertices;
        var uvs = mesh.uv;

        // For each tri...
        for (int i = 0; i < triVerts.Length; i += 3)
		{
            // Index of current tris.
            int triIdx = i;

            // Index of the 3 verts that make up this tri.
            uint idx0 = triVerts[triIdx];
            uint idx1 = triVerts[triIdx + 1];
            uint idx2 = triVerts[triIdx + 2];

            // Index of adjacent tris (if -1, there's no tri adjacent there).
            int adjTri0 = triAdjs[triIdx];
            int adjTri1 = triAdjs[triIdx+1];
            int adjTri2 = triAdjs[triIdx+2];

            bool c = trisCulled[triIdx/3];
            bool c0 = trisCulled[adjTri0/3];
            bool c1 = trisCulled[adjTri1/3];
            bool c2 = trisCulled[adjTri2/3];
            
            if (!c)
			{
                if (isEdgeDrawn(adjTri0, (uint)uvs[idx1].y, trisCulled))
                    GenerateLineObjects(
                        gameObject.transform.TransformPoint(verts[idx0]),
                        gameObject.transform.TransformPoint(verts[idx1]),
                        colors[idx1]
                    );
                if (isEdgeDrawn(adjTri1, (uint)uvs[idx2].y, trisCulled))
                    GenerateLineObjects(
                        gameObject.transform.TransformPoint(verts[idx1]),
                        gameObject.transform.TransformPoint(verts[idx2]),
                        colors[idx2]
                    );
                if (isEdgeDrawn(adjTri2, (uint)uvs[idx0].y, trisCulled))
                    GenerateLineObjects(
                        gameObject.transform.TransformPoint(verts[idx2]),
                        gameObject.transform.TransformPoint(verts[idx0]),
                        colors[idx0]
                    );
			}
		}

        Destroy(gameObject);
	}

    void GenerateLineObjects(Vector3 p1, Vector3 p2, Color color)
	{
        const float MAX_LENGTH = 2f;
        Vector3 v = p2 - p1;

        // Determine how many segments the vector should be split into.
        float segments = (float)Math.Ceiling(v.magnitude / MAX_LENGTH);
        //Debug.Log(segments);

        for (int i = 0; i < segments; i++) {
            GenerateLineObject(p1 + (v / segments) * (i), p1 + (v / segments) * (i + 1), color);
		}
	}

    public void SetColor(Color color)
	{
        this.GetMaterials()[0].SetColor("_Colorize", color);
	}

    void GenerateLineObject(Vector3 p1, Vector3 p2, Color color)
	{
        Vector3 v = p2 - p1;

        var lineObject = Instantiate(LineObject);
        lineObject.transform.position = p1;
        lineObject.transform.localScale = new Vector3(1f,1f,v.magnitude);
        lineObject.transform.rotation = Quaternion.LookRotation(v.normalized);
        lineObject.GetComponent<SolidWire>().SetColor(color);

        //lineObject.GetComponent<Rigidbody>().AddExplosionForce(50f, gameObject.transform.position, 200f, 1f, ForceMode.VelocityChange);

        //Debug.Log(v.magnitude);

        //lineObject.transform.rot
    }

    bool isEdgeDrawn(int adjTriIdx, uint edgeType, bool[] trisCulled)
    {

        // If the type value is <= 0, then never draw the edge.
        if (edgeType <= 0) return false;

        // If the type value is 2, then always draw the edge.
        if (edgeType == 2) return true;
        
        // If there's no adjacent face (adjTriIdx == -1), or if the adjacent face is showing its backface, then draw the edge.
        if (adjTriIdx < 0 || trisCulled[adjTriIdx]) return true;

        // Otherwise, don't draw it.
        return false;
    }

    // Update is called once per frame
    void Update()
    {
        /*Vector4[] clipPos = new Vector4[maxVertCount];
        vertsPosRWBuffer.GetData(clipPos);
        foreach(var e in clipPos)
		{
            Debug.Log(e);
        }*/

        if (Input.GetKeyDown(KeyCode.Space))
		{
            Explode();
		}


        // Clear the RWBuffer each frame.
        Graphics.ClearRandomWriteTargets();
        foreach(var m in materials) { 
            m.SetPass(2);
            m.SetBuffer("vertsPosRWBuffer", vertsPosRWBuffer);
        }
        Graphics.SetRandomWriteTarget(1, vertsPosRWBuffer, false);
    }

    void OnDestroy()
    {
        /*try
        {*/
            vertsPosRWBuffer.Release();
            triIdxBuffer.Release();
            triAdjBuffer.Release();

            vertsPosRWBuffer.Dispose();
            triIdxBuffer.Dispose();
            triAdjBuffer.Dispose();
        /*}
        catch (Exception err)
        {
            // Do nothing.
        }*/
    }
}
