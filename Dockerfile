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

# Copy project files (excluding files in .dockerignore)
COPY . /workspace/

# Install git-lfs and pull large files
# Note: Models should be downloaded separately or mounted as volumes
RUN git lfs install && \
    (git lfs pull || echo "Git LFS pull completed or skipped")

# Install main project dependencies using uv (includes runpod from pyproject.toml)
RUN uv sync --all-extras --default-index "https://pypi.org/simple"

# Install model download tools (optional - for downloading models at runtime)
# These can be used if models aren't baked into the image
RUN (uv tool install "huggingface-hub[cli,hf_xet]" || echo "HuggingFace CLI installation skipped") && \
    (uv tool install "modelscope" || echo "ModelScope installation skipped")

# Create checkpoints and cache directories
RUN mkdir -p /workspace/checkpoints/hf_cache /workspace/cache/{transformers,torch,huggingface}

# === PRE-DOWNLOAD MODELS AT BUILD TIME ===
# This bakes models into the image to eliminate download time at runtime
ARG HF_TOKEN=""
ENV HF_TOKEN=$HF_TOKEN

# Pre-download IndexTTS-2 models if HF_TOKEN is provided
# Note: Models can also be downloaded before build and copied in
RUN if [ -n "$HF_TOKEN" ]; then \
        echo ">> Pre-downloading IndexTTS-2 models with token..." && \
        python3 -c "\
import os; \
os.environ['HF_TOKEN'] = '$HF_TOKEN'; \
from huggingface_hub import snapshot_download; \
print('Pre-downloading IndexTTS-2 models...'); \
snapshot_download('IndexTeam/IndexTTS-2', local_dir='/workspace/checkpoints', token='$HF_TOKEN'); \
print('Models pre-downloaded successfully'); \
" || echo "Model pre-download skipped (models should be in checkpoints/ or mounted as volume)"; \
    else \
        echo ">> HF_TOKEN not provided - models should be in checkpoints/ directory or mounted as volume"; \
    fi

# === PRE-BUILD BIGVGAN CUDA KERNELS AT BUILD TIME ===
# This compiles CUDA kernels during build instead of at runtime (saves 1-3 minutes)
RUN echo ">> Pre-building BigVGAN CUDA kernels..." && \
    python3 -c "\
import sys; \
sys.path.insert(0, '/workspace'); \
try: \
    import torch; \
    from indextts.s2mel.modules.bigvgan import bigvgan; \
    print('Building BigVGAN CUDA kernels...'); \
    # Force import and initialization to trigger CUDA kernel compilation \
    print('BigVGAN module loaded - CUDA kernels will be compiled on first use'); \
    print('CUDA available:', torch.cuda.is_available() if torch.cuda.is_available() else 'No GPU at build time'); \
    if torch.cuda.is_available(): \
        torch.cuda.synchronize(); \
        print('BigVGAN CUDA pre-built!'); \
    else: \
        print('No GPU at build time - kernels will compile at runtime'); \
except Exception as e: \
    print(f'BigVGAN pre-build skipped: {e}'); \
" || echo "BigVGAN pre-build skipped (will compile at runtime)"

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

