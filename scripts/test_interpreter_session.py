#!/usr/bin/env python3
"""
Interpreter Session Test Script

Simulates real-time interpreter by:
1. Creating a backend session
2. Slicing audio file into segments with overlap
3. Sending each segment to backend
4. Collecting results via SSE or sync response

Usage:
    python test_interpreter_session.py <audio_file> [--base-url URL] [--api-key KEY]
"""

import argparse
import asyncio
import base64
import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Optional
import aiohttp

# Configuration
SEGMENT_DURATION = 4.0  # seconds
OVERLAP_DURATION = 2.0  # seconds
DEFAULT_BASE_URL = "https://auth.xiaojinpro.com"


def get_api_key() -> str:
    """Get API key from xjp CLI or environment"""
    # Try environment first
    api_key = os.environ.get("XJP_API_KEY") or os.environ.get("BACKEND_API_KEY")
    if api_key:
        return api_key

    # Try xjp CLI
    try:
        result = subprocess.run(
            ["xjp", "secret", "get", "BACKEND_API_KEY", "--raw"],
            capture_output=True, text=True, timeout=10
        )
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout.strip()
    except Exception as e:
        print(f"Warning: Could not get API key from xjp: {e}")

    raise ValueError("No API key found. Set XJP_API_KEY or use --api-key")


def slice_audio(input_file: str, output_dir: str, segment_duration: float, overlap: float) -> list[dict]:
    """
    Slice audio file into segments with overlap using ffmpeg.
    Returns list of segment info dicts.
    """
    segments = []

    # Get total duration
    probe_cmd = [
        "ffprobe", "-v", "quiet", "-print_format", "json",
        "-show_format", input_file
    ]
    result = subprocess.run(probe_cmd, capture_output=True, text=True)
    duration = float(json.loads(result.stdout)["format"]["duration"])

    print(f"Audio duration: {duration:.2f}s")
    print(f"Segment duration: {segment_duration}s, Overlap: {overlap}s")

    start_time = 0.0
    segment_idx = 0

    while start_time < duration:
        # Effective start (with overlap from previous)
        effective_start = max(0, start_time - overlap) if segment_idx > 0 else 0
        actual_overlap = start_time - effective_start if segment_idx > 0 else 0

        # End time
        end_time = min(start_time + segment_duration, duration)
        segment_len = end_time - effective_start

        # Output file
        output_file = os.path.join(output_dir, f"segment_{segment_idx:03d}.aac")

        # Extract segment using ffmpeg
        cmd = [
            "ffmpeg", "-y", "-v", "quiet",
            "-ss", str(effective_start),
            "-t", str(segment_len),
            "-i", input_file,
            "-acodec", "aac",
            "-ar", "16000",  # 16kHz sample rate
            "-ac", "1",      # Mono
            "-b:a", "64k",   # 64kbps
            output_file
        ]
        subprocess.run(cmd, check=True)

        # Get file size
        file_size = os.path.getsize(output_file)

        segments.append({
            "index": segment_idx,
            "file": output_file,
            "start_time": effective_start,
            "end_time": end_time,
            "overlap_duration": actual_overlap,
            "duration": segment_len,
            "size_bytes": file_size,
            "is_final": end_time >= duration
        })

        print(f"  Segment {segment_idx}: {effective_start:.2f}s - {end_time:.2f}s "
              f"(overlap: {actual_overlap:.2f}s, size: {file_size} bytes)")

        start_time = end_time
        segment_idx += 1

    return segments


async def create_session(session: aiohttp.ClientSession, base_url: str, api_key: str,
                         target_language: str = "zh") -> dict:
    """Create interpreter session"""
    url = f"{base_url}/asr/v1/interpreter/sessions"
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json"
    }
    data = {
        "target_language": target_language,
        "translation_preset": f"interpreter-to-{target_language}",
        "overlap_duration": OVERLAP_DURATION,
        "enable_translation": True
    }

    async with session.post(url, json=data, headers=headers) as resp:
        if resp.status not in (200, 201):
            text = await resp.text()
            raise Exception(f"Failed to create session: {resp.status} {text}")
        return await resp.json()


