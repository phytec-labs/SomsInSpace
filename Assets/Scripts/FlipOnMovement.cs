using UnityEngine;

public class FlipOnMovement : MonoBehaviour
{
    public float positionThreshold = 0.001f; // The minimum position difference to consider as movement

    private Vector3 previousPosition;
    private bool isFacingRight = true;

    private void Start()
    {
        // Store the initial position
        previousPosition = transform.position;
    }

    private void Update()
    {
        // Calculate the difference in position
        float positionDifference = transform.position.x - previousPosition.x;

        // If moving right and not facing right, flip
        if (positionDifference > positionThreshold && !isFacingRight)
        {
            Flip();
        }
        // If moving left and facing right, flip
        else if (positionDifference < -positionThreshold && isFacingRight)
        {
            Flip();
        }

        // Store the current position for the next frame
        previousPosition = transform.position;
    }

    private void Flip()
    {
        // Toggle the 'isFacingRight' boolean
        isFacingRight = !isFacingRight;

        // Flip the GameObject by toggling the Y rotation between 0 and 180 degrees
        Vector3 currentRotation = transform.eulerAngles;
        currentRotation.y = isFacingRight ? 0f : 180f;
        transform.eulerAngles = currentRotation;
    }
}
