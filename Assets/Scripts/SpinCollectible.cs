using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class SpinCollectible : MonoBehaviour
{
    public float rotationSpeed = 300.0f; // Add a variable to control the rotation speed

	private void Start()
	{
		rotationSpeed = Random.Range(.50f * rotationSpeed, rotationSpeed);
	}

    private void Update()
    {
        // Rotate the object around the Y-axis
        transform.Rotate(Vector3.up * rotationSpeed * Time.deltaTime);
    }
}
