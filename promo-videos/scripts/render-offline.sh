#!/bin/zsh
set -euo pipefail

PROJECT_DIR=${0:A:h:h}
FRAME_DIR="$PROJECT_DIR/out/offline/styleframes"
SEGMENT_DIR="$PROJECT_DIR/out/offline/segments"
VIDEO_DIR="$PROJECT_DIR/out/final"
TMP_DIR=$(mktemp -d /tmp/daisy-promo-render.XXXXXX)
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$SEGMENT_DIR" "$VIDEO_DIR"

render_segment() {
  local still_name=$1
  local duration=$2
  local output_path=$3
  local frames=$(( duration * 30 ))
  local fade_out_start=$(awk "BEGIN { print $duration - 0.28 }")
  if [[ -s $output_path && $output_path -nt "$FRAME_DIR/$still_name.png" ]]; then
    return
  fi
  ffmpeg -hide_banner -loglevel error -y \
    -loop 1 -framerate 30 -i "$FRAME_DIR/$still_name.png" \
    -vf "scale=2016:1134,crop=1920:1080:x='48+12*sin(n/75)':y='27+8*cos(n/85)',fade=t=in:st=0:d=0.28:color=white,fade=t=out:st=$fade_out_start:d=0.28:color=white,format=yuv420p" \
    -frames:v "$frames" -r 30 -an -c:v libx264 -preset medium -crf 17 "$output_path"
}

render_hero_segment() {
  local duration=$1
  local output_path=$2
  local frames=$(( duration * 30 ))
  local fade_out_start=$(awk "BEGIN { print $duration - 0.28 }")
  ffmpeg -hide_banner -loglevel error -y \
    -loop 1 -framerate 30 -i "$FRAME_DIR/hero-pin-bg.png" \
    -loop 1 -framerate 30 -i "$PROJECT_DIR/out/offline/assets/minimal-unpinned-shadow.png" \
    -loop 1 -framerate 30 -i "$PROJECT_DIR/out/offline/assets/minimal-pinned-shadow.png" \
    -filter_complex "[0:v]format=rgba[bg];[1:v]format=rgba,fade=t=out:st=1.55:d=0.28:alpha=1[unpinned];[2:v]format=rgba,fade=t=in:st=1.48:d=0.28:alpha=1[pinned];[bg][unpinned]overlay=x='1060+90*exp(-t*2.4)':y='175+105*exp(-t*2.0)*cos(t*6.4)':eval=frame[v1];[v1][pinned]overlay=x='1060+90*exp(-t*2.4)':y='175+105*exp(-t*2.0)*cos(t*6.4)':eval=frame,fade=t=in:st=0:d=0.28:color=white,fade=t=out:st=$fade_out_start:d=0.28:color=white,format=yuv420p[out]" \
    -map '[out]' -frames:v "$frames" -r 30 -an -c:v libx264 -preset medium -crf 17 "$output_path"
}

render_passing_segment() {
  local duration=$1
  local output_path=$2
  local frames=$(( duration * 30 ))
  local fade_out_start=$(awk "BEGIN { print $duration - 0.28 }")
  ffmpeg -hide_banner -loglevel error -y \
    -loop 1 -framerate 30 -i "$FRAME_DIR/hero-pin-passing-bg.png" \
    -loop 1 -framerate 30 -i "$PROJECT_DIR/out/offline/assets/passing-text.png" \
    -loop 1 -framerate 30 -i "$PROJECT_DIR/out/offline/assets/minimal-pinned-shadow.png" \
    -filter_complex "[0:v]format=rgba[bg];[1:v]format=rgba[text];[2:v]format=rgba[window];[bg][text]overlay=x='420-210*t':y=205:eval=frame[v1];[v1][window]overlay=x=1060:y=180,fade=t=in:st=0:d=0.28:color=white,fade=t=out:st=$fade_out_start:d=0.28:color=white,format=yuv420p[out]" \
    -map '[out]' -frames:v "$frames" -r 30 -an -c:v libx264 -preset medium -crf 17 "$output_path"
}

render_popup_segment() {
  local duration=$1
  local output_path=$2
  local frames=$(( duration * 30 ))
  local fade_out_start=$(awk "BEGIN { print $duration - 0.28 }")
  ffmpeg -hide_banner -loglevel error -y \
    -loop 1 -framerate 30 -i "$FRAME_DIR/popup-bg.png" \
    -loop 1 -framerate 30 -i "$PROJECT_DIR/out/offline/assets/quick-popup-shadow.png" \
    -filter_complex "[0:v]format=rgba[bg];[1:v]format=rgba,fade=t=in:st=0.45:d=0.32:alpha=1[popup];[bg][popup]overlay=x=1090:y='470+58*exp(-max(0,t-0.45)*3.2)*cos(max(0,t-0.45)*8.2)':eval=frame,fade=t=in:st=0:d=0.28:color=white,fade=t=out:st=$fade_out_start:d=0.28:color=white,format=yuv420p[out]" \
    -map '[out]' -frames:v "$frames" -r 30 -an -c:v libx264 -preset medium -crf 17 "$output_path"
}

