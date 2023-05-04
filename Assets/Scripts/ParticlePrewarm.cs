using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class ParticlePrewarm : MonoBehaviour
{
	public new ParticleSystem particleSystem;
	public float prewarmDuration = 15f; // The desired duration for prewarming

	private GameStateMachine gameStateMachine;

	private void Start()
	{
		GameObject[] gameStateMachineGameObject = GameObject.FindGameObjectsWithTag("GameStateController");
		gameStateMachine = gameStateMachineGameObject[0].GetComponent<GameStateMachine>();

		gameStateMachine.OnGameStateChanged += HandleGameStateChanged;

		particleSystem = GetComponent<ParticleSystem>();

		// Stop the particle system before modifying its properties
		particleSystem.Stop();

		// Get the main module of the particle system
		ParticleSystem.MainModule mainModule = particleSystem.main;

		// Set the particle system duration to the desired prewarm duration
		mainModule.duration = prewarmDuration;

		// Enable prewarming
		mainModule.prewarm = true;

		// Play the particle system
		particleSystem.Play();
		particleSystem.Pause();
	}

	private void HandleGameStateChanged(GameState newState)
	{
		// Change the behavior based on the new game state
		switch (newState)
		{
			case GameState.Ignition:
				particleSystem.Play();
				break;
		}
	}
}
