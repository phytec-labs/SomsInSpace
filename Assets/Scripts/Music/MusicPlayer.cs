using UnityEngine;
using UnityEngine.SceneManagement;

public class MusicPlayer : MonoBehaviour
{
    public AudioClip musicClip; // Assign your music clip in the Inspector
    public bool playOnStart = true; // Set this to true if you want the music to play when the level starts
    public float volume = 1f; // Volume of the music

    private AudioSource audioSource;
    private static MusicPlayer instance;

    private void Awake()
    {
        if (instance == null)
        {
            instance = this;
            DontDestroyOnLoad(gameObject);

            audioSource = gameObject.AddComponent<AudioSource>();
            audioSource.clip = musicClip;
            audioSource.loop = true; // Set the audio source to loop the music
            audioSource.volume = volume;
        }
        else
        {
            Destroy(gameObject);
        }
    }

    private void Start()
    {
        if (playOnStart)
        {
            PlayMusic();
        }
    }

    public void PlayMusic()
    {
        if (!audioSource.isPlaying)
        {
            audioSource.Play();
        }
    }

    public void StopMusic()
    {
        if (audioSource.isPlaying)
        {
            audioSource.Stop();
        }
    }
}
