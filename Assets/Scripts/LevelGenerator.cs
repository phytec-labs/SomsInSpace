using UnityEngine;
using System.Collections;
using System.Collections.Generic;

public class LevelGenerator : MonoBehaviour
{
	public GameObject Player;
	//Spawners send objects from the left and right side fo the scene
	public GameObject[] spawner1Prefab;
	public Transform spawner1Position;
	[Tooltip("The minimum number of tiles to be repeated before choosing another tile")]
	public int minSpawnBeforeFloorSwitch = 0;

	public GameObject[] spawner2Prefab;
	public Transform spawner2Position;
	[Tooltip("The minimum number of tiles to be repeated before choosing another tile")]
	public int minSpawnBeforeCeilingSwitch = 0;

	//debris spawns from the top of the scene
	public GameObject[] debrisTilePrefabs;
	public float debrisRandomOffset = 8;
	public Transform debrisSpawnPosition;

	//spawner init
	public float hSpeed = 5f;
	public float vSpeed = 5f;
	public int initialTileCount = 10;
	private GameObject spawnedFloorTile;
	private GameObject spawnedCeilingTile;
	private GameObject spawnedDebrisTile;

	public float maxTimeBetweenSpawn1 = 10f;
	public float maxTimeBetweenSpawn2 = 10f;
	[SerializeField] private float timeBetweenSpawn1 = 1f;
	[SerializeField] private float timeBetweenSpawn2 = 1f;
	[SerializeField] private float distanceBetweenDebris = 1f;

	[SerializeField] private float floorTileDiff = 1f;
	[SerializeField] private float ceilTileDiff = 1f;


	public float destroyDistance = 10f;
	public float maxRotationSpeed = 2f;
	public float minRotationSpeed = 1f;
	// public bool floorInitialized = false;

	private int rndIndexNum = 0;

	void Start()
	{
		// if (!floorInitialized)
		// {
		// 	InitializeFloor();
		// 	InitializeCeiling();
		// 	floorInitialized = true;
		// }

		spawnedFloorTile = GenerateScenery(spawner1Prefab[rndIndexNum], spawner1Position.position, false, true);
		spawnedCeilingTile = GenerateScenery(spawner2Prefab[rndIndexNum], spawner2Position.position, false, false);
		spawnedDebrisTile = GenerateDebris(debrisTilePrefabs[rndIndexNum], debrisSpawnPosition.position, true, false);
	}

	void FixedUpdate()
	{
		//calculate the distance the the last tile has moved

		//spawn floor tiles
		if (Mathf.Abs(spawnedFloorTile.transform.position.x - spawner1Position.transform.position.x) >= timeBetweenSpawn1)
		{
			spawnedFloorTile = GenerateScenery(spawner1Prefab[rndIndexNum], spawner1Position.position, true, true);
			timeBetweenSpawn1 = Random.Range(0, maxTimeBetweenSpawn1);
		}
		//spawn ceiling tiles
		if (Mathf.Abs(spawnedCeilingTile.transform.position.x - spawner2Position.transform.position.x) >= timeBetweenSpawn2)
		{
			spawnedCeilingTile = GenerateScenery(spawner2Prefab[rndIndexNum], spawner2Position.position, true, false);
			timeBetweenSpawn2 = Random.Range(0, maxTimeBetweenSpawn2);
		}
		//spawn debris
		if ((spawnedDebrisTile != null) && Mathf.Abs(spawnedDebrisTile.transform.position.x - debrisSpawnPosition.transform.position.x) >= distanceBetweenDebris)
		{
			spawnedDebrisTile = GenerateScenery(debrisTilePrefabs[rndIndexNum], debrisSpawnPosition.position, true, false);
		}
	}

	GameObject GenerateScenery(GameObject tileToGeneratePrefab, Vector3 spawnPosition, bool randomVerticalOffset, bool goLeft)
	{
		//takes in an object and a position for instatiation. A bool is used to determine if a ramdon offset should be applied and is used for sending debris.
		//returns the instantiated gameobject
		GameObject newTile;

		if (randomVerticalOffset)
			spawnPosition = new Vector3(spawnPosition.x, (spawnPosition.y + Random.Range((-1 * debrisRandomOffset), debrisRandomOffset)), spawnPosition.z);

		newTile = Instantiate(tileToGeneratePrefab, spawnPosition, Quaternion.identity);

		MoveTile newTileMoveTile = newTile.AddComponent<MoveTile>();
		newTileMoveTile.hSpeed = Random.Range(0.5f, hSpeed);
		newTileMoveTile.vSpeed = vSpeed;
		newTileMoveTile.Player = Player;
		newTileMoveTile.left = goLeft;

		DestroyOffscreen newTileFloorDestroyOffScreen = newTile.AddComponent<DestroyOffscreen>();
		newTileFloorDestroyOffScreen.destroyDistance = destroyDistance;
		newTileFloorDestroyOffScreen.Player = Player;

		return newTile;
	}

