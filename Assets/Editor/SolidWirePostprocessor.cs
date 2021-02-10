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

    void OnPostprocessModel(GameObject g)
    {
        // YES! Auto adds the SolidWire to it! Does this mean I can set values on it?
        g.AddComponent<SolidWire>();
        g.GetComponent<SolidWire>().Test = "RebelRebel";

        // So just make a public variable on SolidWire that's HIDDEN from the inspector. Then have this thing process the verts for it. EZ.
        // Only issue is that it may re-calculate for the same model each time it's dragged in, but maybe with some clever statics it could be improved or somethin.
    }
}
