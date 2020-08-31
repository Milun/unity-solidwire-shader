import bpy
import bmesh
import os
from bpy import context

'''
    Author:
    =======
    Milun

    Compatibility:
    ==============
    This script was written for Blender v2.79b.
    It is NOT compatible with Blender version 2.8 onwards (as of the time of writing this).
    
    Description:
    ============
    This script needs to be applied to all meshes that will have the SolidWire material applied to them in Unity.
    Upon being applied, it will (for each selected mesh):
    - Triangulate the mesh.
    - Set the normals to smooth on the mesh.
    - Set the UV.x value for each vert in the mesh to be equal to its mesh index (aka, verts[9].UV.x = 9).
    - Set the UV.y value for each vert in the mesh to the type of edge it has.
        - In the 3D view, mark each edge as either smooth (LNORMAL), sharp (LALWAYS) or as a seam (LHIDE) to set its render type for Unity.
    - For each loose edge, it will convert it to a tri with the new vert being in the same location as vert[0].
        - The two new edges that were generated to make the tri will be marked as having the LNEVER type in Unity (meaning they will never be drawn).
        - These two new edges are referred to below as "fake" edges, as their only purpose is to allow the loose edges to be imported into Unity.
    After the script has been executed, it is then safe to export the mesh(es) as a .fbx for use with the SolidWire shader in Unity.
    
    WARNING:
    ========
    - No support for Blender modifiers yet (they will need to be applied on each mesh targetted before running this script).

    TODO:
    =====
    - Have the script clone the mesh and export it, rather than modifying the mesh permanently.
    - Add support for object modifiers.
    - Change this to a proper Blender import/export plugin.
    - This script is can probably be made much more efficient and/or flexible (it's literally one of the first Blender scripts I've ever written). 
'''

# Values set to the UV y value of each vert to indicate what type of edge it has.
# -------------------------------------------------------------------------------
LNEVER = -1  # Never draw (Special. Only used with "fake" edges).
LHIDE = 0 # Never draw
LNORMAL = 1 # Draw when an edge
LALWAYS = 2 # Always draw if not culled

# Source: https://blender.stackexchange.com/questions/45698/triangulate-mesh-in-python
def triangulateObject(obj):
    me = obj.data
    # Get a BMesh representation
    bm = bmesh.new()
    bm.from_mesh(me)

    bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method=0, ngon_method=0)

    # Finish up, write the bmesh back to the mesh
    bm.to_mesh(me)
    bm.free()

# Record which objects are selected when this is called.
selected = bpy.context.selected_objects

# Deselect all objects.
for o in bpy.context.selected_objects:
    o.select = False
    
