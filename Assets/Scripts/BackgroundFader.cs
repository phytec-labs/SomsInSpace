using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class BackgroundFader : MonoBehaviour
{
	public Color startColor = new Color(0.53f, 0.81f, 0.92f, 1.0f);
	public Color endColor = new Color(0.0f, 0.0f, 0.0f, 1.0f);
	public float fadeDuration = 10.0f;
	public bool fadeEnabled = false;

	private MeshRenderer meshRenderer;
	private float elapsedTime;

	public GameStateMachine gameStateMachine;

	void Start()
	{
		meshRenderer = GetComponent<MeshRenderer>();
		elapsedTime = 0;

		GameObject[] gameStateMachineGameObject = GameObject.FindGameObjectsWithTag("GameStateController");
		gameStateMachine = gameStateMachineGameObject[0].GetComponent<GameStateMachine>();

		gameStateMachine.OnGameStateChanged += HandleGameStateChanged;
	}

	void Update()
	{
		elapsedTime += Time.deltaTime;
		float t = Mathf.Clamp01(elapsedTime / fadeDuration);

		Color currentColor = Color.Lerp(startColor, endColor, t);
		meshRenderer.material.color = currentColor;
	}

		private void HandleGameStateChanged(GameState newState)
	{
		// Change the behavior based on the new game state
		switch (newState)
		{
			case GameState.Ignition:
				fadeEnabled = true;
				break;
		}
	}
}
