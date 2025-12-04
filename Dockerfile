# Dockerfile for IndexTTS2 RunPod Serverless Endpoint
# Optimized for fast cold starts with pre-downloaded models and pre-built FSTs
# Multi-stage build to handle disk space constraints

# ============================================================================
# BUILDER STAGE - Downloads models and builds everything
# ============================================================================
FROM nvidia/cuda:12.8.0-devel-ubuntu22.04 AS builder

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV HF_HUB_CACHE=/build/checkpoints/hf_cache
ENV HF_ENDPOINT=https://huggingface.co
ENV CUDA_HOME=/usr/local/cuda
ENV PATH=${CUDA_HOME}/bin:${PATH}
ENV LD_LIBRARY_PATH=${CUDA_HOME}/lib64:${LD_LIBRARY_PATH}

# Install system dependencies
RUN apt-get update && apt-get install -y \
    python3.10 \
    python3.10-dev \
    python3.10-venv \
    python3-pip \
    git \
    git-lfs \
    wget \
    curl \
    ffmpeg \
    libsndfile1 \
    build-essential \
    ninja-build \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Create symlink for python3.10
RUN ln -sf /usr/bin/python3.10 /usr/bin/python3

# Install uv package manager
RUN pip3 install -U uv && \
    pip3 cache purge || true

# Set working directory
WORKDIR /build

# Copy all code
COPY . /build/

# Install git-lfs and pull large files
RUN git lfs install && \
    (git lfs pull || echo "Git LFS pull completed or skipped")

# Install main project dependencies using uv
RUN uv sync --all-extras --python 3.10

# Install model download tools
RUN (uv tool install "huggingface-hub[cli,hf_xet]" || echo "HuggingFace CLI installation skipped") && \
    (uv tool install "modelscope" || echo "ModelScope installation skipped")

# Create checkpoints and cache directories
RUN mkdir -p /build/checkpoints/hf_cache /build/cache/{transformers,torch,huggingface}

# === PRE-DOWNLOAD ALL MODELS AT BUILD TIME ===
# Split downloads across multiple RUN layers to avoid disk space issues
# Each layer is cached separately, reducing peak disk usage
ARG HF_TOKEN=""
ENV HF_TOKEN=$HF_TOKEN

# Download IndexTTS-2 main model (largest, ~2-3GB)
# Use BuildKit cache mount to store HF cache separately
RUN --mount=type=cache,target=/root/.cache/huggingface \
    if [ -n "$HF_TOKEN" ]; then \
        echo ">> Pre-downloading IndexTTS-2 models (includes qwen0.6b-emo4-merge)..." && \
        /build/.venv/bin/python3 -c "\
import os; \
os.environ['HF_TOKEN'] = '$HF_TOKEN'; \
os.environ['HF_HUB_CACHE'] = '/build/checkpoints/hf_cache'; \
from huggingface_hub import snapshot_download; \
snapshot_download('IndexTeam/IndexTTS-2', local_dir='/build/checkpoints', token='$HF_TOKEN'); \
print('>> IndexTTS-2 downloaded successfully'); \
" || echo "IndexTTS-2 download failed - will download at runtime"; \
    else \
        echo ">> HF_TOKEN not provided - skipping IndexTTS-2 download"; \
    fi

# Download MaskGCT semantic codec (specific file, ~500MB)
RUN --mount=type=cache,target=/root/.cache/huggingface \
    if [ -n "$HF_TOKEN" ]; then \
        echo ">> Pre-downloading MaskGCT semantic codec..." && \
        /build/.venv/bin/python3 -c "\
import os; \
os.environ['HF_TOKEN'] = '$HF_TOKEN'; \
os.environ['HF_HUB_CACHE'] = '/build/checkpoints/hf_cache'; \
from huggingface_hub import hf_hub_download; \
hf_hub_download('amphion/MaskGCT', filename='semantic_codec/model.safetensors', local_dir='/build/checkpoints/hf_cache/models--amphion--MaskGCT', token='$HF_TOKEN'); \
print('>> MaskGCT downloaded successfully'); \
" || echo "MaskGCT download failed - will download at runtime"; \
    fi

# Download campplus speaker encoder (specific file, ~200MB)
RUN --mount=type=cache,target=/root/.cache/huggingface \
    if [ -n "$HF_TOKEN" ]; then \
        echo ">> Pre-downloading campplus speaker encoder..." && \
        /build/.venv/bin/python3 -c "\
import os; \
os.environ['HF_TOKEN'] = '$HF_TOKEN'; \
os.environ['HF_HUB_CACHE'] = '/build/checkpoints/hf_cache'; \
from huggingface_hub import hf_hub_download; \
hf_hub_download('funasr/campplus', filename='campplus_cn_common.bin', local_dir='/build/checkpoints/hf_cache/models--funasr--campplus', token='$HF_TOKEN'); \
print('>> campplus downloaded successfully'); \
" || echo "campplus download failed - will download at runtime"; \
    fi

