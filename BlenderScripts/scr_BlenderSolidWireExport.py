import bpy
import bmesh
import os
import sys
from io import StringIO
from bpy import context
from bpy.types import Operator, Macro

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

DUPELAYER = 19

HIDE_FBX_LOGS = False

# The following modifiers 
MODIFIERS_TO_APPLY = [
    "BEVEL",
    "BOOLEAN",
    "BUILD",
    "DECIMATE",
    "EDGE_SPLIT",
    "MASK",
    "MIRROR",
    "MULTIRESOLUTION",
    "REMESH",
    "SCREW",
    "SKIN",
    "SOLIDIFY",
    "SUBSURF",
    "TRIANGULATE",
    "WIREFRAME"
]

# Used to prevent printing the FBX export to console.
class NullIO(StringIO):
    def write(self, txt):
       pass

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

# Hopefully these can be accessed between multiple functions.
selected = []
exportObjs = []
dupes = []
originalNames = []

active = False # The active object when the script is ran.

'''
print("!!! WARNING !!!")
print("!!! When ExportSolidWire is ran, it will DELETE EVERYTHING in layer 20! !!!")
print("!!! I couldn't figure out how to make it delete all temporary dupes after exporting to .fbx, and this was the workaround. !!!")
'''

def processSelection():

    print("Running: BlenderSolidWireExport")

    print("--------------------------------------------------")

    #objects = bpy.context.scene.objects
    active = bpy.context.scene.objects.active

    # Record which objects are selected when this is called.
    selected = bpy.context.selected_objects

    # Create an array of all objects which will be used for the export.
    # (Duped meshes + all non-mesh objects that were selected)
    exportObjs = []
    dupes = []
    originalNames = []
        
    # For each of the objects that was just selected.
    for objIdx, objCur in enumerate(selected):
        
        # Deselect all objects.
        for o in bpy.context.selected_objects:
            o.select = False

        # Record the names of the selected objects.
        originalNames.append(objCur.name)

        # Only process meshes.
        if objCur.type != 'MESH':
            print("Processing skipped for object \"%s\" (%s)" % (objCur.name, objCur.type))
            exportObjs.append(objCur)
            continue

        print("Processing object \"%s\"." % objCur.name)

        # Select the current object
        objCur.select = True

        # Duplicate the mesh so as not to affect the original
        bpy.context.scene.objects.active = objCur
        bpy.ops.object.duplicate_move()
        _original = objCur
        objCur = bpy.context.scene.objects.active
        exportObjs.append(objCur)
        dupes.append(objCur)

        # Swap names with the original (we need the dupe to have the right name when exporting):
        _original.name = objCur.name + ".___temp"
        objCur.name = originalNames[objIdx]
        
        # Make the object active too
        bpy.context.scene.objects.active = bpy.data.objects[objCur.name]
        
        # Apply certain modifiers to the dupes.
        for modifier in objCur.modifiers:
            if modifier.type in MODIFIERS_TO_APPLY:
                print("----- Modifier applied: %s" % (modifier.name))
                bpy.ops.object.modifier_apply(modifier=modifier.name)

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

        # Sort all mesh faces by material (this will make materials with a lower index take priority over materials with a higher index when rendering).
        bpy.ops.mesh.select_all(action='SELECT')  
        bpy.ops.mesh.sort_elements(type="MATERIAL", elements={'FACE'}, reverse=False)
        bpy.ops.mesh.select_all(action='DESELECT')

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

            #print(f.material_index)

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
        # - Store the indexes of the two verts the edge has
        # - Store the type of the edge (based on if it's marked normal/sharp/seam in Blender)
        # - Store the materials that the face(s) the edge belongs to have
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

            # Find the 1|2 faces that this edge belongs to, and record the lowest material index of them (it will take priority).
            matIndex = 99999
            for f in bm.faces:
                if e.verts[0] in f.verts and e.verts[1] in f.verts:
                    if f.material_index < matIndex:
                        matIndex = f.material_index

            el = type('edgedata', (object,), {
                    'verts':v,
                    'type':t,
                    'mat': matIndex
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

            # If this face's material's index isn't the highest priority for this edge, then swap an LALWAYS to a LNORMAL, 
            matIndex = face.material_index
            if matIndex != edge1.mat and edge1.type == LALWAYS: edge1.type = LNORMAL
            if matIndex != edge2.mat and edge2.type == LALWAYS: edge2.type = LNORMAL
            if matIndex != edge3.mat and edge3.type == LALWAYS: edge3.type = LNORMAL

            # Assign edgeData here.
            mesh.uv_layers.active.data[face.loop_indices[0]].uv.x = face.vertices[0]
            mesh.uv_layers.active.data[face.loop_indices[1]].uv.x = face.vertices[1]
            mesh.uv_layers.active.data[face.loop_indices[2]].uv.x = face.vertices[2]

            mesh.uv_layers.active.data[i1].uv.y = edge1.type
            mesh.uv_layers.active.data[i2].uv.y = edge2.type
            mesh.uv_layers.active.data[i3].uv.y = edge3.type
    
    print("--------------------------------------------------")

    # Deselect all objects.
    for o in bpy.context.selected_objects:
        o.select = False

    # Select all objects for exporting.
    for o in exportObjs:
        o.select = True

    print("Exporting to FBX.")

    # Prevent bpy.ops.export_scene.fbx from filling the console with its prints.
    if HIDE_FBX_LOGS == False:
        temp = sys.stdout
        sys.stdout = NullIO()

    # "filename" defined when the script is called.
    filepath = bpy.data.filepath
    directory = os.path.dirname(filepath)
    bpy.ops.export_scene.fbx(
        filepath = os.path.join( dir if dir else directory, filename + ".fbx"), # Either save to the "dir" provided, 
        use_selection = True,
        apply_scale_options = 'FBX_SCALE_ALL',
        bake_space_transform = True, # Needs to be False if an armature is being used?
        check_existing = True
    )

    # Re-enable printing to console.
    if HIDE_FBX_LOGS == False:
        sys.stdout = temp

    print("Removing dupes.")

    # Deselect all objects.
    for o in bpy.context.selected_objects:
        o.select = False

    # Select and delete all the dupes.
    for o in dupes:
        o.select = True
        bpy.context.scene.objects.active = o
        bpy.ops.object.delete()

    # Select all the originally selected meshes. 
    for i, o in enumerate(selected):
        o.select = True
        o.name = originalNames[i] # Swap the names back 
        if o == active:
            bpy.context.scene.objects.active = o

    # Store these values globally for the removeDupes function to use
    # (FIXME: there's probably a smarter way to do this)
    '''bpy.context.object["solidWireSelected"] = selected
    bpy.context.object["solidWireExportObjs"] = exportObjs
    bpy.context.object["solidWireDupes"] = dupes'''


# There seems to be no way to have Blender export a .fbx using INVOKE_DEFAULT, and then have call a script only after the user has saved their file.
# This is why I had to do it this way.
processSelection()

