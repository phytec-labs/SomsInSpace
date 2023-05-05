using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UIElements;

public class PlayerControllerScript : MonoBehaviour
{
	public bool alive { get; protected set; } = true;
	public int health = 1;
	public int points = 0;
	private Rigidbody2D rb;

	public UIDocument uiDocument;
	private Label pointsLabel;
	private Button restartButton;
	private Button quitButton;

	public ParticleSystem engineParticleSystem;

	public GameObject explosionPrefab;

	private GameStateMachine gameStateMachine;

	private void Awake()
	{
		rb = GetComponent<Rigidbody2D>();
		// Get the root VisualElement from the UI Document
		VisualElement root = uiDocument.rootVisualElement;

		// Find the label you want to update by its class name or ID
		pointsLabel = root.Q<Label>("PlayerPoints");
		restartButton = root.Q<Button>("RestartButton");
		quitButton = root.Q<Button>("QuitButton");

		// Add a click event listener to the button
		restartButton.clicked += OnRestartButtonClicked;
		quitButton.clicked += QuitApplication;

		//find our gamestatemachine
		GameObject[] gameStateMachineGameObject = GameObject.FindGameObjectsWithTag("GameStateController");
		gameStateMachine = gameStateMachineGameObject[0].GetComponent<GameStateMachine>();
		
		//attach our gamestatehandler
		gameStateMachine.OnGameStateChanged += HandleGameStateChanged;

		// Stop the particle system before modifying its properties
		engineParticleSystem.Stop();
	}

	public void AddPoint(int value)
	{
		points += value;
		pointsLabel.text = "Points: " + points;
	}

	public void ApplyDamage(int damage)
	{
		health -= damage;

		if (health <= 0)
		{
			OnPlayerDeath();
		}
	}

	void OnPlayerDeath()
	{
		alive = false;
		ShowRestartButton();
		UpdateGameState(GameState.PlayerDied);
		Instantiate(explosionPrefab, this.transform.position, Quaternion.identity);
		Destroy(gameObject);
	}

	public void ShowRestartButton()
	{
		if (restartButton != null)
		{
			restartButton.style.display = DisplayStyle.Flex;
			quitButton.style.display = DisplayStyle.Flex;
		}
	}

	public void QuitApplication()
	{
		// If the Android back button is pressed, quit the application
		Application.Quit();
	}

	private void OnRestartButtonClicked()
	{
		// Restart the game, e.g., reload the current scene
		UnityEngine.SceneManagement.SceneManager.LoadScene(UnityEngine.SceneManagement.SceneManager.GetActiveScene().buildIndex);
	}

	private void UpdateGameState(GameState newGameState)
	{
		gameStateMachine.ChangeState(newGameState);
	}

	private void HandleGameStateChanged(GameState newState)
	{
		// Change the behavior based on the new game state
		switch (newState)
		{
			case GameState.Ignition:
				engineParticleSystem.Play();
				break;
		}
	}
}