render_auto_segment() {
  local duration=$1
  local output_path=$2
  local frames=$(( duration * 30 ))
  local fade_out_start=$(awk "BEGIN { print $duration - 0.28 }")
  local workflow_end=$(awk "BEGIN { print $duration * 0.34 }")
  local workflow_fade=$(awk "BEGIN { print $duration * 0.34 - 0.30 }")
  local window_start=$(awk "BEGIN { print $duration * 0.34 - 0.18 }")
  local result_start=$(awk "BEGIN { print $duration * 0.61 }")
  local waiting_fade=$(awk "BEGIN { print $duration * 0.61 - 0.24 }")
  local result_fade=$(awk "BEGIN { print $duration * 0.61 - 0.14 }")
  ffmpeg -hide_banner -loglevel error -y \
    -loop 1 -framerate 30 -i "$FRAME_DIR/auto-bg.png" \
    -loop 1 -framerate 30 -i "$PROJECT_DIR/out/offline/assets/workflow-automation-shadow.png" \
    -loop 1 -framerate 30 -i "$PROJECT_DIR/out/offline/assets/auto-waiting-shadow.png" \
    -loop 1 -framerate 30 -i "$PROJECT_DIR/out/offline/assets/minimal-auto-shadow.png" \
    -loop 1 -framerate 30 -i "$PROJECT_DIR/out/offline/assets/auto-line.png" \
    -filter_complex "[0:v]format=rgba[bg];[1:v]format=rgba,fade=t=out:st=$workflow_fade:d=0.30:alpha=1[workflow];[2:v]format=rgba,fade=t=in:st=$window_start:d=0.30:alpha=1,fade=t=out:st=$waiting_fade:d=0.30:alpha=1[waiting];[3:v]format=rgba,fade=t=in:st=$result_fade:d=0.30:alpha=1[result];[4:v]format=rgba,fade=t=in:st=$waiting_fade:d=0.20:alpha=1,fade=t=out:st=$result_start:d=0.35:alpha=1[line];[bg][workflow]overlay=x=830:y=175[v1];[v1][waiting]overlay=x=1070:y=185[v2];[v2][result]overlay=x=1070:y=185[v3];[v3][line]overlay=x=1437:y=430,fade=t=in:st=0:d=0.28:color=white,fade=t=out:st=$fade_out_start:d=0.28:color=white,format=yuv420p[out]" \
    -map '[out]' -frames:v "$frames" -r 30 -an -c:v libx264 -preset medium -crf 17 "$output_path"
}

render_ai_embed_segment() {
  local duration=$1
  local output_path=$2
  local frames=$(( duration * 30 ))
  local fade_out_start=$(awk "BEGIN { print $duration - 0.28 }")
  ffmpeg -hide_banner -loglevel error -y \
    -loop 1 -framerate 30 -i "$FRAME_DIR/ai-montage-bg.png" \
    -loop 1 -framerate 30 -i "$PROJECT_DIR/out/offline/assets/provider-apple-row-shadow.png" \
    -loop 1 -framerate 30 -i "$PROJECT_DIR/out/offline/assets/provider-ollama-row-shadow.png" \
    -loop 1 -framerate 30 -i "$PROJECT_DIR/out/offline/assets/provider-openai-row-shadow.png" \
    -loop 1 -framerate 30 -i "$PROJECT_DIR/out/offline/assets/provider-deepseek-row-shadow.png" \
    -filter_complex "[0:v]format=rgba[bg];[1:v]format=rgba,fade=t=in:st=0.18:d=0.28:alpha=1[r1];[2:v]format=rgba,fade=t=in:st=0.62:d=0.28:alpha=1[r2];[3:v]format=rgba,fade=t=in:st=1.02:d=0.28:alpha=1[r3];[4:v]format=rgba,fade=t=in:st=1.38:d=0.28:alpha=1[r4];[bg][r1]overlay=x='700+max(0,0.65-t)*520':y=175:eval=frame[v1];[v1][r2]overlay=x='700+max(0,1.09-t)*520':y=365:eval=frame[v2];[v2][r3]overlay=x='700+max(0,1.49-t)*520':y=555:eval=frame[v3];[v3][r4]overlay=x='700+max(0,1.85-t)*520':y=745:eval=frame,fade=t=in:st=0:d=0.28:color=white,fade=t=out:st=$fade_out_start:d=0.28:color=white,format=yuv420p[out]" \
    -map '[out]' -frames:v "$frames" -r 30 -an -c:v libx264 -preset medium -crf 17 "$output_path"
}

