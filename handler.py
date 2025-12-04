"""
RunPod Serverless Handler for IndexTTS2
This handler processes TTS requests and returns generated audio files.
"""

import os
import sys

# Add current directory to PYTHONPATH to help find IndexTTS modules (as per docs)
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import base64
import tempfile
import json
import traceback
from typing import Dict, Any, Optional
import torch
import runpod
from indextts.infer_v2 import IndexTTS2

# Initialize the TTS model globally to avoid reloading on each request
# Models are pre-baked into the Docker image, so initialization should be fast (~2min load time)
tts_model = None

def initialize_model():
    """
    Initialize the IndexTTS2 model once at startup.
    
    NOTE: All models are pre-downloaded in Dockerfile:
    - IndexTTS-2 (main model, includes qwen0.6b-emo4-merge)
    - amphion/MaskGCT (semantic codec)
    - funasr/campplus (speaker encoder)
    - nvidia/bigvgan_v2_22khz_80band_256x (vocoder)
    - facebook/w2v-bert-2.0 (semantic model)
    
    WeText FSTs are also pre-built, so no runtime compilation needed.
    """
    global tts_model
    if tts_model is None:
        print(">> Initializing IndexTTS2 model...")
        print(">>   (Models are pre-baked in image - no downloads expected)")
        try:
            # Set environment variables (models already in ./checkpoints/hf_cache from Dockerfile)
            os.environ['HF_HUB_CACHE'] = './checkpoints/hf_cache'
            
            # Initialize model with optimized settings for serverless
            tts_model = IndexTTS2(
                cfg_path="checkpoints/config.yaml",
                model_dir="checkpoints",
                use_fp16=True,  # Use FP16 for lower VRAM usage
                use_cuda_kernel=False,  # Disabled for faster cold starts (eliminates 1+ min compilation)
                use_deepspeed=False,  # DeepSpeed may not work well in serverless
                use_accel=False,
                use_torch_compile=False
            )
            print(">> Model initialized successfully!")
        except Exception as e:
            print(f">> Error initializing model: {e}")
            traceback.print_exc()
            raise
    return tts_model

def download_file_from_url(url: str, output_path: str) -> str:
    """Download a file from URL to local path."""
    import urllib.request
    urllib.request.urlretrieve(url, output_path)
    return output_path

def save_base64_audio(base64_string: str, output_path: str) -> str:
    """Save base64 encoded audio to file."""
    audio_data = base64.b64decode(base64_string)
    with open(output_path, 'wb') as f:
        f.write(audio_data)
    return output_path

def encode_audio_to_base64(audio_path: str) -> str:
    """Encode audio file to base64 string."""
    with open(audio_path, 'rb') as f:
        audio_data = f.read()
    return base64.b64encode(audio_data).decode('utf-8')

