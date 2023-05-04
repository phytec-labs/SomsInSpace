using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UIElements;

public class StartSceneScript : MonoBehaviour
{
	public UIDocument uiDocument;
	private Button quitButton;
	private Button startButton;
	
	// Start is called before the first frame update
	void Start()
	{
		// Get the root VisualElement from the UI Document
		VisualElement root = uiDocument.rootVisualElement;
		
		// assign our buttons
		startButton = root.Q<Button>("startButton");
		quitButton = root.Q<Button>("quitButton");

		// Add a click event listener to the button
		startButton.clicked += OnStartButtonClicked;
		quitButton.clicked += OnQuitButtonClicked;
	}

	private void OnStartButtonClicked()
	{
		// Start the game by loading scene indexed at 1
		UnityEngine.SceneManagement.SceneManager.LoadScene(1);
	}

	private void OnQuitButtonClicked()
	{
			Application.Quit();
	}
}
