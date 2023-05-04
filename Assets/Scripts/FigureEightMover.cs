using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class FigureEightMover : MonoBehaviour
{
    public float speed = 1.0f;
    public float scaleX = 1.0f;
    public float scaleY = 1.0f;

    private float timeElapsed;
    private Vector2 previousPosition;
    private Vector2 startPosition;

    void Start()
    {
        timeElapsed = 0.0f;
        previousPosition = transform.position;
        startPosition = transform.position;
    }

    void Update()
    {
        timeElapsed += Time.deltaTime * speed;

        float x = scaleX * Mathf.Sin(timeElapsed);
        float y = scaleY * Mathf.Sin(timeElapsed) * Mathf.Cos(timeElapsed);

        Vector2 offset = new Vector2(x, y);
        Vector2 newPosition = startPosition + offset;
        transform.position = newPosition;

        RotateToFaceDirection(newPosition - previousPosition);
        previousPosition = newPosition;
    }

    private void RotateToFaceDirection(Vector2 direction)
    {
        float angle = Mathf.Atan2(direction.y, direction.x) * Mathf.Rad2Deg;
        transform.rotation = Quaternion.Euler(0, 0, angle);
    }
}