async def process_segment(session: aiohttp.ClientSession, base_url: str, api_key: str,
                          session_id: str, segment: dict) -> dict:
    """Send audio segment for processing"""
    url = f"{base_url}/asr/v1/interpreter/sessions/{session_id}/process"
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json"
    }

    # Read and encode audio
    with open(segment["file"], "rb") as f:
        audio_base64 = base64.b64encode(f.read()).decode()

    data = {
        "audio_base64": audio_base64,
        "audio_format": "aac",
        "start_time": segment["start_time"],
        "end_time": segment["end_time"],
        "is_final": segment["is_final"]
    }

    start = time.time()
    async with session.post(url, json=data, headers=headers) as resp:
        latency = (time.time() - start) * 1000

        if resp.status == 202:
            # Async processing - will get result via SSE
            result = await resp.json()
            return {"status": "accepted", "latency_ms": latency, **result}
        elif resp.status == 200:
            # Sync processing
            result = await resp.json()
            return {"status": "completed", "latency_ms": latency, **result}
        else:
            text = await resp.text()
            return {"status": "error", "latency_ms": latency, "error": f"{resp.status}: {text}"}


async def end_session(session: aiohttp.ClientSession, base_url: str, api_key: str,
                      session_id: str) -> dict:
    """End interpreter session"""
    url = f"{base_url}/asr/v1/interpreter/sessions/{session_id}"
    headers = {"Authorization": f"Bearer {api_key}"}

    async with session.delete(url, headers=headers) as resp:
        if resp.status == 200:
            return await resp.json()
        text = await resp.text()
        raise Exception(f"Failed to end session: {resp.status} {text}")


async def listen_sse(session: aiohttp.ClientSession, base_url: str, api_key: str,
                     session_id: str, results: dict):
    """Listen to SSE stream for segment results"""
    url = f"{base_url}/asr/v1/interpreter/sessions/{session_id}/stream"
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Accept": "text/event-stream"
    }

    try:
        async with session.get(url, headers=headers, timeout=aiohttp.ClientTimeout(total=None)) as resp:
            buffer = ""
            async for chunk in resp.content.iter_any():
                buffer += chunk.decode("utf-8")

                # Parse complete events
                while "\n\n" in buffer:
                    event_text, buffer = buffer.split("\n\n", 1)
                    event = parse_sse_event(event_text)
                    if event:
                        handle_sse_event(event, results)
                        if event.get("type") == "ended":
                            return
    except asyncio.CancelledError:
        pass
    except Exception as e:
        print(f"SSE error: {e}")


def parse_sse_event(text: str) -> Optional[dict]:
    """Parse SSE event text"""
    event_type = ""
    event_data = ""

    for line in text.split("\n"):
        if line.startswith("event:"):
            event_type = line[6:].strip()
        elif line.startswith("data:"):
            event_data = line[5:].strip()

    if not event_type:
        return None

    try:
        data = json.loads(event_data) if event_data else {}
    except json.JSONDecodeError:
        data = {"raw": event_data}

    return {"type": event_type, **data}


def handle_sse_event(event: dict, results: dict):
    """Handle SSE event"""
    event_type = event.get("type")

    if event_type == "ready":
        print(f"\n[SSE] Session ready: {event.get('session_id')}")

    elif event_type == "segment":
        idx = event.get("segment_index", "?")
        original = event.get("deduplicated_text", "")
        translated = event.get("translated_text", "")
        is_dup = event.get("is_duplicate", False)
        latency = event.get("latency_ms", 0)

        results["segments"][idx] = event

        if is_dup:
            print(f"\n[SSE] Segment {idx}: (duplicate)")
        else:
            print(f"\n[SSE] Segment {idx} ({latency}ms):")
            if original:
                print(f"  Text: {original[:80]}...")
            if translated:
                print(f"  → {translated[:80]}...")

    elif event_type == "error":
        print(f"\n[SSE] Error: {event.get('message')}")

    elif event_type == "ended":
        summary = event.get("summary", {})
        print(f"\n[SSE] Session ended: {summary.get('total_segments')} segments, "
              f"{summary.get('total_duration', 0):.1f}s")

    elif event_type == "heartbeat":
        pass  # Ignore heartbeats


