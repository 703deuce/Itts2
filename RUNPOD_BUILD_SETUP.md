# RunPod Serverless Build Setup with GitHub

## Problem

When RunPod automatically builds from GitHub, it needs access to your `HF_TOKEN` to pre-download models during the Docker build. The `--build-arg HF_TOKEN=...` flag won't work automatically.

## Solution: Use GitHub Secrets

### Step 1: Add HF_TOKEN as GitHub Secret

1. Go to your GitHub repository: `https://github.com/703deuce/Itts2`
2. Click **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret**
4. Name: `HF_TOKEN`
5. Value: Your HuggingFace token (e.g., `hf_your_token_here`)
6. Click **Add secret**

### Step 2: Configure RunPod Build

RunPod has two ways to build from GitHub:

#### Option A: RunPod's Native GitHub Integration

If RunPod has a "Build from GitHub" feature in their UI:

1. Go to RunPod Dashboard → Serverless → Create Endpoint
2. Select **"Build from GitHub"** or **"Connect GitHub Repository"**
3. Select your repository: `703deuce/Itts2`
4. In **Build Settings**, look for **"Build Arguments"** or **"Environment Variables"**
5. Add build argument:
   - Name: `HF_TOKEN`
   - Value: `${{ secrets.HF_TOKEN }}` (if supported) OR your actual token
   
   **Note**: If RunPod doesn't support GitHub Secrets directly, you may need to:
   - Use GitHub Actions to build and push (see Option B)
   - Or manually enter your HF_TOKEN in RunPod's UI (less secure)

#### Option B: Use GitHub Actions (Recommended)

Use the provided `.github/workflows/runpod-build.yml` workflow:

1. **Add GitHub Secrets** (as described in Step 1):
   - `HF_TOKEN` - Your HuggingFace token
   - `RUNPOD_USERNAME` - Your RunPod username (optional, if using RunPod registry)
   - `RUNPOD_PASSWORD` - Your RunPod API token (optional, if using RunPod registry)

2. **Push to GitHub** - The workflow will automatically:
   - Build the Docker image with `HF_TOKEN` build arg
   - Pre-download all models during build
   - Push to RunPod registry (or your preferred registry)

3. **Use the built image in RunPod**:
   - Image: `registry.runpod.io/your-username/indextts2-serverless:latest`
   - Or: `your-registry/indextts2-serverless:latest`

### Step 3: Verify Build

Check the GitHub Actions logs to ensure:
- ✅ Models are being downloaded (look for "Pre-downloading..." messages)
- ✅ FSTs are being built (look for "Pre-building WeText FSTs...")
- ✅ Build completes successfully

## Alternative: Build Locally and Push

If RunPod's GitHub integration doesn't support build args:

```bash
# 1. Build locally with HF_TOKEN
docker build --build-arg HF_TOKEN=your_token_here -t indextts2-serverless .

# 2. Tag for your registry
docker tag indextts2-serverless:latest registry.runpod.io/your-username/indextts2-serverless:latest

# 3. Login to RunPod registry
docker login registry.runpod.io

# 4. Push
docker push registry.runpod.io/your-username/indextts2-serverless:latest
```

Then use this image in RunPod.

## Troubleshooting

### Models Not Pre-downloaded

If you see runtime downloads in logs:
- Check GitHub Actions build logs for download errors
- Verify `HF_TOKEN` secret is set correctly
- Check if models are actually in the image: `docker run --rm your-image ls -lh /workspace/checkpoints`

### Build Fails with "HF_TOKEN not provided"

The Dockerfile will skip model downloads if `HF_TOKEN` is empty. This is expected if:
- You're building without the token (models should be in `checkpoints/` directory)
- You're using a volume mount for models

### RunPod Build Doesn't Support Build Args

If RunPod's GitHub integration doesn't support build arguments:
1. Use GitHub Actions to build and push (Option B above)
2. Or download models before committing and include them in the repo (not recommended - large files)
3. Or use a volume mount and download models at runtime (adds 10+ min cold start)

## Expected Results

After setup:
- ✅ Models pre-downloaded in Docker image
- ✅ FSTs pre-built
- ✅ Cold start: ~30 seconds (instead of 10 minutes)
- ✅ No runtime downloads

