bl_info = {
    "name": "SolidWire FBX",
    "blender": (2, 92, 0),
    "category": "Object",
}

import copy
from io import StringIO
import bpy
import bmesh
import sys
from io import StringIO
from bpy.types import Operator
from bpy.props import (BoolProperty, FloatProperty, StringProperty, EnumProperty)
from bpy_extras.io_utils import ExportHelper

'''
    Author:
    =======
    Milun

    Compatibility:
    ==============
    This script was written for Blender v2.92.
    
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

TEMPNAME = ".___solidwiretemp___" # This name is appended to the original object while its dupe is being exported.
HIDE_FBX_LOGS = False

# The following modifiers will NOT be applied prior to the SolidWire calculations.
# All other modifiers will be applied prior; as SolidWire needs very specific, custom UVs to be applied to every vertex the final mesh will use.
MODIFIERS_TO_IGNORE = [
    "ARMATURE"
]

# Globals
# -------------------------------------------------------------------------------
# Source: https://blender.stackexchange.com/questions/45698/triangulate-mesh-in-python
def triangulateObject(obj):
    mesh = obj.data
    # Get a BMesh representation
    bm = bmesh.new()
    bm.from_mesh(mesh)

    #bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method=0, ngon_method=0)
    bmesh.ops.triangulate(bm, faces=bm.faces)

    # Finish up, write the bmesh back to the mesh
    bm.to_mesh(mesh)
    bm.free()

# Used to prevent printing the FBX export to console.
class NullIO(StringIO):
    def write(self, txt):
       pass


class EXPORT_OT_SolidWireFBX(Operator, ExportHelper):
    """Export to SolidWire FBX"""      # Use this as a tooltip for menu items and buttons.
    bl_idname = "export_scene.solidwire_fbx"        # Unique identifier for buttons and menu items to reference.
    bl_label = "Export SolidWire FBX"         # Display name in the interface.
    bl_options = {'REGISTER', 'UNDO'}  # Enable undo for the operator.

    # ExportHelper mixin class uses this
    filename_ext = ".fbx"

    # List of operator properties, the attributes will be assigned
    # to the class instance from the operator settings before calling.

    filter_glob: StringProperty(
        default="*.fbx",
        options={'HIDDEN'},
        maxlen=255,  # Max internal buffer length, longer would be clamped.
    )

    global_scale: FloatProperty(
        name="Scale",
        description="Scale multi?",
        default=1.0,
    )

    use_subsurf: BoolProperty(
        name="Use Subsurf",
        description="Use Subsurf?",
        default=False,
    )
    
    use_selection: BoolProperty(
        name="Selected only",
        description="Export only selected objects?",
        default=True,
    )

    apply_unit_scale: BoolProperty(
        name="Apply Unit Scale",
        description="Apply Unit Scale",
        default=True,
    )
    
    axis_forward: EnumProperty(
        name="Forward",
        description="Forward",
        items={
            ('X', 'X', 'X'), 
            ('Y', 'Y', 'Y'), 
            ('Z', 'Z', 'Z'), 
            ('-X', '-X', '-X'), 
            ('-Y', '-Y', '-Y'), 
            ('-Z', '-Z', '-Z')
        },
        default='-Z'
    )
    
    axis_up: EnumProperty(
        name="Up",
        description="Up",
        items={
            ('X', 'X', 'X'), 
            ('Y', 'Y', 'Y'), 
            ('Z', 'Z', 'Z'), 
            ('-X', '-X', '-X'), 
            ('-Y', '-Y', '-Y'), 
            ('-Z', '-Z', '-Z')
        },
        default='Y'
    )


    def execute(self, context):        # execute() is called when running the operator.

        print("---------------------------------------")
        print("--          SolidWireExport          --")
        print("---------------------------------------")

        activeObj = context.view_layer.objects.active
        selectedObjs = [o for o in context.selected_objects if o.type == 'MESH']
        
        exportObjs = []
        dupeObjs = []
        originalNames = []

        # Reverts any temporary changes made by the export script.
        def cleanup():

            bpy.ops.object.mode_set(mode = 'OBJECT')

            # Delete all the duplicated objects.
            bpy.ops.object.delete({"selected_objects": dupeObjs})

            # Select all the originally selected objects and set their names back to what they were. 
            for idx, obj in enumerate(selectedObjs):
                obj.select_set(True)
                # Swap the names back
                obj.name = originalNames[idx]
                # Set the active object again 
                if obj == activeObj:
                    context.view_layer.objects.active = obj
        
        try:
            # For each of the objects that was just selected.
            for idx, obj in enumerate(selectedObjs):

                # Duplicate this object
                # -----------------------------------------------------------------------

                # Deselect all objects.
                for o in bpy.context.selected_objects:
                    o.select_set(False)

                # Record the name of this object.
                originalNames.append(obj.name)

                # Only process selected objects that are meshes.
                if obj.type != 'MESH':
                    print("Processing skipped for object \"%s\" (%s)" % (obj.name, obj.type))
                    exportObjs.append(obj)
                    continue

                print("Processing object \"%s\"." % obj.name)

                # Select the current object
                obj.select_set(True)

                # Duplicate the object so as not to affect the original with the changes that are about to take place.
                context.view_layer.objects.active = obj
                bpy.ops.object.duplicate_move()
                _objOriginal = obj

                obj = context.view_layer.objects.active
                exportObjs.append(obj)
                dupeObjs.append(obj)

                # Swap the dupe's name with the original's (we need the dupe to have the right name when exporting):
                _objOriginal.name = obj.name + TEMPNAME
                obj.name = originalNames[idx]

                # Apply all non-ignored modifiers (the mesh modifiers) to the dupes.
                for modifier in obj.modifiers:
                    if modifier.type not in MODIFIERS_TO_IGNORE:
                        print("----- Modifier applied: %s" % (modifier.name))
                        bpy.ops.object.modifier_apply(modifier=modifier.name)

                # Triangulate the object. Every triangle in the final mesh needs to be processed for SolidWire.
                triangulateObject(obj)

                # Store reference to Mesh.
                mesh = obj.data

                # Ensure smooth shading is used for the mesh (this is used by the Unity shader to contract the normals).
                for f in mesh.polygons:
                    f.use_smooth = True


                # Convert all loose edges to triangles
                # -------------------------------------------------------------------------------------------

                # bmesh requires EDIT mode.
                # This will change the active object to EDIT mode.
                bpy.ops.object.mode_set(mode = 'EDIT') 
                bm = bmesh.from_edit_mesh(mesh)

                # Store an array of all edges in the mesh.
                edges = [e for e in bm.edges]

                # Find all the verts that aren't linked to faces.
                looseVerts = [v for v in bm.verts if not v.link_faces]

                # Find all edges that aren't part of faces.
                looseEdges = []
                for e in edges:

                    # Check if either of the verts in this edge are in the looseVerts array.
                    if e.verts[0] in looseVerts or e.verts[1] in looseVerts:
                        
                        # This edge is loose.
                        # Mark it as a sharp edge (it should always be drawn by the SolidWire shader).
                        e.smooth = False

                        # Store the group indexes for all vertex groups vertex[0] belongs to.
                        # (This is done so that armature weights, if there are any, can be duplicated to the new vert).
                        vert0Groups = []
                        for g in mesh.vertices[e.verts[0].index].groups:
                            vert0Groups.append(copy.copy(g))

                        # Store the loose edge data in an array for later modification.
                        el = type('looseedgedata', (object,), {

                            # Indexes of the two vertices that already exist in the loose edge
                            'vertIndexes': [e.verts[0].index, e.verts[1].index],

                            # Position of vertex[0]
                            'vert0co': copy.copy(e.verts[0].co),

                            # vertex[0] groups (if any)
                            'vert0Groups': vert0Groups    
                        })()
                        looseEdges.append(el)

                        print(e.verts[0].co)

                # Go back to object mode to enable modifying the mesh.
                bpy.ops.object.mode_set(mode = 'OBJECT')

                # Create the third vert for each loose edge, and have it be in the same location as its vert[0].
                for e in looseEdges:
                    mesh.vertices.add(1)
                    mesh.vertices[-1].co = e.vert0co

                    newVertIdx = len(mesh.vertices)-1

                    e.vertIndexes.append(newVertIdx)

                    # Clear any group data that may exist for the new vert's index from the vertex_groups.
                    # If this isn't done, then the new vert might gain unintended weights upon creation.
                    for gr in obj.vertex_groups:
                        gr.remove([newVertIdx])

                    # Add the new vert to the same vertex_groups as the one it was a clone of.
                    for g in e.vert0Groups:
                        for gr in obj.vertex_groups:
                            if gr.index == g.group:
                                if g.weight != 0:
                                    #print("NAME: %i, %i, %f, %s" % (vi, g, g, gr.name))
                                    gr.add([newVertIdx], g.weight, 'ADD')
                
                # Connect the loose edge to the new vert to create a new tri.
                bpy.ops.object.mode_set(mode = 'EDIT')
                bm = bmesh.from_edit_mesh(mesh)
                bm.verts.ensure_lookup_table() # Applies the newly created verts to Blender.
                for e in looseEdges:
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


                # Go through all tris and find any which have two verts in the exact same position.
                # For those tris that do, mark two of their edges as "fake" (LNEVER; the SolidWire shader in Unity will never draw them).
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
                    matIndex = float("inf")
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


                # Store edgeData in the vert's UVs
                # -------------------------------------------------

                # Unwrap all verts (they'll be modified in a bit).
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
                # - LALWAYS edges with two faces need to have one marked as LNORMAL, and one as LALWAYS (to prevent double rendering).
                sharpEdges = [] # The second time the same sharp edge is retrieved from getEdgeData, it will be marked as smooth instead.
                def processSharpEdge(edge, matIndex):
                    if edge.type == LALWAYS:
                        if matIndex != edge.mat:
                            edge.type = LNORMAL
                        else:
                            if edge in sharpEdges:
                                edge.type = LNORMAL
                            else:
                                sharpEdges.append(edge)

                # Materials are converted to vertex colors. Ensure the mesh has data for vertex colors.
                if not mesh.vertex_colors:
                    mesh.vertex_colors.new()

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
                    processSharpEdge(edge1, matIndex)
                    processSharpEdge(edge2, matIndex)
                    processSharpEdge(edge3, matIndex)

                    # If multiple materials are used, then the mesh will be rendered with multiple submeshes.
                    # Unfortunately, the Unity SolidWire shader breaks if multiple submeshes are used at this time, so instead we'll convert the materials to
                    # vertex colors instead.
                    # Assign the lowest mat color of each edge to its vert0.
                    matSlots = obj.material_slots
                    mesh.vertex_colors.active.data[face.loop_indices[0]].color = matSlots[edge1.mat].material.diffuse_color
                    mesh.vertex_colors.active.data[face.loop_indices[1]].color = matSlots[edge2.mat].material.diffuse_color
                    mesh.vertex_colors.active.data[face.loop_indices[2]].color = matSlots[edge3.mat].material.diffuse_color
                    
                    
                    #face.material_index = 0

                    # Assign edgeData here.
                    mesh.uv_layers.active.data[face.loop_indices[0]].uv.x = face.vertices[0]
                    mesh.uv_layers.active.data[face.loop_indices[1]].uv.x = face.vertices[1]
                    mesh.uv_layers.active.data[face.loop_indices[2]].uv.x = face.vertices[2]

                    mesh.uv_layers.active.data[i1].uv.y = edge1.type
                    mesh.uv_layers.active.data[i2].uv.y = edge2.type
                    mesh.uv_layers.active.data[i3].uv.y = edge3.type

                # Remove all materials from the object before exporting (ensuring only one submesh is used).
                obj.data.materials.clear()

        except Exception as e:

            # If anything goes wrong, revert the state back to before the export started.
            cleanup()

            # Show the error message.
            self.layout.label(text=e)

            # Stop the script (If this works).
            sys.exit()


        # END LOOP
        # -------------------------------------------------

        bpy.ops.object.mode_set(mode = 'OBJECT') 

        # Deselect all objects (just in case)
        # -------------------------------------------------
        for o in bpy.context.selected_objects:
            o.select_set(False)

        # Select all objects for exporting.
        # -------------------------------------------------
        for o in exportObjs:
            o.select_set(True)

        # Export
        # -----------------------------------------------------------------
        # Prevent bpy.ops.export_scene.fbx from filling the console with its prints.
        if HIDE_FBX_LOGS == True:
            temp = sys.stdout
            sys.stdout = NullIO()
        
        # TODO: Have these be actual settings and not hardcoded.
        bpy.ops.export_scene.fbx(
            filepath=           self.filepath,
            use_selection=      self.use_selection,
            global_scale=       self.global_scale, 
            apply_unit_scale=   self.apply_unit_scale, 
            use_subsurf=        self.use_subsurf,

            use_mesh_modifiers= True, # Apply non-armature modifiers.
            use_metadata=       True, 
            axis_forward=       self.axis_forward, 
            axis_up=            self.axis_up,

            # These two settings ensure the best chance that the FBX is imported into Unity correctly.
            apply_scale_options='FBX_SCALE_UNITS',
            bake_space_transform=True,
        )

        # Re-enable printing to console.
        if HIDE_FBX_LOGS == True:
            sys.stdout = temp

        # Cleanup
        # -----------------------------------------------------------------

        cleanup()

        return {'FINISHED'}            # Lets Blender know the operator finished successfully.



def menu_func(self, context):
    self.layout.operator(EXPORT_OT_SolidWireFBX.bl_idname)

# Registration
classes = (
    EXPORT_OT_SolidWireFBX,
)

def register():
    from bpy.utils import register_class
    for cls in classes:
        register_class(cls)

    bpy.types.TOPBAR_MT_file_export.prepend(menu_func)

def unregister():
    from bpy.utils import unregister_class
    for cls in reversed(classes):
        unregister_class(cls)

    bpy.types.TOPBAR_MT_file_export.remove(menu_func)



# This allows you to run the script directly from Blender's Text editor
# to test the add-on without having to install it.
if __name__ == "__main__":
    register()

    # test call
    bpy.ops.export_scene.solidwire_fbx('INVOKE_DEFAULT')












    