async def run_test(audio_file: str, base_url: str, api_key: str, target_language: str,
                   use_sse: bool = True, delay: float = 0.5):
    """Run the interpreter test"""
    print(f"\n{'='*60}")
    print("Interpreter Session Test")
    print(f"{'='*60}")
    print(f"Audio file: {audio_file}")
    print(f"Base URL: {base_url}")
    print(f"Target language: {target_language}")
    print(f"Use SSE: {use_sse}")
    print(f"{'='*60}\n")

    # Create temp directory for segments
    with tempfile.TemporaryDirectory() as temp_dir:
        # Slice audio
        print("Slicing audio...")
        segments = slice_audio(audio_file, temp_dir, SEGMENT_DURATION, OVERLAP_DURATION)
        print(f"\nCreated {len(segments)} segments\n")

        # Create HTTP session
        async with aiohttp.ClientSession() as session:
            # Create interpreter session
            print("Creating interpreter session...")
            resp = await create_session(session, base_url, api_key, target_language)
            session_id = resp["session_id"]
            print(f"Session created: {session_id}")
            print(f"Stream URL: {resp.get('stream_url')}")

            results = {"segments": {}}
            sse_task = None

            try:
                # Start SSE listener if enabled
                if use_sse:
                    print("\nStarting SSE listener...")
                    sse_task = asyncio.create_task(
                        listen_sse(session, base_url, api_key, session_id, results)
                    )
                    await asyncio.sleep(1)  # Wait for SSE connection

                # Process segments
                print("\nProcessing segments...")
                for i, seg in enumerate(segments):
                    print(f"\nSending segment {i}/{len(segments)-1} "
                          f"({seg['start_time']:.1f}s - {seg['end_time']:.1f}s)...", end=" ", flush=True)

                    result = await process_segment(session, base_url, api_key, session_id, seg)

                    status = result.get("status")
                    latency = result.get("latency_ms", 0)

                    if status == "accepted":
                        print(f"accepted ({latency:.0f}ms)")
                    elif status == "completed":
                        text = result.get("deduplicated_text", "")[:50]
                        print(f"done ({latency:.0f}ms): {text}...")
                        results["segments"][i] = result
                    else:
                        print(f"error: {result.get('error')}")

                    # Simulate real-time delay
                    if delay > 0 and i < len(segments) - 1:
                        await asyncio.sleep(delay)

                # Wait for SSE results
                if use_sse and sse_task:
                    print("\n\nWaiting for SSE results...")
                    await asyncio.sleep(5)  # Wait for final results
                    sse_task.cancel()
                    try:
                        await sse_task
                    except asyncio.CancelledError:
                        pass

                # End session
                print("\nEnding session...")
                end_resp = await end_session(session, base_url, api_key, session_id)
                summary = end_resp.get("summary", {})

                print(f"\n{'='*60}")
                print("Session Summary")
                print(f"{'='*60}")
                print(f"Total segments: {summary.get('total_segments', len(segments))}")
                print(f"Total duration: {summary.get('total_duration', 0):.1f}s")
                print(f"{'='*60}")

                # Print all results
                print("\n\nAll Transcriptions:")
                print("-" * 60)
                for idx in sorted(results["segments"].keys()):
                    seg = results["segments"][idx]
                    is_dup = seg.get("is_duplicate", False)
                    orig = seg.get("deduplicated_text") or seg.get("deduplicated") or seg.get("original", "")
                    trans = seg.get("translated_text") or seg.get("translated", "")
                    if is_dup:
                        print(f"[{idx}] (duplicate)")
                    elif orig:
                        print(f"[{idx}] {orig}")
                        if trans:
                            print(f"    → {trans}")
                    print()

            except Exception as e:
                print(f"\nError: {e}")
                raise
            finally:
                if sse_task:
                    sse_task.cancel()


def main():
    parser = argparse.ArgumentParser(description="Test interpreter session API")
    parser.add_argument("audio_file", help="Path to audio file (m4a, mp3, wav)")
    parser.add_argument("--base-url", default=DEFAULT_BASE_URL, help="API base URL")
    parser.add_argument("--api-key", help="API key (or set XJP_API_KEY env var)")
    parser.add_argument("--target-language", default="zh", help="Target language (zh, en, ja)")
    parser.add_argument("--no-sse", action="store_true", help="Disable SSE streaming")
    parser.add_argument("--delay", type=float, default=0.5, help="Delay between segments (seconds)")

    args = parser.parse_args()

    # Validate audio file
    if not os.path.exists(args.audio_file):
        print(f"Error: Audio file not found: {args.audio_file}")
        sys.exit(1)

    # Get API key
    try:
        api_key = args.api_key or get_api_key()
    except ValueError as e:
        print(f"Error: {e}")
        sys.exit(1)

    # Run test
    asyncio.run(run_test(
        audio_file=args.audio_file,
        base_url=args.base_url,
        api_key=api_key,
        target_language=args.target_language,
        use_sse=not args.no_sse,
        delay=args.delay
    ))


if __name__ == "__main__":
    main()
