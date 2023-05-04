using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.InputSystem;

// handles making the character follow 1 unit above the players finger touching the screen
public class FollowFinger : MonoBehaviour
{
	public bool allowInput = false;
	public float followSpeed = 5f; // The speed at which the GameObject follows the finger
	public float touchOffsetY = 1f;
	public InputActionAsset inputActions; // Reference to the Input Actions Asset

	private InputAction touchPositionAction;
	private Camera mainCamera;

	private GameStateMachine gameStateMachine;

	private void Awake()
	{
		// Get the TouchControls action map and TouchPosition action from the Input Actions Asset
		var touchControls = inputActions.FindActionMap("TouchControls");
		touchPositionAction = touchControls.FindAction("TouchPosition");
	}

	private void Start()
	{
		mainCamera = Camera.main;

		GameObject[] gameStateMachineGameObject = GameObject.FindGameObjectsWithTag("GameStateController");
		gameStateMachine = gameStateMachineGameObject[0].GetComponent<GameStateMachine>();

		if (gameStateMachine != null)
		{
			gameStateMachine.OnGameStateChanged += HandleGameStateChanged;
		}
	}

	private void OnEnable()
	{
		touchPositionAction.Enable();
	}

	private void OnDisable()
	{
		touchPositionAction.Disable();
	}

	private void Update()
	{
		if (touchPositionAction.triggered && allowInput)
		{
			// Convert the touch position from screen space to world space
			Vector2 touchPosition = touchPositionAction.ReadValue<Vector2>();
			Vector3 touchWorldPosition = mainCamera.ScreenToWorldPoint(touchPosition);
			touchWorldPosition.z = transform.position.z; // Preserve the original z-position of the GameObject
			touchWorldPosition.y = touchWorldPosition.y + touchOffsetY; // Preserve the original z-position of the GameObject

			// Smoothly move the GameObject towards the touch position
			transform.position = Vector3.Lerp(transform.position, touchWorldPosition, followSpeed * Time.deltaTime);
		}
	}

	private void HandleGameStateChanged(GameState newState)
	{
		// Change the behavior based on the new game state
		switch (newState)
		{
			case GameState.Ignition:
				allowInput = true;
				break;

			case GameState.Pause:
				allowInput = false;
				break;

			case GameState.PlayerDied:
				allowInput = false;
				break;
		}
	}
}
