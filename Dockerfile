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

# Create checkpoints directory
RUN mkdir -p /workspace/checkpoints/hf_cache

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

