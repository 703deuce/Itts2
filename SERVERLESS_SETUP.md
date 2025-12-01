# RunPod Serverless Setup Guide

## Overview

This setup is configured for RunPod serverless endpoints with automatic model handling.

## Model Download Strategy

The entrypoint script (`entrypoint.sh`) automatically handles models in this order:

1. **Check if models exist** - If models are already in `/workspace/checkpoints/`, skip download
2. **Try to download** - If models are missing, attempt download using HuggingFace CLI or ModelScope
3. **Fail fast** - If models can't be downloaded, exit with error (prevents slow cold starts)

## Recommended Approach: Bake Models into Image

For **production serverless endpoints**, download models **before building** the Docker image:

```bash
# 1. Install download tool
uv tool install "huggingface-hub[cli,hf_xet]"

# 2. Download models
hf download IndexTeam/IndexTTS-2 --local-dir=checkpoints

# 3. Verify models are present
ls -lh checkpoints/
# Should see: config.yaml, gpt.pth, s2mel.pth, etc.

# 4. Build Docker image (models will be included)
docker build -t indextts2-serverless .
```

**Benefits:**
- ✅ Fast cold starts (no model download delay)
- ✅ Reliable (models always available)
- ✅ No network dependency at runtime

**Drawbacks:**
- ❌ Larger Docker image (~10GB+)
- ❌ Longer build time

## Alternative: Runtime Download (Not Recommended)

The entrypoint script can download models at container startup, but:

- ⚠️ Adds 10+ minutes to cold start time
- ⚠️ Requires network access
- ⚠️ May fail if HuggingFace/ModelScope is slow or unavailable
- ⚠️ Uses bandwidth on every cold start

This is only useful for:
- Development/testing
- When you can't bake models into the image
- When using RunPod volumes (models persist across restarts)

## RunPod Configuration

When creating your serverless endpoint:

1. **Container Image**: Your Docker image with models baked in
2. **Container Disk**: 20GB+ (if models are in image) or mount a volume
3. **GPU**: RTX 3090, A40, or similar (8GB+ VRAM recommended)
4. **Max Workers**: 1-2 (adjust based on GPU memory)
5. **Timeout**: 300 seconds (5 minutes) - adjust based on your needs
6. **Environment Variables** (optional):
   - `HF_ENDPOINT=https://hf-mirror.com` - Use mirror if HuggingFace is slow

## Volume Mount Option

If you prefer to keep models separate from the image:

1. Create a RunPod volume with models
2. Mount it at `/workspace/checkpoints` in endpoint settings
3. The entrypoint script will detect models and skip download

## Verification

After deployment, check the logs to verify:

```
>> Starting IndexTTS2 RunPod Serverless Endpoint...
>> Models found in /workspace/checkpoints, skipping download.
>> Models verified. Starting handler...
>> Starting RunPod serverless handler for IndexTTS2...
```

If you see download messages, models weren't baked into the image.

## Troubleshooting

### Models Not Found Error

If you see:
```
>> ERROR: config.yaml not found in /workspace/checkpoints
```

**Solution**: Download models before building, or mount a volume with models.

### Slow Cold Starts

If cold starts take 10+ minutes:
- Models are being downloaded at runtime
- **Fix**: Bake models into the Docker image before building

### Out of Memory

If you see CUDA OOM errors:
- Use a GPU with more VRAM
- Reduce `max_text_tokens_per_segment` in requests
- FP16 is already enabled (uses less VRAM)

## Summary

✅ **For Production**: Download models before building Docker image  
✅ **Entrypoint script**: Automatically handles model detection/download  
✅ **Fail fast**: Exits if models are missing (prevents slow cold starts)  
✅ **Flexible**: Supports baked-in models, volumes, or runtime download

