# RunPod GitHub Integration Setup

This guide explains how to configure RunPod to automatically build your Docker image from GitHub.

## ✅ Code Pushed to GitHub

Your code has been successfully pushed to: **https://github.com/703deuce/Itts2.git**

## RunPod GitHub Integration Steps

### Option 1: RunPod GitHub Integration (Recommended)

RunPod can automatically build Docker images from your GitHub repository:

1. **Go to RunPod Dashboard**
   - Navigate to https://www.runpod.io/console
   - Go to **Serverless** → **Templates** or **Endpoints**

2. **Create New Endpoint from GitHub**
   - Click **"Create Endpoint"** or **"New Template"**
   - Select **"Build from GitHub"** or **"GitHub Repository"**
   - Connect your GitHub account if not already connected
   - Select repository: `703deuce/Itts2`
   - Select branch: `main`

3. **Configure Build Settings**
   - **Dockerfile Path**: `Dockerfile` (root of repository)
   - **Build Context**: `.` (root directory)
   - **Image Name**: `indextts2-serverless` (or your preferred name)
   - **Registry**: Choose where to push (RunPod Registry, Docker Hub, etc.)

4. **Configure Endpoint Settings**
   - **Container Disk**: 20GB+ (if models are baked in) or mount volume
   - **GPU Type**: RTX 3090, A40, or similar (8GB+ VRAM)
   - **Max Workers**: 1-2
   - **Timeout**: 300 seconds (5 minutes)
   - **Environment Variables** (optional):
     - `HF_ENDPOINT=https://hf-mirror.com` (if HuggingFace is slow)

5. **Model Handling**
   - **Option A**: Models baked into image (recommended)
     - Download models before building (see below)
     - Models will be included in Docker image
   - **Option B**: Models in volume
     - Create RunPod volume with models
     - Mount at `/workspace/checkpoints`
   - **Option C**: Download at runtime
     - Entrypoint script will download (adds 10+ min cold start)

### Option 2: Manual Build and Push

If RunPod doesn't have GitHub integration, build manually:

1. **Build Docker Image Locally**
   ```bash
   # Download models first (recommended)
   uv tool install "huggingface-hub[cli,hf_xet]"
   hf download IndexTeam/IndexTTS-2 --local-dir=checkpoints
   
   # Build image
   docker build -t indextts2-serverless .
   ```

2. **Push to Container Registry**
   ```bash
   # Tag for your registry
   docker tag indextts2-serverless:latest your-registry/indextts2-serverless:latest
   
   # Push
   docker push your-registry/indextts2-serverless:latest
   ```

3. **Deploy to RunPod**
   - Create endpoint in RunPod
   - Use image: `your-registry/indextts2-serverless:latest`

## Downloading Models for Build

**Important**: For production, download models before building to avoid long cold starts.

### Using GitHub Actions (Recommended)

Create `.github/workflows/build-docker.yml`:

```yaml
name: Build Docker Image

on:
  push:
    branches: [ main ]
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3
      
      - name: Login to RunPod Registry
        uses: docker/login-action@v3
        with:
          registry: registry.runpod.io
          username: ${{ secrets.RUNPOD_USERNAME }}
          password: ${{ secrets.RUNPOD_PASSWORD }}
      
      - name: Download Models
        run: |
          pip install huggingface-hub[cli]
          huggingface-cli download IndexTeam/IndexTTS-2 --local-dir=checkpoints
      
      - name: Build and Push
        uses: docker/build-push-action@v5
        with:
          context: .
          file: ./Dockerfile
          push: true
          tags: registry.runpod.io/your-username/indextts2-serverless:latest
```

### Manual Download Before Build

```bash
# Install tool
uv tool install "huggingface-hub[cli,hf_xet]"

# Download models
hf download IndexTeam/IndexTTS-2 --local-dir=checkpoints

# Verify models
ls -lh checkpoints/
# Should see: config.yaml, gpt.pth, s2mel.pth, etc.
```

## RunPod Endpoint Configuration

When creating your serverless endpoint:

### Basic Settings
- **Name**: `indextts2-serverless` (or your choice)
- **Container Image**: Your built image
- **Container Disk**: 20GB+ (if models in image) or mount volume
- **GPU**: RTX 3090, A40, or similar (8GB+ VRAM recommended)
- **Max Workers**: 1-2 (adjust based on GPU memory)
- **Timeout**: 300 seconds (5 minutes)

### Advanced Settings
- **Environment Variables**:
  - `HF_ENDPOINT=https://hf-mirror.com` (optional, for faster downloads)
- **Volume Mounts** (if using volumes):
  - Mount path: `/workspace/checkpoints`
  - Your volume with models

## Testing the Endpoint

After deployment, test with:

```python
import requests
import base64

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

print(response.json())
```

## Troubleshooting

### Build Fails
- Check Dockerfile syntax
- Verify all dependencies in pyproject.toml
- Check RunPod build logs

### Models Not Found
- Ensure models are downloaded before build
- Or mount volume with models
- Check entrypoint.sh logs

### Slow Cold Starts
- Models are downloading at runtime
- **Fix**: Bake models into image before building

### Out of Memory
- Use GPU with more VRAM
- Reduce max workers
- FP16 is already enabled

## Next Steps

1. ✅ Code pushed to GitHub
2. ⏭️ Connect GitHub to RunPod
3. ⏭️ Configure build settings
4. ⏭️ Download models (or use volume)
5. ⏭️ Deploy endpoint
6. ⏭️ Test endpoint

## Resources

- [RunPod Documentation](https://docs.runpod.io/)
- [RunPod Serverless Guide](https://docs.runpod.io/serverless)
- [GitHub Repository](https://github.com/703deuce/Itts2)

