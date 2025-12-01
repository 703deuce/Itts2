# IndexTTS2 RunPod Serverless Endpoint

This directory contains the necessary files to deploy IndexTTS2 as a RunPod serverless API endpoint.

## Files

- `handler.py` - RunPod serverless handler that processes TTS requests
- `Dockerfile` - Docker image definition for the serverless endpoint
- `requirements-serverless.txt` - Additional dependencies for serverless deployment
- `.dockerignore` - Files to exclude from Docker build

## Setup Instructions

### 1. Prerequisites

- RunPod account
- Docker (for local testing)
- Git LFS installed

### 2. Model Download

For RunPod serverless endpoints, you have **three options** for handling models:

#### Option 1: Download Models Before Building (Recommended)
This bakes the models into the Docker image, eliminating cold start delays:

```bash
# Using HuggingFace CLI
uv tool install "huggingface-hub[cli,hf_xet]"
hf download IndexTeam/IndexTTS-2 --local-dir=checkpoints

# Or using ModelScope
uv tool install "modelscope"
modelscope download --model IndexTeam/IndexTTS-2 --local_dir checkpoints
```

Then build the Docker image. The models will be included in the image.

#### Option 2: Download Models at Container Startup
The entrypoint script will automatically download models if they're not present. However, this adds significant cold start time (models are ~10GB+), so this is **not recommended** for production.

#### Option 3: Mount Models as Volume in RunPod
In RunPod endpoint settings, you can mount a volume containing the models. This is useful if you want to update models without rebuilding the image.

**Important**: For production serverless endpoints, **Option 1 is strongly recommended** to avoid long cold starts.

### 3. Building the Docker Image

```bash
docker build -t indextts2-serverless .
```

### 4. Deploying to RunPod

1. Push your Docker image to a container registry (Docker Hub, GitHub Container Registry, etc.)
2. In RunPod, create a new serverless endpoint
3. Use your Docker image
4. Configure the endpoint settings:
   - **Container Disk**: At least 20GB (for models)
   - **GPU**: Recommended GPU with at least 8GB VRAM
   - **Max Workers**: Adjust based on your needs

### 5. API Usage

#### Request Format

```json
{
  "input": {
    "text": "Text to synthesize",
    "spk_audio_prompt": "base64_encoded_audio_or_url",
    "emo_audio_prompt": "base64_encoded_audio_or_url (optional)",
    "emo_alpha": 1.0,
    "emo_vector": [0, 0, 0, 0, 0, 0, 0, 0],
    "use_emo_text": false,
    "emo_text": "emotion description",
    "use_random": false,
    "interval_silence": 200,
    "max_text_tokens_per_segment": 120,
    "verbose": false
  }
}
```

#### Response Format

Success:
```json
{
  "audio": "base64_encoded_audio",
  "sample_rate": 24000,
  "format": "wav"
}
```

Error:
```json
{
  "error": "error message",
  "traceback": "optional traceback"
}
```

#### Example Request (Python)

```python
import requests
import base64

# Read audio file
with open("speaker_voice.wav", "rb") as f:
    audio_data = f.read()
    audio_base64 = base64.b64encode(audio_data).decode('utf-8')

# Prepare request
payload = {
    "input": {
        "text": "Hello, this is a test of the IndexTTS2 serverless endpoint.",
        "spk_audio_prompt": audio_base64,
        "use_emo_text": True,
        "emo_alpha": 0.6
    }
}

# Send request
response = requests.post(
    "https://api.runpod.ai/v2/YOUR_ENDPOINT_ID/run",
    headers={
        "Authorization": "Bearer YOUR_API_KEY",
        "Content-Type": "application/json"
    },
    json=payload
)

# Get job ID
job_id = response.json()["id"]

# Poll for result
import time
while True:
    status_response = requests.get(
        f"https://api.runpod.ai/v2/YOUR_ENDPOINT_ID/status/{job_id}",
        headers={"Authorization": "Bearer YOUR_API_KEY"}
    )
    status = status_response.json()
    
    if status["status"] == "COMPLETED":
        # Decode audio
        result = status["output"]
        if "error" in result:
            print("Error:", result["error"])
            break
        audio_base64 = result["audio"]
        audio_data = base64.b64decode(audio_base64)
        with open("output.wav", "wb") as f:
            f.write(audio_data)
        print("Audio saved to output.wav")
        break
    elif status["status"] == "FAILED":
        print("Job failed:", status.get("error"))
        break
    
    time.sleep(1)
```

## Parameters

### Required Parameters

- `text` (string): The text to synthesize into speech
- `spk_audio_prompt` (string): Speaker voice reference. Can be:
  - Base64 encoded audio string
  - URL to audio file (http:// or https://)
  - Data URI (data:audio/wav;base64,...)

### Optional Parameters

- `emo_audio_prompt` (string): Emotional reference audio (same formats as spk_audio_prompt)
- `emo_alpha` (float): Emotion influence strength (0.0-1.0, default: 1.0)
- `emo_vector` (array): 8-element array of emotion intensities [happy, angry, sad, afraid, disgusted, melancholic, surprised, calm]
- `use_emo_text` (bool): Use text-based emotion detection (default: false)
- `emo_text` (string): Text description for emotion (used when use_emo_text=true)
- `use_random` (bool): Enable random sampling (default: false)
- `interval_silence` (int): Silence interval between segments in milliseconds (default: 200)
- `max_text_tokens_per_segment` (int): Maximum tokens per text segment (default: 120)
- `verbose` (bool): Enable verbose logging (default: false)

## Notes

- The model is initialized once at startup to improve response times
- FP16 inference is enabled by default for lower VRAM usage
- Audio files are processed in temporary directories and cleaned up after each request
- The endpoint returns audio as base64-encoded WAV files at 24kHz sample rate

## Troubleshooting

### Model Not Found

Ensure that model checkpoints are available in the `checkpoints/` directory. You can:
- Download models before building the Docker image
- Mount a volume with models in RunPod
- Download models during container startup (modify Dockerfile)

### Out of Memory

- Reduce `max_text_tokens_per_segment` to process shorter segments
- Ensure GPU has sufficient VRAM (8GB+ recommended)
- Consider using a larger GPU instance

### Slow Inference

- The first request may be slower due to model warmup
- Consider using DeepSpeed (may require Dockerfile modifications)
- Ensure CUDA kernels are properly installed

## License

See the main repository LICENSE file for licensing information.

