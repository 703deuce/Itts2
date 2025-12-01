# Quick Start Guide for IndexTTS2 RunPod Serverless

## Prerequisites

1. **RunPod Account**: Sign up at https://www.runpod.io
2. **Docker**: For local testing (optional)
3. **Model Files**: Download IndexTTS-2 models

## Step 1: Download Models (Recommended Before Build)

**For RunPod Serverless, download models BEFORE building the Docker image** to avoid long cold starts:

```bash
# Option 1: Using HuggingFace CLI
uv tool install "huggingface-hub[cli,hf_xet]"
hf download IndexTeam/IndexTTS-2 --local-dir=checkpoints

# Option 2: Using ModelScope
uv tool install "modelscope"
modelscope download --model IndexTeam/IndexTTS-2 --local_dir checkpoints
```

**Important**: Ensure the `checkpoints/` directory contains:
- `config.yaml`
- `gpt.pth`
- `s2mel.pth`
- Other model files from IndexTTS-2

**Note**: The entrypoint script can download models at runtime if they're missing, but this adds significant cold start time (10+ minutes). For production, bake models into the image.

## Step 2: Build Docker Image

```bash
docker build -t indextts2-serverless:latest .
```

## Step 3: Test Locally (Optional)

```bash
# Run the container locally
docker run --gpus all -p 8000:8000 indextts2-serverless:latest
```

## Step 4: Push to Container Registry

```bash
# Tag for your registry
docker tag indextts2-serverless:latest your-registry/indextts2-serverless:latest

# Push to registry
docker push your-registry/indextts2-serverless:latest
```

## Step 5: Deploy to RunPod

1. Go to RunPod Dashboard → Serverless → Create Endpoint
2. Configure:
   - **Container Image**: `your-registry/indextts2-serverless:latest`
   - **Container Disk**: 20GB+ (for models)
   - **GPU Type**: RTX 3090, A40, or similar (8GB+ VRAM)
   - **Max Workers**: 1-2 (adjust based on GPU memory)
   - **Timeout**: 300 seconds (5 minutes)
3. Save and deploy

## Step 6: Test the Endpoint

Use the RunPod API or test from Python:

```python
import requests
import base64

# Your endpoint details
endpoint_id = "YOUR_ENDPOINT_ID"
api_key = "YOUR_API_KEY"

# Read speaker audio
with open("speaker.wav", "rb") as f:
    audio_base64 = base64.b64encode(f.read()).decode('utf-8')

# Create request
payload = {
    "input": {
        "text": "Hello from IndexTTS2!",
        "spk_audio_prompt": audio_base64,
        "use_emo_text": True
    }
}

# Send request
response = requests.post(
    f"https://api.runpod.ai/v2/{endpoint_id}/run",
    headers={
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json"
    },
    json=payload
)

job_id = response.json()["id"]
print(f"Job ID: {job_id}")

# Poll for result
import time
while True:
    status = requests.get(
        f"https://api.runpod.ai/v2/{endpoint_id}/status/{job_id}",
        headers={"Authorization": f"Bearer {api_key}"}
    ).json()
    
    if status["status"] == "COMPLETED":
        result = status["output"]
        if "error" in result:
            print("Error:", result["error"])
        else:
            # Save audio
            audio_data = base64.b64decode(result["audio"])
            with open("output.wav", "wb") as f:
                f.write(audio_data)
            print("Audio saved to output.wav")
        break
    elif status["status"] == "FAILED":
        print("Job failed")
        break
    
    time.sleep(2)
```

## Troubleshooting

### Models Not Found
- Ensure models are in `checkpoints/` directory before building
- Or mount a volume with models in RunPod settings

### Out of Memory
- Use a GPU with more VRAM
- Reduce `max_text_tokens_per_segment` in requests
- Enable FP16 (already enabled by default)

### Slow Inference
- First request is slower (model warmup)
- Consider using larger GPU instances
- Check CUDA availability in logs

## Next Steps

- See `README_SERVERLESS.md` for detailed API documentation
- Check RunPod logs for debugging
- Adjust GPU and worker settings based on usage

