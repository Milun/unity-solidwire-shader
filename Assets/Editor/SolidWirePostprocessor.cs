using UnityEngine;
using UnityEditor;
using System.Collections;

class SolidWirePostprocessor : AssetPostprocessor
{

    /*void OnPreprocessAudio()
    {
        //AudioImporter audioImporter = (AudioImporter)assetImporter;
        //audioImporter.format = AudioImporterFormat.Compressed;
    }*/

    // Good for ensuring the correct settings are applied to the imported meshes.
    // Dunno if this can be used to auto apply stuff or preprocess other data though.
    void OnPreprocessModel()
    {
        Debug.Log("Imported: " + assetPath);

        if (assetPath.Contains("@"))
        {
            ModelImporter modelImporter = assetImporter as ModelImporter;
            modelImporter.materialImportMode = ModelImporterMaterialImportMode.None;

            modelImporter.addCollider = false;

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

    void OnPostprocessModel(GameObject g)
    {
        /*uint[] tris = (uint[])(object)GetMeshFromGameObject(g).triangles;
        int triIdxCount = tris.Length;*/

        SolidWire solidWire = g.AddComponent<SolidWire>();

        //Debug.Log(triIdxCount);
        solidWire.Postprocess();











        // YES! Auto adds the SolidWire to it! Does this mean I can set values on it?
        /*
        g.GetComponent<SolidWire>().Test = "TestTest";*/

        // So just make a public variable on SolidWire that's HIDDEN from the inspector. Then have this thing process the verts for it. EZ.
        // Only issue is that it may re-calculate for the same model each time it's dragged in, but maybe with some clever statics it could be improved or somethin.
    }
}
