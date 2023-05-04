using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class ParticlePrewarm_StartScene : MonoBehaviour
{
	public new ParticleSystem particleSystem;
	public float prewarmDuration = 15f; // The desired duration for prewarming

	private ParticleSystem.MainModule mainModule;
	private ParticleSystem.Particle[] particles;
	private Vector3[] initialParticlePositions;

	private void Awake()
	{
		particleSystem = GetComponent<ParticleSystem>();
		mainModule = particleSystem.main;
	}

	private void Start()
	{

		// Stop the particle system before modifying its properties
		particleSystem.Stop();

		// Set the particle system duration to the desired prewarm duration
		mainModule.duration = prewarmDuration;

		// Enable prewarming
		mainModule.prewarm = true;

		// Play the particle system
		particleSystem.Play();

		// Set particle lifetime to infinite
		mainModule.startLifetime = Mathf.Infinity;

		// Disable movement
		mainModule.startSpeed = 0f;

		// Initialize particles array
		particles = new ParticleSystem.Particle[particleSystem.main.maxParticles];
		initialParticlePositions = new Vector3[particleSystem.main.maxParticles];

		// Get the initial positions of the particles
		int numParticles = particleSystem.GetParticles(particles);
		for (int i = 0; i < numParticles; i++)
		{
			initialParticlePositions[i] = particles[i].position;
		}
	}

	private void Update()
	{
		// Keep particles at their initial positions
		int numParticles = particleSystem.GetParticles(particles);
		for (int i = 0; i < numParticles; i++)
		{
			particles[i].position = initialParticlePositions[i];
		}
		particleSystem.SetParticles(particles, numParticles);
	}
}