	GameObject GenerateDebris(GameObject objectToGeneratePrefab, Vector3 spawnPosition, bool randomVerticalOffset, bool goLeft)
	{
		//takes in an object and a position for instatiation. A bool is used to determine if a ramdon offset should be applied and is used for sending debris.
		//returns the instantiated gameobject
		GameObject newTile;

		if (randomVerticalOffset)
			spawnPosition = new Vector3(spawnPosition.x, (spawnPosition.y + Random.Range((-1 * debrisRandomOffset), debrisRandomOffset)), spawnPosition.z);

		newTile = Instantiate(objectToGeneratePrefab, spawnPosition, Quaternion.identity);

		MoveTile newTileMoveTile = newTile.AddComponent<MoveTile>();
		newTileMoveTile.hSpeed = Random.Range(0.5f, hSpeed);
		newTileMoveTile.vSpeed = vSpeed;
		newTileMoveTile.Player = Player;
		newTileMoveTile.left = goLeft;

		DestroyOffscreen newTileFloorDestroyOffScreen = newTile.AddComponent<DestroyOffscreen>();
		newTileFloorDestroyOffScreen.destroyDistance = destroyDistance;
		newTileFloorDestroyOffScreen.Player = Player;

		if (randomVerticalOffset)
		{
			RotateObject newTileRotator = newTile.AddComponent<RotateObject>();
			newTileRotator.maxRotationSpeed = maxRotationSpeed;
			newTileRotator.minRotationSpeed = minRotationSpeed;
			newTileRotator.CalcRange();
		}

		return newTile;
	}

	void InitializeFloor()
	{
		Vector3 initialPosition;
		for (int i = 0; i < initialTileCount; i++)
		{
			initialPosition = new Vector3(spawner1Position.position.x - (i * spawner1Prefab[0].GetComponent<BoxCollider2D>().size.x), spawner1Position.position.y, spawner1Position.position.z);
			spawnedFloorTile = GenerateScenery(spawner1Prefab[rndIndexNum], initialPosition, false, true);
		}
	}

	void InitializeCeiling()
	{
		Vector3 initialPosition;
		for (int i = 0; i < initialTileCount; i++)
		{
			initialPosition = new Vector3(spawner2Position.position.x - (i * spawner2Prefab[0].GetComponent<BoxCollider2D>().size.x), spawner2Position.position.y, spawner2Position.position.z);
			spawnedCeilingTile = GenerateScenery(spawner2Prefab[rndIndexNum], initialPosition, false, false);
		}
	}
}

/*** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***  ***/
/*** Additional Classes which are applied to instantiated objects ***/
/*** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***  ***/

public class MoveTile : MonoBehaviour
{
	public float hSpeed = 5f;
	public float vSpeed = 5f;
	public bool hMove = false;
	public bool left = true;
	public GameObject Player;

	void Update()
	{
		if (Player.GetComponent<PlayerControllerScript>().alive)
			if (left)
				transform.position += Vector3.left * hSpeed * Time.deltaTime;
			else
				transform.position += Vector3.right * hSpeed * Time.deltaTime;

		transform.position -= Vector3.up * vSpeed * Time.deltaTime;
	}
}

public class DestroyOffscreen : MonoBehaviour
{
	public float destroyDistance = 15f;
	public GameObject Player;
	public Vector3 spawnPosition;

	void Start()
	{
		spawnPosition = transform.position;
	}
	void Update()
	{
		if (Mathf.Abs(spawnPosition.x - transform.position.x) > destroyDistance && Player.GetComponent<PlayerControllerScript>().alive)
		{
			Destroy(gameObject);
		}
	}
}

public class RotateObject : MonoBehaviour
{
	public float maxRotationSpeed; // adjust this to set the rotation speed
	public float minRotationSpeed;
	public float rotationRange;
	public bool rangeCalculated = false;

	void Update()
	{
		if (rangeCalculated)
			transform.Rotate(0, 0, rotationRange * Time.deltaTime);
	}

	public void CalcRange()
	{

		rotationRange = Random.Range(minRotationSpeed, maxRotationSpeed);

		if ((Random.Range(0, 2) == 0))
			rotationRange = -1 * rotationRange;

		rangeCalculated = true;
	}
}
