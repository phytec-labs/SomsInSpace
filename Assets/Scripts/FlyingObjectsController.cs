using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class FlyingObjectsController : MonoBehaviour
{
	public bool spawnerEnabled = false;
	public GameObject[] objectsToSpawn; // Array of GameObjects to spawn
	public Vector3 spawnOffsetRange; // Range of the random offset applied to the spawn position
	public float spawnIntervalMin = 1f; // Time interval between spawns
	public float spawnIntervalMax = 1f; // Time interval between spawns
	public float objectSpeed = 5f; // Speed of the spawned objects
	public float maxTravelDistance = 10f; // Maximum distance the spawned objects can travel before being destroyed
	public float downwardSpeed = 1f; // Downward speed for left and right options

	public GameStateMachine gameStateMachine;

	public enum MovementDirection
	{
		Left,
		Left_Down,
		Right,
		Right_Down,
		Down
	}

	public MovementDirection movementDirection; // Direction the spawned objects should move

	private void Start()
	{
		GameObject[] gameStateMachineGameObject = GameObject.FindGameObjectsWithTag("GameStateController");
		gameStateMachine = gameStateMachineGameObject[0].GetComponent<GameStateMachine>();

		gameStateMachine.OnGameStateChanged += HandleGameStateChanged;

		StartCoroutine(SpawnObjects());
	}

	private IEnumerator SpawnObjects()
	{
		while (true)
		{
			if (spawnerEnabled)
			{
				// Choose a random GameObject from the array
				GameObject objectToSpawn = objectsToSpawn[Random.Range(0, objectsToSpawn.Length)];

				// Apply a random offset to the spawn position
				Vector3 spawnPositionWithOffset = transform.position;
				spawnPositionWithOffset.x += Random.Range(-spawnOffsetRange.x, spawnOffsetRange.x);
				spawnPositionWithOffset.y += Random.Range(-spawnOffsetRange.y, spawnOffsetRange.y);
				spawnPositionWithOffset.z += Random.Range(-spawnOffsetRange.z, spawnOffsetRange.z);

				// Instantiate the GameObject
				GameObject spawnedObject = Instantiate(objectToSpawn, spawnPositionWithOffset, Quaternion.identity);

				// Assign the object's movement direction and max travel distance
				spawnedObject.AddComponent<ObjectMover>().Initialize(objectSpeed, movementDirection, maxTravelDistance, downwardSpeed);

				// Wait for the specified interval before spawning the next object
				yield return new WaitForSeconds(Random.Range(spawnIntervalMin, spawnIntervalMax));
			}
			else
			{
				// Add a small delay if spawnerEnabled is false
				yield return new WaitForSeconds(0.1f);
			}
		}
	}

	private void HandleGameStateChanged(GameState newState)
	{
		// Change the behavior based on the new game state
		switch (newState)
		{
			case GameState.Ignition:
				spawnerEnabled = true;
				break;
		}
	}
}

public class ObjectMover : MonoBehaviour
{
	private float speed;
	private FlyingObjectsController.MovementDirection movementDirection;
	private float maxTravelDistance;
	private Vector3 initialPosition;
	private float downwardSpeed;

	public void Initialize(float objectSpeed, FlyingObjectsController.MovementDirection direction, float travelDistance, float downSpeed)
	{
		speed = objectSpeed;
		movementDirection = direction;
		maxTravelDistance = travelDistance;
		downwardSpeed = downSpeed;
	}

	private void Start()
	{

		initialPosition = transform.position;

	}

	private void Update()
	{
		Vector3 moveDirection;

		switch (movementDirection)
		{
			case FlyingObjectsController.MovementDirection.Left:
				moveDirection = Vector3.left;
				break;
			case FlyingObjectsController.MovementDirection.Left_Down:
				moveDirection = Vector3.left + Vector3.down * downwardSpeed;
				break;
			case FlyingObjectsController.MovementDirection.Right:
				moveDirection = Vector3.right;
				break;
			case FlyingObjectsController.MovementDirection.Right_Down:
				moveDirection = Vector3.right + Vector3.down * downwardSpeed;
				break;
			case FlyingObjectsController.MovementDirection.Down:
				moveDirection = Vector3.down;
				break;
			default:
				moveDirection = Vector3.zero;
				break;
		}

		transform.position += moveDirection * speed * Time.deltaTime;

		// Check if the object has traveled the maximum allowed distance and destroy it if it has
		if (Vector3.Distance(initialPosition, transform.position) >= maxTravelDistance)
		{
			Destroy(gameObject);
		}
	}
}
