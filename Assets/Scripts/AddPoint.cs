using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class AddPoint : MonoBehaviour
{
	private void OnTriggerEnter2D(Collider2D other) {
		if (other.gameObject.tag == "Player")
		{
			other.gameObject.SendMessage("AddPoint", 1);
			Destroy(gameObject);
		}
	}
}