render_waterfall_segment() {
  local duration=$1
  local output_path=$2
  local frames=$(( duration * 30 ))
  local fade_out_start=$(awk "BEGIN { print $duration - 0.28 }")
  ffmpeg -hide_banner -loglevel error -y \
    -loop 1 -framerate 30 -i "$FRAME_DIR/waterfall-bg.png" \
    -loop 1 -framerate 30 -i "$PROJECT_DIR/out/offline/assets/waterfall-col-1.png" \
    -loop 1 -framerate 30 -i "$PROJECT_DIR/out/offline/assets/waterfall-col-1.png" \
    -loop 1 -framerate 30 -i "$PROJECT_DIR/out/offline/assets/waterfall-col-2.png" \
    -loop 1 -framerate 30 -i "$PROJECT_DIR/out/offline/assets/waterfall-col-2.png" \
    -loop 1 -framerate 30 -i "$PROJECT_DIR/out/offline/assets/waterfall-col-3.png" \
    -loop 1 -framerate 30 -i "$PROJECT_DIR/out/offline/assets/waterfall-col-3.png" \
    -filter_complex "[0:v]format=rgba[bg];[1:v]format=rgba[c1a];[2:v]format=rgba[c1b];[3:v]format=rgba[c2a];[4:v]format=rgba[c2b];[5:v]format=rgba[c3a];[6:v]format=rgba[c3b];[bg][c1a]overlay=x=640:y='-1500+mod(t*105,1500)':eval=frame[v1];[v1][c1b]overlay=x=640:y='mod(t*105,1500)':eval=frame[v2];[v2][c2a]overlay=x=1070:y='-mod(t*82,1500)':eval=frame[v3];[v3][c2b]overlay=x=1070:y='1500-mod(t*82,1500)':eval=frame[v4];[v4][c3a]overlay=x=1500:y='-1500+mod(t*118,1500)':eval=frame[v5];[v5][c3b]overlay=x=1500:y='mod(t*118,1500)':eval=frame,fade=t=in:st=0:d=0.28:color=white,fade=t=out:st=$fade_out_start:d=0.28:color=white,format=yuv420p[out]" \
    -map '[out]' -frames:v "$frames" -r 30 -an -c:v libx264 -preset medium -crf 17 "$output_path"
}

render_outro_segment() {
  local duration=$1
  local output_path=$2
  local frames=$(( duration * 30 ))
  local fade_out_start=$(awk "BEGIN { print $duration - 0.28 }")
  ffmpeg -hide_banner -loglevel error -y \
    -loop 1 -framerate 30 -i "$FRAME_DIR/outro-bg.png" \
    -loop 1 -framerate 30 -i "$PROJECT_DIR/out/offline/assets/minimal-pinned-shadow.png" \
    -loop 1 -framerate 30 -i "$PROJECT_DIR/out/offline/assets/quick-popup-shadow.png" \
    -loop 1 -framerate 30 -i "$PROJECT_DIR/out/offline/assets/settings-openai-shadow.png" \
    -loop 1 -framerate 30 -i "$PROJECT_DIR/out/offline/assets/minimal-auto-shadow.png" \
    -loop 1 -framerate 30 -i "$PROJECT_DIR/out/offline/assets/outro-center.png" \
    -filter_complex "[0:v]format=rgba[bg];[1:v]scale=430:-1,format=rgba,fade=t=in:st=0.05:d=0.30:alpha=1[a1];[2:v]scale=460:-1,format=rgba,fade=t=in:st=0.18:d=0.30:alpha=1[a2];[3:v]scale=500:-1,format=rgba,fade=t=in:st=0.30:d=0.30:alpha=1[a3];[4:v]scale=430:-1,format=rgba,fade=t=in:st=0.42:d=0.30:alpha=1[a4];[5:v]format=rgba,fade=t=in:st=0.92:d=0.34:alpha=1[center];[bg][a1]overlay=x='95-520*exp(-t*3.0)':y='150-280*exp(-t*3.0)':eval=frame[v1];[v1][a2]overlay=x='1330+520*exp(-max(0,t-0.12)*3.0)':y='165-260*exp(-max(0,t-0.12)*3.0)':eval=frame[v2];[v2][a3]overlay=x='1260+460*exp(-max(0,t-0.24)*3.0)':y='650+300*exp(-max(0,t-0.24)*3.0)':eval=frame[v3];[v3][a4]overlay=x='130-500*exp(-max(0,t-0.36)*3.0)':y='710+300*exp(-max(0,t-0.36)*3.0)':eval=frame[v4];[v4][center]overlay=x=645:y=260,fade=t=in:st=0:d=0.28:color=white,fade=t=out:st=$fade_out_start:d=0.28:color=white,format=yuv420p[out]" \
    -map '[out]' -frames:v "$frames" -r 30 -an -c:v libx264 -preset medium -crf 17 "$output_path"
}

