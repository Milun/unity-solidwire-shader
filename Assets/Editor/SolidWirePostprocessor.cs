using UnityEngine;
using UnityEditor;
using System.Collections;

class SolidWirePostprocessor : AssetPostprocessor
{
    public Material defaultMaterial;

    /*void OnPreprocessAudio()
    {
        //AudioImporter audioImporter = (AudioImporter)assetImporter;
        //audioImporter.format = AudioImporterFormat.Compressed;
    }*/

    // Good for ensuring the correct settings are applied to the imported meshes.
    // Dunno if this can be used to auto apply stuff or preprocess other data though.
    void OnPreprocessModel()
    {
        //Debug.Log("Imported: " + assetPath);

        if (assetPath.Contains("Assets/Meshes/SolidWire/"))
        {
            //Debug.Log("Imported: " + assetPath);

            ModelImporter modelImporter = assetImporter as ModelImporter;

            // The following settings must be used to ensure the SolidWire mesh data gets imported correctly.
            /*modelImporter.importCameras = false;
            modelImporter.importLights = false;*/
            
            modelImporter.meshCompression = ModelImporterMeshCompression.Off;       // Mesh Compression
            modelImporter.isReadable = true;                                        // Read/Write Enabled
            modelImporter.optimizeMeshPolygons = true;                              // Optimize Mesh
            modelImporter.optimizeMeshVertices = false;                             // Optimize Mesh; Not sure if this is necessary.
            modelImporter.keepQuads = false;                                        // Keep Quads
            modelImporter.weldVertices = false;                                     // Weld Vertices

            modelImporter.importNormals = ModelImporterNormals.Import;              // Normals
            modelImporter.importBlendShapeNormals = ModelImporterNormals.Import;    // Blend Shape Normals
            modelImporter.normalCalculationMode = ModelImporterNormalCalculationMode.Unweighted; // Normals Mode
            modelImporter.normalSmoothingSource = ModelImporterNormalSmoothingSource.None;
            modelImporter.importTangents = ModelImporterTangents.None;
            modelImporter.swapUVChannels = false;

            // Materials (replace the imported mesh's material with the default SolidWire material).
            modelImporter.SearchAndRemapMaterials(ModelImporterMaterialName.BasedOnTextureName, ModelImporterMaterialSearch.RecursiveUp);


            //modelImporter.AddRemap(, )

            //modelImporter.addCollider = false;

            //modelImporter.
        }
    }

    private Mesh GetMeshFromGameObject(GameObject gameObject)
    {
        // Skinned
        var skinnedMeshRenderer = gameObject.GetComponent<SkinnedMeshRenderer>();
        if (skinnedMeshRenderer) {
            return skinnedMeshRenderer.sharedMesh;
        }

        // Non-skinned
        return gameObject.GetComponent<MeshFilter>().sharedMesh;
    }

    void RemapDefaultMaterial(Transform t)
	{
        // Remap materials.
        Renderer renderer = t.gameObject.GetComponent<Renderer>();
        if (defaultMaterial == null) {
            defaultMaterial = AssetDatabase.LoadAssetAtPath<Material>("Assets/Materials/SolidWireDefault.mat");
        }

        if (renderer != null)
        {
            Material[] materials = renderer.sharedMaterials;

            for (int materialIndex = 0; materialIndex < materials.Length; materialIndex++) {
                Material material = materials[materialIndex];
                assetImporter.AddRemap(new AssetImporter.SourceAssetIdentifier(material), defaultMaterial);
            }

            SolidWire solidWire = t.gameObject.AddComponent<SolidWire>();
            solidWire.Postprocess();
        }

        // Recurse
        foreach (Transform child in t) {
            RemapDefaultMaterial(child);
        }
    }

    void OnPostprocessModel(GameObject g)
    {
        /*uint[] tris = (uint[])(object)GetMeshFromGameObject(g).triangles;
        int triIdxCount = tris.Length;*/

        
        RemapDefaultMaterial(g.transform);

        //Debug.Log(triIdxCount);
        

        // YES! Auto adds the SolidWire to it! Does this mean I can set values on it?
        /*
        g.GetComponent<SolidWire>().Test = "TestTest";*/

        // So just make a public variable on SolidWire that's HIDDEN from the inspector. Then have this thing process the verts for it. EZ.
        // Only issue is that it may re-calculate for the same model each time it's dragged in, but maybe with some clever statics it could be improved or somethin.
    }
}