# Download BigVGAN vocoder (~1-2GB)
RUN --mount=type=cache,target=/root/.cache/huggingface \
    if [ -n "$HF_TOKEN" ]; then \
        echo ">> Pre-downloading BigVGAN vocoder..." && \
        /build/.venv/bin/python3 -c "\
import os; \
os.environ['HF_TOKEN'] = '$HF_TOKEN'; \
os.environ['HF_HUB_CACHE'] = '/build/checkpoints/hf_cache'; \
from huggingface_hub import snapshot_download; \
snapshot_download('nvidia/bigvgan_v2_22khz_80band_256x', local_dir='/build/checkpoints/hf_cache/models--nvidia--bigvgan_v2_22khz_80band_256x', token='$HF_TOKEN'); \
print('>> BigVGAN downloaded successfully'); \
" || echo "BigVGAN download failed - will download at runtime"; \
    fi

# Download w2v-bert-2.0 semantic model (~1-2GB)
RUN --mount=type=cache,target=/root/.cache/huggingface \
    if [ -n "$HF_TOKEN" ]; then \
        echo ">> Pre-downloading w2v-bert-2.0 semantic model..." && \
        /build/.venv/bin/python3 -c "\
import os; \
os.environ['HF_TOKEN'] = '$HF_TOKEN'; \
os.environ['HF_HUB_CACHE'] = '/build/checkpoints/hf_cache'; \
from huggingface_hub import snapshot_download; \
snapshot_download('facebook/w2v-bert-2.0', local_dir='/build/checkpoints/hf_cache/models--facebook--w2v-bert-2.0', token='$HF_TOKEN'); \
print('>> w2v-bert-2.0 downloaded successfully'); \
print('>> All models pre-downloaded successfully'); \
" || echo "w2v-bert-2.0 download failed - will download at runtime"; \
    fi

# === PRE-BUILD WeText FSTs ===
RUN echo ">> Pre-building WeText FSTs..." && \
    /build/.venv/bin/python3 -c "\
import os; \
import sys; \
os.environ['HF_HUB_CACHE'] = './checkpoints/hf_cache'; \
sys.path.insert(0, '/build'); \
from indextts.utils.front import TextNormalizer; \
normalizer = TextNormalizer(); \
normalizer.load(); \
print('>> WeText FSTs pre-built successfully'); \
" || echo "FST pre-build skipped (will build on first use)"

# === PRE-COMPILE BigVGAN CUDA ===
RUN echo ">> Pre-compiling BigVGAN module..." && \
    /build/.venv/bin/python3 -c "\
import sys; \
sys.path.insert(0, '/build'); \
import indextts.s2mel.modules.bigvgan; \
print('>> BigVGAN module pre-compiled successfully'); \
" || echo "BigVGAN pre-compile skipped"

# ============================================================================
# FINAL STAGE - Copy only what's needed for runtime
# ============================================================================
FROM nvidia/cuda:12.8.0-runtime-ubuntu22.04

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

# Install minimal runtime dependencies
RUN apt-get update && apt-get install -y \
    python3.10 \
    python3.10-venv \
    git \
    git-lfs \
    ffmpeg \
    libsndfile1 \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Create symlink for python3.10
RUN ln -sf /usr/bin/python3.10 /usr/bin/python3

# Install uv package manager
RUN pip3 install -U uv && \
    pip3 cache purge || true

# Set working directory
WORKDIR /workspace

# Copy virtual environment from builder
COPY --from=builder /build/.venv /workspace/.venv

# Copy checkpoints (models) from builder
COPY --from=builder /build/checkpoints /workspace/checkpoints

# Copy all code (needed for imports and runtime)
COPY --from=builder /build/indextts /workspace/indextts
COPY --from=builder /build/handler.py /workspace/handler.py
COPY --from=builder /build/entrypoint.sh /workspace/entrypoint.sh
COPY --from=builder /build/pyproject.toml /workspace/pyproject.toml
COPY --from=builder /build/README.md /workspace/README.md

# Copy optional files if they exist (using RUN with shell to handle missing files)
RUN set -e; \
    if [ -f /build/uv.lock ]; then cp /build/uv.lock /workspace/; fi; \
    if [ -f /build/.python-version ]; then cp /build/.python-version /workspace/; fi; \
    true

# Create cache directories
RUN mkdir -p /workspace/cache/{transformers,torch,huggingface}

# Make entrypoint script executable
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

# Use entrypoint script
ENTRYPOINT ["/workspace/entrypoint.sh"]
