# Local Build Instructions (Recommended for Large Models)

If GitHub Actions continues to run out of disk space (14GB limit), build locally and push directly to your registry.

## Quick Start

```bash
# 1. Build the image locally (no disk limits)
docker build --build-arg HF_TOKEN=your_huggingface_token_here -t indextts2-serverless .

# 2. Test the image locally
docker run --gpus all indextts2-serverless python3 -c "from indextts.inferv2 import IndexTTS2; print('✅ Models loaded successfully')"

# 3. Tag for RunPod registry
docker tag indextts2-serverless registry.runpod.io/YOUR_USERNAME/indextts2-serverless:latest

# 4. Login to RunPod registry
docker login registry.runpod.io
# Username: your_runpod_username
# Password: your_runpod_api_key (get from https://www.runpod.io/console/user/settings)

# 5. Push to RunPod
docker push registry.runpod.io/YOUR_USERNAME/indextts2-serverless:latest
```

## Alternative: Push to Docker Hub

```bash
# 1. Build
docker build --build-arg HF_TOKEN=your_token -t YOUR_DOCKERHUB_USERNAME/indextts2-serverless:latest .

# 2. Login to Docker Hub
docker login

# 3. Push
docker push YOUR_DOCKERHUB_USERNAME/indextts2-serverless:latest
```

## Benefits of Local Build

- ✅ **No disk space limits** (your machine has more space)
- ✅ **Faster builds** (no GitHub Actions queue)
- ✅ **Full control** over the build process
- ✅ **Models pre-baked** into image (30s cold starts)
- ✅ **One-time setup** - push once, use forever

## After Pushing

1. Go to RunPod Console → Serverless → Your Endpoint
2. Update the Docker image to: `registry.runpod.io/YOUR_USERNAME/indextts2-serverless:latest`
3. Deploy - models are already baked in!

## Troubleshooting

**"No space left on device" during local build:**
```bash
# Clean up Docker
docker system prune -af --volumes
docker builder prune -af
```

**Build takes too long:**
- First build downloads ~10GB of models (30-60 minutes)
- Subsequent builds are faster (cached layers)

**Models not found at runtime:**
- Make sure `HF_TOKEN` was provided during build
- Check that models are in `/workspace/checkpoints/` in the image

