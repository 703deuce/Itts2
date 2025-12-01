"""
Test script for the RunPod serverless handler.
This can be used to test the handler locally before deploying.
"""

import base64
import json
from handler import handler

def test_handler():
    """Test the handler with a sample request."""
    
    # Read a sample audio file (use one of the example voices)
    try:
        with open("examples/voice_01.wav", "rb") as f:
            audio_data = f.read()
            audio_base64 = base64.b64encode(audio_data).decode('utf-8')
    except FileNotFoundError:
        print("Error: examples/voice_01.wav not found. Please provide a speaker audio file.")
        return
    
    # Create a test job
    test_job = {
        "input": {
            "text": "Hello, this is a test of the IndexTTS2 serverless endpoint.",
            "spk_audio_prompt": audio_base64,
            "use_emo_text": True,
            "emo_alpha": 0.6,
            "verbose": True
        }
    }
    
    print(">> Testing handler with sample request...")
    print(f">> Text: {test_job['input']['text']}")
    
    # Call the handler
    result = handler(test_job)
    
    # Check result
    if "error" in result:
        print(f">> Error: {result['error']}")
        if "traceback" in result:
            print(f">> Traceback: {result['traceback']}")
        return
    
    # Save output audio
    if "audio" in result:
        audio_data = base64.b64decode(result["audio"])
        with open("test_output.wav", "wb") as f:
            f.write(audio_data)
        print(f">> Success! Audio saved to test_output.wav")
        print(f">> Sample rate: {result.get('sample_rate', 'unknown')}")
        print(f">> Format: {result.get('format', 'unknown')}")
    else:
        print(">> Unexpected result format:", result)

if __name__ == "__main__":
    test_handler()

