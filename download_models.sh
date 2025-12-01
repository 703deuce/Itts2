#!/bin/bash
# Script to download IndexTTS2 models
# This can be run during container startup or before building the image

set -e

echo ">> Downloading IndexTTS2 models..."

# Set HuggingFace endpoint (use mirror if needed)
export HF_ENDPOINT=${HF_ENDPOINT:-"https://huggingface.co"}

# Create checkpoints directory
mkdir -p checkpoints

# Check if models already exist
if [ -d "checkpoints/gpt.pth" ] && [ -f "checkpoints/config.yaml" ]; then
    echo ">> Models already exist, skipping download..."
    exit 0
fi

# Download using HuggingFace CLI
if command -v hf &> /dev/null; then
    echo ">> Using HuggingFace CLI to download models..."
    hf download IndexTeam/IndexTTS-2 --local-dir=checkpoints
elif command -v modelscope &> /dev/null; then
    echo ">> Using ModelScope to download models..."
    modelscope download --model IndexTeam/IndexTTS-2 --local_dir checkpoints
else
    echo ">> Error: Neither huggingface-cli nor modelscope found."
    echo ">> Please install one of them:"
    echo ">>   uv tool install 'huggingface-hub[cli,hf_xet]'"
    echo ">>   or"
    echo ">>   uv tool install modelscope"
    exit 1
fi

echo ">> Model download completed!"

