# Test Endpoint Script

## Overview

`test_endpoint.py` is a test script for the RunPod serverless endpoint. It tests the IndexTTS2 API by:
1. Loading an audio file (local or from URL)
2. Submitting a TTS job to RunPod
3. Polling for job completion
4. Downloading and saving the generated audio

## ⚠️ Security Notice

**This file contains sensitive API keys and endpoints and is NOT committed to GitHub.**

The file is excluded via `.gitignore` to prevent accidental commits.

## Setup

1. **Install dependencies** (if not already installed):
   ```bash
   pip install requests
   # Or if using uv:
   uv pip install requests
   ```

2. **Configure the script**:
   - Open `test_endpoint.py`
   - Update the configuration variables at the top:
     - `RUNPOD_ENDPOINT_ID` - Your RunPod endpoint ID
     - `RUNPOD_API_KEY` - Your RunPod API key
     - `HF_TOKEN` - HuggingFace token (optional)
     - `AUDIO_FILE_LOCAL` - Path to local audio file (optional)
     - `AUDIO_FILE_URL` - URL to audio file (used if local file not found)

## Usage

```bash
python test_endpoint.py
# Or with uv:
uv run test_endpoint.py
```

## Features

- **Flexible audio input**: Uses local file if available, falls back to URL
- **Job polling**: Automatically polls RunPod API for job completion
- **Progress tracking**: Shows status updates and elapsed time
- **Error handling**: Comprehensive error messages and tracebacks
- **Output management**: Saves generated audio with timestamps

## Output

Generated audio files are saved to `test_outputs/` directory with format:
- `output_<timestamp>.wav`

The script prints:
- Job submission status
- Polling progress
- File save location and details (size, sample rate, format)

## Example Output

```
============================================================
IndexTTS2 RunPod Endpoint Test
============================================================

Step 1: Loading audio file...
>> Loading audio from URL: https://firebasestorage.googleapis.com/...
>> Audio loaded (123456 base64 characters)

Step 2: Submitting job to RunPod...
>> Submitting job to RunPod endpoint: fbtmbk778obt7m
>> Text: Hello, this is a test...
>> Job submitted successfully. Job ID: abc123xyz

Step 3: Waiting for job completion...
>> Polling job status (max wait: 300s)...
>> Status: IN_PROGRESS (elapsed: 2.1s)
>> Status: IN_PROGRESS (elapsed: 15.3s)
>> Status: COMPLETED (elapsed: 28.7s)
>> Job completed in 28.7 seconds

Step 4: Saving output audio...
>> Audio saved successfully!
>>   File: test_outputs/output_1234567890.wav
>>   Size: 234,567 bytes (229.07 KB)
>>   Sample Rate: 24000 Hz
>>   Format: wav

============================================================
✅ Test completed successfully!
✅ Output saved to: test_outputs/output_1234567890.wav
============================================================
```

## Troubleshooting

### Job Timeout
- Increase `max_wait_time` in `poll_job_status()` call
- Check RunPod endpoint logs for errors

### Audio Loading Failed
- Verify URL is accessible
- Check local file path if using local file
- Ensure audio file is in WAV format

### API Errors
- Verify API key is correct
- Check endpoint ID is correct
- Ensure endpoint is active in RunPod dashboard

## Notes

- The script uses a 5-minute (300s) default timeout
- Polling interval is 2 seconds (adjustable)
- Output files are timestamped to avoid overwrites
- All sensitive data is in the script file (not in environment variables)

