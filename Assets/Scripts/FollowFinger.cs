using UnityEngine;
using UnityEngine.InputSystem;

// handles making the character follow 1 unit above the players finger touching the screen
public class FollowFinger : MonoBehaviour
{
	public bool allowInput = false;
	public float followSpeed = 5f; // The speed at which the GameObject follows the finger
	public float touchOffsetY = 1f;
	public InputActionAsset inputActions; // Reference to the Input Actions Asset

	public ParticleSystem rightParticleSystem;
	public ParticleSystem leftParticleSystem;
	public ParticleSystem downParticleSystem;

	private InputAction touchPositionAction;
	private Camera mainCamera;

	private GameStateMachine gameStateMachine;

	private Vector3 previousPosition;


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

		previousPosition = transform.position;

		//stop our pulseengine particle systems
		rightParticleSystem.Stop();
		leftParticleSystem.Stop();
		downParticleSystem.Stop();
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

			// Determine the movement direction
			Vector3 direction = (transform.position - previousPosition).normalized;

			// Update the left and right particle systems based on the movement direction
			if (direction.x > 0)
			{
				rightParticleSystem.Play();
				leftParticleSystem.Stop();
			}
			else if (direction.x < 0)
			{
				rightParticleSystem.Stop();
				leftParticleSystem.Play();
			}

			// Update the down particle systems based on the movement direction
			if (direction.y < 0)
			{
				downParticleSystem.Play();
			}
			else
			{
				downParticleSystem.Stop();
			}

			// Update the previous position
			previousPosition = transform.position;
		}
		else
		{
			//stop our pulseengine particle systems
			rightParticleSystem.Stop();
			leftParticleSystem.Stop();
			downParticleSystem.Stop();
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
