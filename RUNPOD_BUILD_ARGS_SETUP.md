# Configure RunPod Build Arguments for HF_TOKEN

Since RunPod automatically rebuilds from GitHub, you need to configure it to pass the `HF_TOKEN` build argument.

## Step 1: Find Your RunPod Endpoint/Template

1. Go to **RunPod Dashboard**: https://www.runpod.io/console
2. Navigate to **Serverless** → **Endpoints** (or **Templates**)
3. Find your endpoint that's connected to GitHub: `703deuce/Itts2`

## Step 2: Configure Build Arguments

RunPod's UI varies, but look for one of these sections:

### Option A: Build Settings / Advanced Settings

1. Click on your endpoint/template
2. Look for **"Build Settings"**, **"Advanced Settings"**, or **"Build Configuration"**
3. Find **"Build Arguments"**, **"Docker Build Args"**, or **"Build-time Variables"**
4. Add a new build argument:
   - **Name**: `HF_TOKEN`
   - **Value**: Your HuggingFace token (e.g., `hf_your_token_here`)

### Option B: Environment Variables (if build args not available)

Some RunPod setups use environment variables that get passed as build args:

1. Go to **"Environment Variables"** or **"Container Environment"**
2. Add:
   - **Name**: `HF_TOKEN`
   - **Value**: Your HuggingFace token
   - **Type**: Build-time (if available)

### Option C: Edit Template/Endpoint JSON/YAML

If RunPod has a JSON/YAML editor:

```json
{
  "buildArgs": {
    "HF_TOKEN": "your_huggingface_token_here"
  }
}
```

## Step 3: Verify Build Logs

After pushing to GitHub, check RunPod's build logs:

1. Go to your endpoint → **Build History** or **Build Logs**
2. Look for these messages:
   - ✅ `>> Pre-downloading IndexTTS-2 models (includes qwen0.6b-emo4-merge)...`
   - ✅ `>> Pre-downloading MaskGCT semantic codec...`
   - ✅ `>> Pre-downloading campplus speaker encoder...`
   - ✅ `>> Pre-downloading BigVGAN vocoder...`
   - ✅ `>> Pre-downloading w2v-bert-2.0 semantic model...`
   - ✅ `>> All models pre-downloaded successfully`
   - ✅ `>> Pre-building WeText FSTs...`

If you see:
- ❌ `>> HF_TOKEN not provided - models should be in checkpoints/ directory`
- ❌ Models downloading at runtime (in container logs)

Then the build arg wasn't passed correctly.

## Alternative: Use GitHub Actions Instead

If RunPod doesn't support build arguments, use GitHub Actions to build and push:

1. The workflow `.github/workflows/docker-publish.yml` will build with `HF_TOKEN`
2. It pushes to a registry (if you add credentials)
3. Then point RunPod to use that pre-built image instead of building from GitHub

## Security Note

⚠️ **Important**: If you enter your HF_TOKEN directly in RunPod's UI, it will be stored in RunPod's system. Consider:
- Using a read-only HuggingFace token (if possible)
- Or using GitHub Actions to build and push (token stays in GitHub Secrets)

## Troubleshooting

### Build Arg Not Working

If RunPod doesn't support build arguments:
1. **Use GitHub Actions** (recommended) - Build in GitHub Actions and push to registry
2. **Use Volume Mount** - Download models to a RunPod volume, mount at `/workspace/checkpoints`
3. **Runtime Download** - Let models download at container startup (adds 10+ min cold start)

### Can't Find Build Settings

RunPod's UI changes frequently. Try:
- Looking for **"Advanced"** or **"Configuration"** tabs
- Checking **"Template Settings"** if using templates
- Contacting RunPod support for build args configuration
- Using RunPod's API to set build args programmatically