# For each of the objects that was just selected.
for objIdx, objCur in enumerate(selected):
    
    print("Processing object \"%s\"." % objCur.name)
    
    # Select the current object
    objCur.select = True
    
    # Make the object active too
    bpy.context.scene.objects.active = bpy.data.objects[objCur.name]
    
    # Store reference to Mesh.
    mesh = objCur.data

    # Triangulate the mesh.
    triangulateObject(objCur)

    # Ensure smooth shading.
    for f in mesh.polygons:
        f.use_smooth = True

    # bmesh requires EDIT mode.
    # This will change the active object to EDIT mode.
    bpy.ops.object.mode_set(mode = 'EDIT')
    bm = bmesh.from_edit_mesh(mesh)

    # Store an array of all edges
    edges = [e for e in bm.edges]

    # Find all the verts with no faces attached.
    looseVerts = [v for v in bm.verts if not v.link_faces]
    
    # Find all edges that aren't part of faces.
    looseData = []
    for e in edges:
        
        # This edge has a loose vert if it's contained in the looseVerts array.
        if e.verts[0] in looseVerts or e.verts[1] in looseVerts:
            
            # Mark the existing edge as a sharp edge (it should always be drawn in Unity).
            e.smooth = False

            # Store the group indexes for all vertex groups vertex[0] belongs to.
            # (This is done so that armature weights can be duplicated to the new vert).
            vert0Groups = []
            for g in mesh.vertices[e.verts[0].index].groups:
                vert0Groups.append(type('_group', (object,), {
                    'group': g.group,
                    'weight': g.weight
                })())
                #g.weight = 0
                #print("G %i, %i, %f" % (e.verts[0].index, g.group, g.weight))

            # Store the loose edge data in an array for later modification.
            el = type('looseedgedata', (object,), {
                'vertIndexes':[e.verts[0].index,e.verts[1].index],
                'vert0co':e.verts[0].co,
                'vert0Groups': vert0Groups
            })()
            looseData.append(el)
    
    # Go back to object mode to enable modifying the mesh.
    bpy.ops.object.mode_set(mode = 'OBJECT')

    # Create the third vert for each loose edge, and have it be in the same location as its vert[0].
    for e in looseData:
        mesh.vertices.add(1)
        mesh.vertices[-1].co = e.vert0co
        e.vertIndexes.append(len(mesh.vertices)-1)

        # Clear any group data that may exist for the new vert's index from the vertex_groups.
        # If this isn't done, then the new vert might gain unintended weights upon creation.
        vi = len(mesh.vertices)-1
        for gr in objCur.vertex_groups:
            gr.remove([vi])

        # Add the new vert to the same vertex_groups as the one it was a clone of.
        for g in e.vert0Groups:
            for gr in objCur.vertex_groups:
                if gr.index == g.group:
                    if g.weight != 0:
                        #print("NAME: %i, %i, %f, %s" % (vi, g, g, gr.name))
                        gr.add([vi], g.weight, 'ADD')
    
    # Connect the loose edge to the new vert to create a new tri.
    bpy.ops.object.mode_set(mode = 'EDIT')
    bm = bmesh.from_edit_mesh(mesh)
    bm.verts.ensure_lookup_table() # Applies the newly created verts to Blender.
    for e in looseData:
        bm.faces.new((
            bm.verts[e.vertIndexes[0]],
            bm.verts[e.vertIndexes[1]],
            bm.verts[e.vertIndexes[2]]
        ))
    
    # Applies the newly created data (refreshes the indexes).
    bpy.ops.object.mode_set(mode = 'OBJECT')
    bpy.ops.object.mode_set(mode = 'EDIT')
    bm = bmesh.from_edit_mesh(mesh)

    # Just in case (may not be necessary)
    bm.verts.ensure_lookup_table()
    bm.edges.ensure_lookup_table()
    bm.faces.ensure_lookup_table()

    # Go through all faces and find any tris which have 2 verts in the exact same position.
    # For those tris that do, mark two of their edges as "fake" (the SolidWire shader in Unity will never draw them).
    fakeEdges = []
    for f in bm.faces:
        # If two verts match, then it's a fake face.
        if f.edges[0].verts[0].co == f.edges[0].verts[1].co:
            fakeEdges.append(f.edges[0].index)
            fakeEdges.append(f.edges[1].index)

        if f.edges[1].verts[0].co == f.edges[1].verts[1].co:
            fakeEdges.append(f.edges[1].index)
            fakeEdges.append(f.edges[2].index)
            
        if f.edges[2].verts[0].co == f.edges[2].verts[1].co:
            fakeEdges.append(f.edges[2].index)
            fakeEdges.append(f.edges[0].index)

    # Store all relevant edge data to the SolidWire export.
    edgeData = []
    for e in bm.edges:
        v = []
        v.append(e.verts[0].index)
        v.append(e.verts[1].index)

        t = LNORMAL
        if e.smooth == False:
            t = LALWAYS
        if e.seam == True:
            t = LHIDE
        if e.index in fakeEdges:
            t = LNEVER

        el = type('edgedata', (object,), {
                'verts':v,
                'type':t
            })()

        edgeData.append(el)



    # Assigning edgeData to the vert UVs
    # ==================================

    # Unwrap all verts (they'll be modified in a second).
    bpy.ops.mesh.select_all(action = 'SELECT')
    bpy.ops.uv.unwrap()
    bpy.ops.object.mode_set(mode = 'OBJECT')

    # Gets the edgeData object based on the two verts.
    def getEdgeData(v0, v1):
        for e in edgeData:
            if v0 in e.verts and v1 in e.verts:
                flipped = False
                if e.verts[0] == v1: flipped = True
                return e, flipped
        print("ERROR: getEdgeData could not find a matching edge!")
        return 0

    # Set the UVs for all verts.
    # Rules:
    # - If the edge from v0 to v1 is sharp, then v0 will have the sharp UVs set.
    # - If the edge from v1 to v2 is sharp, then v1 will have the sharp UVs set.
    # - etc.
    test = 0
    for face in mesh.polygons:

        edge1, f1 = getEdgeData(face.vertices[0], face.vertices[1])
        edge2, f2 = getEdgeData(face.vertices[1], face.vertices[2])
        edge3, f3 = getEdgeData(face.vertices[2], face.vertices[0])
        
        f1 = False
        f2 = False
        f3 = False

        i1 = face.loop_indices[0 if not f1 else 1]
        i2 = face.loop_indices[1 if not f2 else 2]
        i3 = face.loop_indices[2 if not f3 else 0]

        # Assign edgeData here.
        mesh.uv_layers.active.data[face.loop_indices[0]].uv.x = face.vertices[0]
        mesh.uv_layers.active.data[face.loop_indices[1]].uv.x = face.vertices[1]
        mesh.uv_layers.active.data[face.loop_indices[2]].uv.x = face.vertices[2]

        mesh.uv_layers.active.data[i1].uv.y = edge1.type
        mesh.uv_layers.active.data[i2].uv.y = edge2.type
        mesh.uv_layers.active.data[i3].uv.y = edge3.type