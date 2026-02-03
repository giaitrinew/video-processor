#!/bin/bash
set -e

# Args
INPUT_FILE="$1"
INTRO_FILE="$2"
FLIP="$3"
AUDIO_FILE="$4"
OUTPUT_FILE="$5"

if [ -z "$INPUT_FILE" ] || [ -z "$OUTPUT_FILE" ]; then
  echo "❌ Usage:"
  echo "  $0 input.mp4 [intro.mp4] flip [audio.mp3] output.mp4"
  echo "  flip: 0 = normal, 1 = hflip"
  exit 1
fi

# -----------------------------
# Base filter cho video dọc
# -----------------------------
BASE_FILTER="scale=1080:1920:force_original_aspect_ratio=decrease,pad=1080:1920:(ow-iw)/2:(oh-ih)/2,setsar=1:1,fps=30"

if [ "$FLIP" -eq 1 ]; then
  VF_INPUT="$BASE_FILTER,hflip"
else
  VF_INPUT="$BASE_FILTER"
fi

VF_INTRO="$BASE_FILTER"

# -----------------------------
# Encode INPUT
# -----------------------------
echo "🎬 Encode INPUT..."
ffmpeg -y -i "$INPUT_FILE" \
  -vf "$VF_INPUT" \
  -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p -profile:v high \
  -c:a aac -b:a 192k -ar 44100 \
  -movflags +faststart -fflags +genpts \
  input_encoded.mp4

FINAL_VIDEO="input_encoded.mp4"

# -----------------------------
# Encode + concat INTRO (nếu có)
# -----------------------------
if [ -n "$INTRO_FILE" ] && [ -f "$INTRO_FILE" ]; then
  echo "🎬 Encode INTRO..."
  ffmpeg -y -i "$INTRO_FILE" \
    -vf "$VF_INTRO" \
    -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p -profile:v high \
    -c:a aac -b:a 192k -ar 44100 \
    -movflags +faststart -fflags +genpts \
    intro_encoded.mp4

  echo "📝 Create concat list..."
  cat > list.txt <<EOF
file 'intro_encoded.mp4'
file 'input_encoded.mp4'
EOF

  echo "🔗 Concat intro + main..."
  ffmpeg -y -f concat -safe 0 -i list.txt -c copy merged_temp.mp4

  FINAL_VIDEO="merged_temp.mp4"
fi

# -----------------------------
# Final encode + AUDIO
# -----------------------------
if [ -n "$AUDIO_FILE" ] && [ -f "$AUDIO_FILE" ]; then
  echo "🎵 Replace audio bằng MP3..."

  ffmpeg -y \
    -i "$FINAL_VIDEO" \
    -stream_loop -1 -i "$AUDIO_FILE" \
    -map 0:v:0 -map 1:a:0 \
    -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p -profile:v high \
    -c:a aac -b:a 192k -ar 44100 \
    -shortest \
    -movflags +faststart \
    -vsync 2 -avoid_negative_ts make_zero \
    -video_track_timescale 30 \
    "$OUTPUT_FILE"
else
  echo "👉 Không có MP3, giữ audio gốc..."

  ffmpeg -y -i "$FINAL_VIDEO" \
    -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p -profile:v high \
    -c:a aac -b:a 192k -ar 44100 \
    -movflags +faststart \
    -vsync 2 -avoid_negative_ts make_zero \
    -video_track_timescale 30 \
    "$OUTPUT_FILE"
fi

echo "✅ DONE: $OUTPUT_FILE"
