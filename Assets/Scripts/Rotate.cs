using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class Rotate : MonoBehaviour
{
    // Start is called before the first frame update
    void Start()
    {
        
    }

    // Update is called once per frame
    void Update()
    {
        transform.Rotate(Vector3.one * Time.deltaTime * 30f);

        //this.GetComponent<MeshRenderer>().material.SetFloat("_WireStrength", 1.5f + Mathf.Cos(Time.time));
    }
}