render_brand_settle_segment() {
  local still_name=$1
  local duration=$2
  local output_path=$3
  local frames=$(( duration * 30 ))
  local fade_out_start=$(awk "BEGIN { print $duration - 0.28 }")
  ffmpeg -hide_banner -loglevel error -y \
    -loop 1 -framerate 30 -i "$FRAME_DIR/$still_name.png" \
    -vf "zoompan=z='max(1.0,1.08-0.08*min(on/36,1))':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=1:s=1920x1080:fps=30,fade=t=in:st=0:d=0.28:color=white,fade=t=out:st=$fade_out_start:d=0.28:color=white,format=yuv420p" \
    -frames:v "$frames" -r 30 -an -c:v libx264 -preset medium -crf 17 "$output_path"
}

render_named_segment() {
  local still_name=$1
  local duration=$2
  local output_path=$3
  case "$still_name" in
    hero-pin-dynamic) render_hero_segment "$duration" "$output_path" ;;
    hero-pin-passing-dynamic) render_passing_segment "$duration" "$output_path" ;;
    popup-dynamic) render_popup_segment "$duration" "$output_path" ;;
    auto-dynamic) render_auto_segment "$duration" "$output_path" ;;
    ai-montage-dynamic) render_ai_embed_segment "$duration" "$output_path" ;;
    waterfall-dynamic) render_waterfall_segment "$duration" "$output_path" ;;
    outro-dynamic) render_outro_segment "$duration" "$output_path" ;;
    outro-pinned|outro-auto|outro-ai) render_brand_settle_segment "$still_name" "$duration" "$output_path" ;;
    *) render_segment "$still_name" "$duration" "$output_path" ;;
  esac
}

