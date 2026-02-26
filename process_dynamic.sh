#!/bin/bash
set -e

# Args
INPUT_FILE="$1"
INTRO_FILE="$2"
FLIP="$3"
AUDIO_FILE="$4"
OUTPUT_FILE="$5"

if [ -z "$INPUT_FILE" ] || [ -z "$OUTPUT_FILE" ]; then
  echo "❌ Usage: $0 input.mp4 [intro.mp4] flip [audio.mp3] output.mp4"
  exit 1
fi

# ---------------------------------------------------------
# 1. THIẾT LẬP BITRATE SÀN (Min 8000k)
# ---------------------------------------------------------
MIN_BITRATE_BITS=8000000 # 8000k tính bằng bits/s

# Lấy bitrate gốc từ file input
ORIGINAL_BITRATE=$(ffprobe -v error -select_streams v:0 -show_entries stream=bitrate -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE")

# Kiểm tra nếu không có bitrate hoặc bitrate thấp hơn sàn 8000k
if [ -z "$ORIGINAL_BITRATE" ] || [ "$ORIGINAL_BITRATE" = "N/A" ] || [ "$ORIGINAL_BITRATE" -lt "$MIN_BITRATE_BITS" ]; then
    echo "⚠️ Bitrate gốc thấp hoặc không có, ép lên sàn 8000k"
    V_BITRATE="8000k"
    BUF_SIZE="16000k"
else
    # Nếu bitrate gốc cao hơn 8000k, lấy gốc + 10% cho nét hẳn
    V_BITRATE="$((ORIGINAL_BITRATE * 110 / 100 / 1000))k"
    BUF_SIZE="$((ORIGINAL_BITRATE * 2 / 1000))k"
fi

echo "📊 Target Bitrate: $V_BITRATE"

# -----------------------------
# Base filter (Cố định 1080p)
# -----------------------------
BASE_FILTER="scale=1080:1920:force_original_aspect_ratio=decrease,pad=1080:1920:(ow-iw)/2:(oh-ih)/2,setsar=1:1,fps=30"
[ "$FLIP" -eq 1 ] && VF_INPUT="$BASE_FILTER,hflip" || VF_INPUT="$BASE_FILTER"

# -----------------------------
# 2. Encode INPUT
# -----------------------------
echo "🎬 Encode INPUT..."
ffmpeg -y -i "$INPUT_FILE" \
  -vf "$VF_INPUT" \
  -c:v libx264 -b:v "$V_BITRATE" -maxrate "$V_BITRATE" -bufsize "$BUF_SIZE" \
  -preset slow -pix_fmt yuv420p -profile:v high \
  -c:a aac -b:a 192k -ar 44100 \
  -movflags +faststart -fflags +genpts \
  input_encoded.mp4

FINAL_VIDEO="input_encoded.mp4"

# -----------------------------
# 3. Encode + concat INTRO (Intro sau)
# -----------------------------
if [ -n "$INTRO_FILE" ] && [ -f "$INTRO_FILE" ]; then
  echo "🎬 Encode INTRO..."
  ffmpeg -y -i "$INTRO_FILE" \
    -vf "$BASE_FILTER" \
    -c:v libx264 -b:v "$V_BITRATE" -maxrate "$V_BITRATE" -bufsize "$BUF_SIZE" \
    -preset slow -pix_fmt yuv420p \
    -c:a aac -b:a 192k -ar 44100 \
    intro_encoded.mp4

  # Ghi danh sách (Video chính -> Intro)
  echo "file 'input_encoded.mp4'" > list.txt
  echo "file 'intro_encoded.mp4'" >> list.txt

  ffmpeg -y -f concat -safe 0 -i list.txt -c copy merged_temp.mp4
  FINAL_VIDEO="merged_temp.mp4"
fi

# -----------------------------
# 4. Final encode + AUDIO
# -----------------------------
if [ -n "$AUDIO_FILE" ] && [ -f "$AUDIO_FILE" ]; then
  echo "🎵 Replace audio & Finalizing..."
  DUR=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$FINAL_VIDEO")
  
  ffmpeg -y -i "$FINAL_VIDEO" -i "$AUDIO_FILE" \
    -filter_complex "[1:a]aloop=loop=-1:size=2e+09[aud]; [aud]atrim=0:$DUR[aud2]" \
    -map 0:v:0 -map "[aud2]" \
    -c:v libx264 -b:v "$V_BITRATE" -maxrate "$V_BITRATE" -bufsize "$BUF_SIZE" \
    -preset slow -pix_fmt yuv420p \
    -c:a aac -b:a 192k -ar 44100 \
    -movflags +faststart -vsync 2 \
    "$OUTPUT_FILE"
else
  # Nén lại lần cuối để đồng bộ bitrate sàn
  ffmpeg -y -i "$FINAL_VIDEO" \
    -c:v libx264 -b:v "$V_BITRATE" -maxrate "$V_BITRATE" -bufsize "$BUF_SIZE" \
    -preset slow -c:a copy "$OUTPUT_FILE"
fi

echo "✅ DONE: $OUTPUT_FILE"
