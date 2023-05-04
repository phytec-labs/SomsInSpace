using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class RotateGameObject : MonoBehaviour
{
	public float rotationSpeedMin = 2f; // adjust this to set the rotation speed
	public float rotationSpeedMax = 1f;
	
	private float rotationSpeed;
	private bool rotationCalculated = false;

	public void Start()
	{
		rotationSpeed = Random.Range(rotationSpeedMin, rotationSpeedMax);

		if ((Random.Range(0, 2) == 0))
			rotationSpeed = -1 * rotationSpeed;

		rotationCalculated = true;
	}

	void Update()
	{
		if (rotationCalculated)
			transform.Rotate(0, 0, rotationSpeed * Time.deltaTime);
	}

	public void CalcRange()
	{
		rotationSpeed = Random.Range(rotationSpeedMin, rotationSpeedMax);

		if ((Random.Range(0, 2) == 0))
			rotationSpeed = -1 * rotationSpeed;

		rotationCalculated = true;
	}
}
