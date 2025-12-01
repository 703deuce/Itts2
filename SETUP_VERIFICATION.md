# Setup Verification Checklist

This document verifies that the RunPod serverless setup aligns with IndexTTS2 documentation requirements.

## ✅ Dependency Management

- [x] **uv is used for all dependencies** - All dependencies are managed via `pyproject.toml` and installed with `uv sync --all-extras`
- [x] **runpod is included** - Added to `pyproject.toml` dependencies (line 59)
- [x] **No pip installs** - Dockerfile uses only `uv sync`, no separate pip installs

## ✅ Model Download

The setup supports model download via:

1. **Before Docker build** (Recommended):
   ```bash
   uv tool install "huggingface-hub[cli,hf_xet]"
   hf download IndexTeam/IndexTTS-2 --local-dir=checkpoints
   ```
   Then build Docker image with models already in place.

2. **During container startup** (Alternative):
   - Mount a volume with models in RunPod
   - Or download models in an entrypoint script

3. **Using ModelScope**:
   ```bash
   uv tool install "modelscope"
   modelscope download --model IndexTeam/IndexTTS-2 --local_dir checkpoints
   ```

## ✅ Environment Configuration

- [x] **PYTHONPATH** - Set in Dockerfile to include `/workspace` for module discovery
- [x] **HF_HUB_CACHE** - Set to `/workspace/checkpoints/hf_cache`
- [x] **HF_ENDPOINT** - Set in Dockerfile (can be overridden to use mirror: `https://hf-mirror.com`)
- [x] **CUDA** - CUDA 12.8 environment configured
- [x] **Virtual Environment** - PATH includes `.venv/bin` from uv

## ✅ Handler Configuration

- [x] **FP16 enabled** - Handler uses `use_fp16=True` (as recommended in docs)
- [x] **CUDA kernels** - Handler uses `use_cuda_kernel=True` for speed
- [x] **Model paths** - Correctly points to `checkpoints/config.yaml` and `checkpoints/` directory
- [x] **PYTHONPATH** - Handler adds current directory to sys.path for module discovery

## ✅ Code Execution

- [x] **Handler runs in uv environment** - PATH includes `.venv/bin`, so `python3` uses uv-managed environment
- [x] **Module imports** - Handler imports `from indextts.infer_v2 import IndexTTS2` correctly
- [x] **All features supported**:
  - Voice cloning (spk_audio_prompt)
  - Emotion control (emo_audio_prompt, emo_vector, use_emo_text)
  - All optional parameters

## 📋 Pre-Deployment Checklist

Before deploying to RunPod:

1. **Download Models**:
   ```bash
   uv tool install "huggingface-hub[cli,hf_xet]"
   hf download IndexTeam/IndexTTS-2 --local-dir=checkpoints
   ```
   Verify `checkpoints/` contains:
   - `config.yaml`
   - `gpt.pth`
   - `s2mel.pth`
   - Other model files

2. **Build Docker Image**:
   ```bash
   docker build -t indextts2-serverless .
   ```

3. **Test Locally** (Optional):
   ```bash
   docker run --gpus all -p 8000:8000 indextts2-serverless
   ```

4. **Push to Registry**:
   ```bash
   docker tag indextts2-serverless:latest your-registry/indextts2-serverless:latest
   docker push your-registry/indextts2-serverless:latest
   ```

5. **Deploy to RunPod**:
   - Use GPU with 8GB+ VRAM
   - Set container disk to 20GB+
   - Configure endpoint settings

## 🔍 Verification Commands

To verify the setup works:

1. **Check GPU** (in container):
   ```bash
   uv run tools/gpu_check.py
   ```

2. **Test Handler** (locally):
   ```bash
   python3 test_handler.py
   ```

3. **Verify Dependencies**:
   ```bash
   python3 -c "import torch; print(f'PyTorch: {torch.__version__}'); print(f'CUDA: {torch.cuda.is_available()}')"
   python3 -c "import runpod; print('RunPod: OK')"
   python3 -c "from indextts.infer_v2 import IndexTTS2; print('IndexTTS2: OK')"
   ```

## ✅ Everything is Set Up Correctly!

The setup follows all IndexTTS2 documentation requirements:
- ✅ Uses `uv` for dependency management
- ✅ FP16 enabled for lower VRAM usage
- ✅ CUDA kernels enabled for speed
- ✅ Proper environment variables set
- ✅ PYTHONPATH configured for module discovery
- ✅ All IndexTTS2 features supported in handler

The only remaining step is to **download the models** before building the Docker image (or mount them as a volume in RunPod).