def handler(job: Dict[str, Any]) -> Dict[str, Any]:
    """
    Main handler function for RunPod serverless.
    
    Expected input format:
    {
        "input": {
            "text": "Text to synthesize",
            "spk_audio_prompt": "base64_encoded_audio" or "url_to_audio_file",
            "emo_audio_prompt": "base64_encoded_audio" or "url_to_audio_file" (optional),
            "emo_alpha": 1.0 (optional, default: 1.0),
            "emo_vector": [0, 0, 0, 0, 0, 0, 0, 0] (optional, 8 floats),
            "use_emo_text": false (optional),
            "emo_text": "emotion description" (optional),
            "use_random": false (optional),
            "interval_silence": 200 (optional, milliseconds),
            "max_text_tokens_per_segment": 120 (optional),
            "verbose": false (optional)
        }
    }
    
    Returns:
    {
        "audio": "base64_encoded_audio",
        "sample_rate": 24000,
        "format": "wav"
    }
    
    Or on error:
    {
        "error": "error message",
        "traceback": "optional traceback"
    }
    """
    try:
        # Initialize model if not already done
        model = initialize_model()
        
        # Extract input parameters
        input_data = job.get("input", {})
        text = input_data.get("text")
        
        if not text:
            return {
                "error": "Missing required parameter: 'text'"
            }
        
        # Create temporary directory for this job
        with tempfile.TemporaryDirectory() as temp_dir:
            # Handle speaker audio prompt
            spk_audio_prompt = input_data.get("spk_audio_prompt")
            if not spk_audio_prompt:
                return {
                    "error": "Missing required parameter: 'spk_audio_prompt'"
                }
            
            spk_audio_path = os.path.join(temp_dir, "spk_audio.wav")
            if spk_audio_prompt.startswith("http://") or spk_audio_prompt.startswith("https://"):
                # Download from URL
                download_file_from_url(spk_audio_prompt, spk_audio_path)
            elif spk_audio_prompt.startswith("data:"):
                # Handle data URI
                header, encoded = spk_audio_prompt.split(",", 1)
                save_base64_audio(encoded, spk_audio_path)
            else:
                # Assume base64 encoded
                try:
                    save_base64_audio(spk_audio_prompt, spk_audio_path)
                except Exception:
                    # If base64 decode fails, assume it's a file path
                    if os.path.exists(spk_audio_prompt):
                        spk_audio_path = spk_audio_prompt
                    else:
                        return {
                            "error": f"Invalid spk_audio_prompt format. Expected URL, base64, or file path."
                        }
            
            # Handle emotion audio prompt (optional)
            emo_audio_prompt = input_data.get("emo_audio_prompt")
            emo_audio_path = None
            if emo_audio_prompt:
                emo_audio_path = os.path.join(temp_dir, "emo_audio.wav")
                if emo_audio_prompt.startswith("http://") or emo_audio_prompt.startswith("https://"):
                    download_file_from_url(emo_audio_prompt, emo_audio_path)
                elif emo_audio_prompt.startswith("data:"):
                    header, encoded = emo_audio_prompt.split(",", 1)
                    save_base64_audio(encoded, emo_audio_path)
                else:
                    try:
                        save_base64_audio(emo_audio_prompt, emo_audio_path)
                    except Exception:
                        if os.path.exists(emo_audio_prompt):
                            emo_audio_path = emo_audio_prompt
                        else:
                            emo_audio_path = None
            
            # Output path for generated audio
            output_path = os.path.join(temp_dir, "output.wav")
            
            # Extract optional parameters
            emo_alpha = input_data.get("emo_alpha", 1.0)
            emo_vector = input_data.get("emo_vector")
            use_emo_text = input_data.get("use_emo_text", False)
            emo_text = input_data.get("emo_text")
            use_random = input_data.get("use_random", False)
            interval_silence = input_data.get("interval_silence", 200)
            max_text_tokens_per_segment = input_data.get("max_text_tokens_per_segment", 120)
            verbose = input_data.get("verbose", False)
            
            # Prepare inference parameters
            infer_params = {
                "spk_audio_prompt": spk_audio_path,
                "text": text,
                "output_path": output_path,
                "emo_alpha": emo_alpha,
                "use_random": use_random,
                "interval_silence": interval_silence,
                "verbose": verbose,
                "max_text_tokens_per_segment": max_text_tokens_per_segment,
            }
            
            # Add optional parameters
            if emo_audio_path:
                infer_params["emo_audio_prompt"] = emo_audio_path
            
            if emo_vector:
                infer_params["emo_vector"] = emo_vector
            
            if use_emo_text:
                infer_params["use_emo_text"] = True
                if emo_text:
                    infer_params["emo_text"] = emo_text
            
            # Run inference
            print(f">> Processing TTS request: text='{text[:50]}...'")
            result = model.infer(**infer_params)
            
            # Check if output file was created
            if not os.path.exists(output_path):
                return {
                    "error": "Failed to generate audio file"
                }
            
            # Encode output audio to base64
            audio_base64 = encode_audio_to_base64(output_path)
            
            # Return result (RunPod expects the result directly, not wrapped)
            return {
                "audio": audio_base64,
                "sample_rate": 24000,
                "format": "wav"
            }
    
    except Exception as e:
        error_msg = str(e)
        error_trace = traceback.format_exc()
        print(f">> Error in handler: {error_msg}")
        print(f">> Traceback: {error_trace}")
        return {
            "error": error_msg,
            "traceback": error_trace
        }

# Initialize model at module load time
if __name__ == "__main__":
    print(">> Starting RunPod serverless handler for IndexTTS2...")
    
    # === WARMUP: Load model IMMEDIATELY at startup ===
    # This pre-loads the model into VRAM to eliminate cold start delay
    print(">> WARMING UP: Loading IndexTTS2 into VRAM...")
    try:
        # Initialize model immediately (not lazy)
        model = initialize_model()
        print(">> WARMUP COMPLETE: Model loaded in VRAM - ready for instant requests!")
        
        # Clear any unused cache
        if torch.cuda.is_available():
            torch.cuda.empty_cache()
            print(f">> GPU Memory: {torch.cuda.get_device_properties(0).total_memory / 1024**3:.2f} GB total")
        
    except Exception as e:
        print(f">> WARMUP FAILED: {e}")
        traceback.print_exc()
        # Don't raise - allow handler to try again on first request
        print(">> Will attempt to load model on first request...")
    
    print(">> Starting RunPod serverless...")
    runpod.serverless.start({"handler": handler})

