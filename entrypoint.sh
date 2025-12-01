#!/bin/bash
# Entrypoint script for RunPod serverless endpoint
# Handles model download if models are not present

set -e

echo ">> Starting IndexTTS2 RunPod Serverless Endpoint..."

# Set HuggingFace endpoint (use mirror if needed)
export HF_ENDPOINT=${HF_ENDPOINT:-"https://huggingface.co"}

# Check if models exist
MODEL_DIR="/workspace/checkpoints"
CONFIG_FILE="${MODEL_DIR}/config.yaml"
GPT_MODEL="${MODEL_DIR}/gpt.pth"

if [ ! -f "$CONFIG_FILE" ] || [ ! -f "$GPT_MODEL" ]; then
    echo ">> Models not found. Checking if we should download them..."
    
    # Check if we have download tools available
    if command -v hf &> /dev/null; then
        echo ">> Using HuggingFace CLI to download models..."
        hf download IndexTeam/IndexTTS-2 --local-dir="${MODEL_DIR}" || {
            echo ">> HuggingFace download failed, trying ModelScope..."
            if command -v modelscope &> /dev/null; then
                modelscope download --model IndexTeam/IndexTTS-2 --local_dir "${MODEL_DIR}" || {
                    echo ">> ERROR: Failed to download models. Please ensure models are available."
                    echo ">> You can either:"
                    echo ">>   1. Download models before building the Docker image"
                    echo ">>   2. Mount a volume with models in RunPod"
                    echo ">>   3. Ensure huggingface-cli or modelscope is available in the container"
                    exit 1
                }
            else
                echo ">> ERROR: Neither huggingface-cli nor modelscope found."
                echo ">> Please download models before building the Docker image or mount them as a volume."
                exit 1
            }
        }
    elif command -v modelscope &> /dev/null; then
        echo ">> Using ModelScope to download models..."
        modelscope download --model IndexTeam/IndexTTS-2 --local_dir "${MODEL_DIR}" || {
            echo ">> ERROR: Failed to download models via ModelScope."
            exit 1
        }
    else
        echo ">> ERROR: Models not found and no download tools available."
        echo ">> For RunPod serverless, models should be:"
        echo ">>   1. Downloaded before building the Docker image (recommended)"
        echo ">>   2. Mounted as a volume in RunPod"
        echo ">> Downloading models at runtime adds 10+ minutes to cold start time."
        echo ">> Exiting to prevent slow cold starts..."
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

