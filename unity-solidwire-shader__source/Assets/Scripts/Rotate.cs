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
        transform.Rotate(Vector3.up, Time.deltaTime*70f, Space.World);

        //transform.position = Vector3.forward * (Mathf.Cos(Time.time) * 40f + 44f);

        //this.GetComponent<MeshRenderer>().material.SetFloat("_WireStrength", 1.5f + Mathf.Cos(Time.time));
    }
}
