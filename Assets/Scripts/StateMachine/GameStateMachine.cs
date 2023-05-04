using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UIElements;

public enum GameState
{
	Countdown,
	Ignition,
	Launch,
	Atmosphere_Low,
	Atmosphere_Mid,
	Atmosphere_High,
	Space,
	Planet4,
	Planet5,
	Planet6,
	Planet7,
	Planet8,
	Planet9,
	Pause,
	PlayerDied
}

public class GameStateMachine : MonoBehaviour
{
	public GameState currentState;

	public UIDocument uiDocument;
	private Label countdownLabel;

	public float stateTimer; // Countdown timer variable

	public delegate void GameStateChangedHandler(GameState newState);
	public event GameStateChangedHandler OnGameStateChanged;

	private void Awake()
	{
		// Get the root VisualElement from the UI Document
		VisualElement root = uiDocument.rootVisualElement;

		// Find the label you want to update by its class name or ID
		countdownLabel = root.Q<Label>("CountdownTimer");
	}

	private void Update()
	{
		UpdateState();
	}

	private void EnterState(GameState newState)
	{
		// Perform any necessary cleanup for the previous state
		ExitState();

		currentState = newState;

		// Invoke the event when the state changes
		OnGameStateChanged?.Invoke(currentState);

		switch (currentState)
		{
			case GameState.Countdown:
				stateTimer = 3.0f; // Set the initial countdown time (e.g., 10 seconds)
				countdownLabel.style.display = DisplayStyle.Flex; // show the countdown text
				break;

			case GameState.Ignition:
				stateTimer = 3.0f; // Set the initial countdown time (e.g., 10 seconds)
				break;

			case GameState.Atmosphere_Low:
				break;

			case GameState.Atmosphere_Mid:
				break;

			case GameState.Atmosphere_High:
				break;

			case GameState.Space:
				break;

			case GameState.Planet4:
				break;

			case GameState.Planet5:
				break;

			case GameState.Planet6:
				break;

			case GameState.Planet7:
				break;

			case GameState.Planet8:
				break;

			case GameState.Planet9:
				break;

			case GameState.Pause:
				// Handle entering Pause state logic here.
				break;

			case GameState.PlayerDied:
				// Handle entering Pause state logic here.
				break;
		}
	}

	private void Start()
	{
		ChangeState(GameState.Countdown);
	}

	private void UpdateState()
	{
		switch (currentState)
		{
			case GameState.Countdown:
				stateTimer -= Time.deltaTime; // Decrement the timer
				countdownLabel.text = Mathf.CeilToInt(stateTimer).ToString(); // Update the UI text

				// Check if the countdown is finished and transition to the Ignition state
				if (stateTimer <= 0)
				{
					ChangeState(GameState.Ignition);
				}
				break;
		}
	}

	private void ExitState()
	{
		switch (currentState)
		{
			case GameState.Countdown:
				countdownLabel.style.display = DisplayStyle.None; // Hide the countdown text
				break;
		}
	}

	public void ChangeState(GameState newState)
	{
		EnterState(newState);
	}
}
