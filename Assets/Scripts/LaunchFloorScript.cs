using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class LaunchFloorScript : MonoBehaviour
{
	public bool launch = false;

	public float initialSpeed = 0f;
	public float acceleration = 10f; // Rate of acceleration in units/s²
	public float maxSpeed = 100f; // Maximum speed the rocket can reach

	private Rigidbody2D rb; // The Rigidbody component attached to the GameObject

	public float maxTravelDistance = 15f;
	private Vector3 initialPosition;

	private GameStateMachine gameStateMachine;

	private void Awake()
	{
		// Get the Rigidbody component of the GameObject
		rb = GetComponent<Rigidbody2D>();
	}

	// Start is called before the first frame update
	void Start()
	{
		initialPosition = transform.position;

		GameObject[] gameStateMachineGameObject = GameObject.FindGameObjectsWithTag("GameStateController");
		gameStateMachine = gameStateMachineGameObject[0].GetComponent<GameStateMachine>();

		if (gameStateMachine != null)
		{
			gameStateMachine.OnGameStateChanged += HandleGameStateChanged;
		}
	}

	private void FixedUpdate()
	{
		if (launch)
		{
			// Make sure the Rigidbody component is attached
			if (rb == null)
			{
				Debug.LogError("RocketAcceleration requires a Rigidbody component.");
				return;
			}

			// Apply acceleration if the current speed is less than the maximum speed
			if (rb.velocity.magnitude < maxSpeed)
			{
				Vector2 forceDirection = transform.up * -1; // Assuming the rocket moves in the local up direction
				rb.AddForce(forceDirection * acceleration, ForceMode2D.Force);
			}

			// Check if the object has traveled the maximum allowed distance and destroy it if it has
			if (Vector3.Distance(initialPosition, transform.position) >= maxTravelDistance)
			{
				Destroy(gameObject);
			}
		}
	}

	private void HandleGameStateChanged(GameState newState)
	{
		// Change the behavior based on the new game state
		switch (newState)
		{
			case GameState.Ignition:
				launch = true;
				break;
		}
	}
}