concat_video() {
  local composition=$1
  shift
  local list_path="$TMP_DIR/$composition.txt"
  : > "$list_path"
  local index=0
  while (( $# >= 2 )); do
    local still_name=$1
    local duration=$2
    shift 2
    local segment_path="$SEGMENT_DIR/${composition}-${index}.mp4"
    render_named_segment "$still_name" "$duration" "$segment_path"
    print -r -- "file '$segment_path'" >> "$list_path"
    index=$(( index + 1 ))
  done
  ffmpeg -hide_banner -loglevel error -y -f concat -safe 0 -i "$list_path" -c copy "$TMP_DIR/$composition-video.mp4"
}

mix_versions() {
  local composition=$1
  local duration=$2
  shift 2
  local bgm_path="$PROJECT_DIR/public/audio/bgm-tech-house.mp3"
  local video_path="$TMP_DIR/$composition-video.mp4"
  local with_bgm_path="$VIDEO_DIR/$composition.mp4"
  local no_bgm_path="$VIDEO_DIR/${composition}-no-bgm.mp4"
  local duration_ms=$(( duration * 1000 ))
  local bgm_fade_out=$(( duration - 2 ))

  local event_inputs=()
  local event_filters=''
  local event_labels=()
  local input_index=1
  while (( $# >= 3 )); do
    local event_file=$1
    local event_ms=$2
    local event_volume=$3
    shift 3
    event_inputs+=( -i "$PROJECT_DIR/public/audio/$event_file" )
    event_filters+="[${input_index}:a]aformat=sample_rates=48000:channel_layouts=stereo,volume=${event_volume},adelay=delays=${event_ms}:all=1,atrim=0:${duration}[a${input_index}];"
    event_labels+=( "[a${input_index}]" )
    input_index=$(( input_index + 1 ))
  done

  local joined_labels=${(j::)event_labels}
  ffmpeg -hide_banner -loglevel error -y \
    -stream_loop -1 -i "$bgm_path" "${event_inputs[@]}" \
    -filter_complex "[0:a]aformat=sample_rates=48000:channel_layouts=stereo,atrim=0:${duration},volume=0.30,afade=t=in:st=0:d=1,afade=t=out:st=${bgm_fade_out}:d=2[bgm];${event_filters}[bgm]${joined_labels}amix=inputs=${input_index}:normalize=0:duration=longest,alimiter=limit=0.92,atrim=0:${duration}[aout]" \
    -i "$video_path" -map "$input_index:v:0" -map '[aout]' -c:v copy -c:a aac -b:a 256k -t "$duration" -movflags +faststart "$with_bgm_path"

  local no_bgm_inputs=()
  local no_bgm_filters=''
  local no_bgm_labels=()
  local no_bgm_index=0
  local event_args=( "$@" )
  # Rebuild from the event files already registered above.
  for event_input in "${event_inputs[@]}"; do
    if [[ $event_input == -i ]]; then continue; fi
    no_bgm_inputs+=( -i "$event_input" )
  done
  # `event_filters` starts at input 1 for the BGM mix; shift every audio label
  # down by one for the no-BGM graph.
  no_bgm_filters=$(print -r -- "$event_filters" | perl -pe 's/\[(\d+):a\]/"[".($1-1).":a]"/ge; s/\[a(\d+)\]/"[n".($1-1)."]"/ge')
  for (( no_bgm_index = 0; no_bgm_index < ${#no_bgm_inputs[@]} / 2; no_bgm_index++ )); do
    no_bgm_labels+=( "[n${no_bgm_index}]" )
  done
  local no_bgm_joined=${(j::)no_bgm_labels}
  local no_bgm_count=${#no_bgm_labels[@]}
  ffmpeg -hide_banner -loglevel error -y \
    "${no_bgm_inputs[@]}" \
    -filter_complex "${no_bgm_filters}${no_bgm_joined}amix=inputs=${no_bgm_count}:normalize=0:duration=longest,alimiter=limit=0.92,atrim=0:${duration}[aout]" \
    -i "$video_path" -map "$no_bgm_count:v:0" -map '[aout]' -c:v copy -c:a aac -b:a 256k -t "$duration" -movflags +faststart "$no_bgm_path"
}

concat_video DaisyOverview \
  brand-overview 3 \
  hero-pin-dynamic 5 \
  popup-dynamic 5 \
  auto-dynamic 4 \
  ai-montage-dynamic 4 \
  waterfall-dynamic 4 \
  outro-dynamic 5
mix_versions DaisyOverview 30 \
  transition-soft.mp3 350 0.28 \
  whoosh-big.mp3 3050 0.38 \
  transition-soft.mp3 8000 0.28 \
  swoosh-quick.mp3 12600 0.32 \
  transition-soft.mp3 17000 0.28 \
  whoosh-big.mp3 21100 0.34 \
  riser-cine.mp3 25000 0.34 \
  impact-deep-whoosh.mp3 26200 0.48 \
  sparkle.mp3 27000 0.30

concat_video DaisyPinned \
  brand-pinned 2 \
  hero-pin-dynamic 5 \
  hero-pin-passing-dynamic 4 \
  outro-pinned 4
mix_versions DaisyPinned 15 \
  transition-soft.mp3 300 0.28 \
  whoosh-big.mp3 2050 0.40 \
  transition-soft.mp3 7000 0.26 \
  riser-cine.mp3 11000 0.34 \
  impact-deep-whoosh.mp3 12200 0.48 \
  sparkle.mp3 13000 0.30

concat_video DaisyAuto \
  brand-auto 2 \
  auto-dynamic 9 \
  outro-auto 4
mix_versions DaisyAuto 15 \
  transition-soft.mp3 300 0.28 \
  whoosh-big.mp3 2050 0.36 \
  swoosh-quick.mp3 6000 0.32 \
  riser-cine.mp3 11000 0.34 \
  impact-deep-whoosh.mp3 12100 0.46 \
  sparkle.mp3 12800 0.30

concat_video DaisyAI \
  brand-ai 2 \
  ai-apple 2 \
  ai-ollama 2 \
  ai-openai 2 \
  ai-deepseek 2 \
  ai-montage-dynamic 3 \
  outro-ai 2
mix_versions DaisyAI 15 \
  transition-soft.mp3 300 0.28 \
  swoosh-quick.mp3 2050 0.30 \
  swoosh-quick.mp3 4050 0.27 \
  swoosh-quick.mp3 6050 0.25 \
  swoosh-quick.mp3 8050 0.23 \
  whoosh-big.mp3 10050 0.34 \
  riser-cine.mp3 12000 0.34 \
  impact-deep-whoosh.mp3 13000 0.46 \
  sparkle.mp3 13400 0.30

echo "Rendered final videos in $VIDEO_DIR"
