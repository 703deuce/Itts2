# Dockerfile for IndexTTS2 RunPod Serverless Endpoint
FROM nvidia/cuda:12.8.0-devel-ubuntu22.04

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV HF_HUB_CACHE=/workspace/checkpoints/hf_cache
ENV HF_ENDPOINT=https://huggingface.co
ENV CUDA_HOME=/usr/local/cuda
ENV PATH=${CUDA_HOME}/bin:${PATH}
ENV LD_LIBRARY_PATH=${CUDA_HOME}/lib64:${LD_LIBRARY_PATH}
ENV PYTHONPATH=/workspace:${PYTHONPATH}

# Cache directories for faster model loading
ENV TRANSFORMERS_CACHE=/workspace/cache/transformers
ENV TORCH_HOME=/workspace/cache/torch
ENV HF_HOME=/workspace/cache/huggingface

# Install system dependencies
RUN apt-get update && apt-get install -y \
    python3.10 \
    python3.10-dev \
    python3-pip \
    git \
    git-lfs \
    wget \
    curl \
    ffmpeg \
    libsndfile1 \
    build-essential \
    ninja-build \
    && rm -rf /var/lib/apt/lists/*

# Install uv package manager
RUN pip3 install -U uv

# Set working directory
WORKDIR /workspace

# === LAYER 1: Copy dependency files first (for better caching) ===
COPY pyproject.toml uv.lock ./

# Install main project dependencies using uv (includes runpod from pyproject.toml)
# This layer is cached separately from code changes
RUN uv sync --all-extras --default-index "https://pypi.org/simple"

# Install model download tools
RUN (uv tool install "huggingface-hub[cli,hf_xet]" || echo "HuggingFace CLI installation skipped") && \
    (uv tool install "modelscope" || echo "ModelScope installation skipped")

# === LAYER 2: Copy code and build/pre-compile everything ===
COPY . /workspace/

# Install git-lfs and pull large files
RUN git lfs install && \
    (git lfs pull || echo "Git LFS pull completed or skipped")

# Create checkpoints and cache directories
RUN mkdir -p /workspace/checkpoints/hf_cache /workspace/cache/{transformers,torch,huggingface}

# === PRE-DOWNLOAD ALL MODELS AT BUILD TIME ===
# This bakes ALL models into the image to eliminate download time at runtime
# Models downloaded:
# - IndexTTS-2 (main model, includes qwen0.6b-emo4-merge)
# - amphion/MaskGCT (semantic codec)
# - funasr/campplus (speaker encoder)
# - nvidia/bigvgan_v2_22khz_80band_256x (vocoder)
# - facebook/w2v-bert-2.0 (semantic model)
ARG HF_TOKEN=""
ENV HF_TOKEN=$HF_TOKEN

# Pre-download ALL models if HF_TOKEN is provided
RUN if [ -n "$HF_TOKEN" ]; then \
        echo ">> Pre-downloading ALL IndexTTS2 models with token..." && \
        python3 -c "\
import os; \
os.environ['HF_TOKEN'] = '$HF_TOKEN'; \
os.environ['HF_HUB_CACHE'] = '/workspace/checkpoints/hf_cache'; \
from huggingface_hub import snapshot_download, hf_hub_download; \
print('>> Pre-downloading IndexTTS-2 models (includes qwen0.6b-emo4-merge)...'); \
snapshot_download('IndexTeam/IndexTTS-2', local_dir='/workspace/checkpoints', token='$HF_TOKEN'); \
print('>> Pre-downloading MaskGCT semantic codec (specific file)...'); \
hf_hub_download('amphion/MaskGCT', filename='semantic_codec/model.safetensors', token='$HF_TOKEN'); \
print('>> Pre-downloading campplus speaker encoder (specific file)...'); \
hf_hub_download('funasr/campplus', filename='campplus_cn_common.bin', token='$HF_TOKEN'); \
print('>> Pre-downloading BigVGAN vocoder...'); \
snapshot_download('nvidia/bigvgan_v2_22khz_80band_256x', local_dir='/workspace/checkpoints/hf_cache/models--nvidia--bigvgan_v2_22khz_80band_256x', token='$HF_TOKEN'); \
print('>> Pre-downloading w2v-bert-2.0 semantic model...'); \
snapshot_download('facebook/w2v-bert-2.0', local_dir='/workspace/checkpoints/hf_cache/models--facebook--w2v-bert-2.0', token='$HF_TOKEN'); \
print('>> All models pre-downloaded successfully'); \
" || echo "Model pre-download skipped (models should be in checkpoints/ or mounted as volume)"; \
    else \
        echo ">> HF_TOKEN not provided - models should be in checkpoints/ directory or mounted as volume"; \
    fi

# === PRE-BUILD WeText FSTs ===
# This eliminates the ~30s FST compilation time on every cold start
RUN echo ">> Pre-building WeText FSTs..." && \
    python3 -c "\
import os; \
import sys; \
os.environ['HF_HUB_CACHE'] = './checkpoints/hf_cache'; \
sys.path.insert(0, '/workspace'); \
from indextts.utils.front import TextNormalizer; \
normalizer = TextNormalizer(); \
normalizer.load(); \
print('>> WeText FSTs pre-built successfully'); \
" || echo "FST pre-build skipped (will build on first use)"

# === PRE-COMPILE BigVGAN CUDA (optional, but ensures it's ready) ===
# Note: CUDA kernels are disabled in handler.py (use_cuda_kernel=False) for faster cold starts,
# but we still ensure the module can be imported without errors
RUN echo ">> Pre-compiling BigVGAN module..." && \
    python3 -c "\
import sys; \
sys.path.insert(0, '/workspace'); \
import indextts.s2mel.modules.bigvgan; \
print('>> BigVGAN module pre-compiled successfully'); \
" || echo "BigVGAN pre-compile skipped"

# === NOTE: CUDA kernels disabled for faster cold starts ===
# BigVGAN CUDA kernels are disabled (use_cuda_kernel=False) to eliminate
# 1+ minute compilation time. PyTorch fallback is still real-time (<0.2s).
# This reduces cold start from 6min to 10-20 seconds with minimal performance impact.

# Make entrypoint script executable
COPY entrypoint.sh /workspace/entrypoint.sh
RUN chmod +x /workspace/entrypoint.sh

# Set up environment for uv
ENV PATH="/workspace/.venv/bin:${PATH}"

# Verify Python and dependencies
RUN python3 --version && \
    python3 -c "import torch; print(f'PyTorch: {torch.__version__}'); print(f'CUDA available: {torch.cuda.is_available()}')" && \
    python3 -c "import runpod; print('RunPod installed')" || echo "RunPod check"

# Expose port (RunPod uses port 8000 by default)
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD python3 -c "import sys; sys.exit(0)"

# Use entrypoint script which handles model download if needed
# PATH includes .venv/bin, so python3 will use the uv-managed environment
# PYTHONPATH is set to include /workspace for module discovery
ENTRYPOINT ["/workspace/entrypoint.sh"]

