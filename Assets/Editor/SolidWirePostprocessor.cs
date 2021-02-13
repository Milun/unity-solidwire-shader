using UnityEngine;
using UnityEditor;
using System.Collections;

class SolidWirePostprocessor : AssetPostprocessor
{
    public Material defaultMaterial;

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

    void ProcessGameObject(Transform t)
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

            // Add SolidWire.
            SolidWire solidWire = t.gameObject.AddComponent<SolidWire>();
            solidWire.Postprocess();
        }

        // Recurse
        foreach (Transform child in t) {
            ProcessGameObject(child);
        }
    }

    void OnPostprocessModel(GameObject g)
    {
        ProcessGameObject(g.transform);
    }
}
