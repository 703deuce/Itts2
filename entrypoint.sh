#!/bin/bash
# Entrypoint script for RunPod serverless endpoint
# Handles model download if models are not present and warms up CUDA

set -e

echo ">> Starting IndexTTS2 RunPod Serverless Endpoint..."

# === WARM UP CUDA CONTEXT ===
echo ">> ENTRYPOINT: Pre-warming CUDA context..."
if command -v nvidia-smi &> /dev/null; then
    nvidia-smi --query-gpu=name,memory.total --format=csv,noheader || echo "nvidia-smi check skipped"
fi

# Warm up PyTorch CUDA
python3 -c "import torch; print(f'CUDA available: {torch.cuda.is_available()}'); torch.cuda.is_available() and torch.cuda.synchronize(); print('CUDA context warmed')" || echo "CUDA warmup skipped"

# Set HuggingFace endpoint (use mirror if needed)
export HF_ENDPOINT=${HF_ENDPOINT:-"https://huggingface.co"}

# Check if models exist
MODEL_DIR="/workspace/checkpoints"
CONFIG_FILE="${MODEL_DIR}/config.yaml"
GPT_MODEL="${MODEL_DIR}/gpt.pth"

if [ ! -f "$CONFIG_FILE" ] || [ ! -f "$GPT_MODEL" ]; then
    echo ">> Models not found. Checking if we should download them..."
    
    # Check if we have download tools available
    DOWNLOAD_SUCCESS=false
    
    if command -v hf &> /dev/null; then
        echo ">> Using HuggingFace CLI to download models..."
        if hf download IndexTeam/IndexTTS-2 --local-dir="${MODEL_DIR}"; then
            DOWNLOAD_SUCCESS=true
        else
            echo ">> HuggingFace download failed, trying ModelScope..."
            if command -v modelscope &> /dev/null; then
                if modelscope download --model IndexTeam/IndexTTS-2 --local_dir "${MODEL_DIR}"; then
                    DOWNLOAD_SUCCESS=true
                fi
            fi
        fi
    elif command -v modelscope &> /dev/null; then
        echo ">> Using ModelScope to download models..."
        if modelscope download --model IndexTeam/IndexTTS-2 --local_dir "${MODEL_DIR}"; then
            DOWNLOAD_SUCCESS=true
        fi
    fi
    
    if [ "$DOWNLOAD_SUCCESS" = false ]; then
        echo ">> ERROR: Failed to download models. Please ensure models are available."
        echo ">> You can either:"
        echo ">>   1. Download models before building the Docker image (recommended)"
        echo ">>   2. Mount a volume with models in RunPod"
        echo ">>   3. Ensure huggingface-cli or modelscope is available in the container"
        echo ">> Downloading models at runtime adds 10+ minutes to cold start time."
        exit 1
    fi
else
    echo ">> Models found in ${MODEL_DIR}, skipping download."
fi

# Verify models are present
if [ ! -f "$CONFIG_FILE" ]; then
    echo ">> ERROR: config.yaml not found in ${MODEL_DIR}"
    exit 1
fi

if [ ! -f "$GPT_MODEL" ]; then
    echo ">> ERROR: gpt.pth not found in ${MODEL_DIR}"
    exit 1
fi

echo ">> Models verified. Starting handler..."

# Run the handler
exec python3 handler.py

