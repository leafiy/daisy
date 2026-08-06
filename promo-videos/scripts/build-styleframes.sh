#!/bin/zsh
set -euo pipefail

PROJECT_DIR=${0:A:h:h}
UI_DIR="$PROJECT_DIR/public/ui/white"
ICON_PATH="$PROJECT_DIR/public/ui/daisy-icon.png"
FRAME_DIR="$PROJECT_DIR/out/offline/styleframes"
ASSET_DIR="$PROJECT_DIR/out/offline/assets"
TMP_DIR=$(mktemp -d /tmp/daisy-promo-styleframes.XXXXXX)
trap 'rm -rf "$TMP_DIR"' EXIT

BOLD_FONT='/System/Library/Fonts/STHeiti Medium.ttc'
LIGHT_FONT='/System/Library/Fonts/STHeiti Light.ttc'
INK='#111827'
SECONDARY='#667085'
BLUE='#2F7DF6'
MINT='#32C9A3'

mkdir -p "$FRAME_DIR" "$ASSET_DIR"

make_canvas() {
  local output_path=$1
  magick -size 1920x1080 xc:white \
    \( -size 820x650 xc:none -fill 'rgba(47,125,246,0.10)' -draw 'circle 410,325 410,36' -blur 0x80 \) \
    -geometry +1110-220 -composite \
    \( -size 760x620 xc:none -fill 'rgba(50,201,163,0.08)' -draw 'circle 380,310 380,34' -blur 0x86 \) \
    -geometry -250+690 -composite \
    "$output_path"
}

shadow_asset() {
  local input_path=$1
  local width=$2
  local output_path=$3
  magick "$input_path" -resize "${width}x" \
    \( +clone -background '#23324D' -shadow 18x10+0+24 \) \
    +swap -background none -layers merge "$output_path"
}

brand_card() {
  local output_name=$1
  local title=$2
  local detail=$3
  local kicker=$4
  make_canvas "$TMP_DIR/canvas.png"
  magick "$ICON_PATH" -resize 164x164 "$TMP_DIR/icon.png"
  magick "$TMP_DIR/canvas.png" \
    "$TMP_DIR/icon.png" -geometry +430+424 -composite \
    -font "$BOLD_FONT" -fill "$INK" -pointsize 92 -annotate +635+492 "$title" \
    -font "$LIGHT_FONT" -fill "$SECONDARY" -pointsize 36 -annotate +640+560 "$detail" \
    -font "$BOLD_FONT" -fill "$BLUE" -pointsize 22 -kerning 4 -annotate +640+620 "$kicker" \
    "$FRAME_DIR/$output_name.png"
}

shadow_asset "$UI_DIR/minimal-pinned.png" 720 "$ASSET_DIR/minimal-pinned-shadow.png"
shadow_asset "$UI_DIR/minimal-unpinned.png" 720 "$ASSET_DIR/minimal-unpinned-shadow.png"
shadow_asset "$UI_DIR/minimal-auto.png" 700 "$ASSET_DIR/minimal-auto-shadow.png"
shadow_asset "$UI_DIR/minimal-empty.png" 700 "$ASSET_DIR/minimal-empty-shadow.png"
shadow_asset "$UI_DIR/quick-popup.png" 680 "$ASSET_DIR/quick-popup-shadow.png"
shadow_asset "$UI_DIR/settings-apple.png" 900 "$ASSET_DIR/settings-apple-shadow.png"
shadow_asset "$UI_DIR/settings-ollama.png" 900 "$ASSET_DIR/settings-ollama-shadow.png"
shadow_asset "$UI_DIR/settings-openai.png" 900 "$ASSET_DIR/settings-openai-shadow.png"
shadow_asset "$UI_DIR/settings-deepseek.png" 900 "$ASSET_DIR/settings-deepseek-shadow.png"
magick "$UI_DIR/settings-workflow.png" -crop 1200x680+100+620 +repage \
  "$ASSET_DIR/workflow-automation-crop.png"
shadow_asset "$ASSET_DIR/workflow-automation-crop.png" 1040 "$ASSET_DIR/workflow-automation-shadow.png"
magick -size 6x190 gradient:'#2F7DF6-#32C9A3' "$ASSET_DIR/auto-line.png"

# Waiting state: the source is already present, while the production empty
# result pane remains visible. Both layers come from real Daisy captures.
magick "$UI_DIR/minimal-auto.png" \
  \( "$UI_DIR/minimal-empty.png" -crop 680x279+0+337 +repage \) -geometry +0+337 -composite \
  "$ASSET_DIR/auto-waiting.png"
shadow_asset "$ASSET_DIR/auto-waiting.png" 700 "$ASSET_DIR/auto-waiting-shadow.png"

# Exact provider rows cropped from four production settings screenshots.
for provider in apple ollama openai deepseek; do
  magick "$UI_DIR/settings-$provider.png" -crop 1160x128+120+474 +repage \
    "$ASSET_DIR/provider-$provider-row.png"
  shadow_asset "$ASSET_DIR/provider-$provider-row.png" 1160 "$ASSET_DIR/provider-$provider-row-shadow.png"
done

brand_card brand-overview 'Daisy' '翻译随处到，原文不动。' 'LIGHT · NATIVE · ALWAYS NEAR'
brand_card brand-pinned '钉住，不打断' 'Daisy stays nearby' 'PINNED AIR'
brand_card brand-auto '不用催' '它会自己开始' 'AUTO TRANSLATE'
brand_card brand-ai '从 Apple 开始' '也能接入你的 AI' 'YOUR MODEL, YOUR CHOICE'

make_canvas "$TMP_DIR/canvas.png"
magick "$TMP_DIR/canvas.png" \
  -font "$BOLD_FONT" -fill "$BLUE" -pointsize 22 -kerning 4 -annotate +150+220 'PINNED AIR' \
  -font "$BOLD_FONT" -fill "$INK" -pointsize 70 -annotate +150+340 '钉在屏幕上' \
  -font "$LIGHT_FONT" -fill "$SECONDARY" -pointsize 34 -annotate +150+412 '轻轻放在需要的位置，' \
  -annotate +150+458 '不挡住正在做的事。' \
  "$FRAME_DIR/hero-pin-bg.png"
magick "$TMP_DIR/canvas.png" \
  -font "$BOLD_FONT" -fill "$BLUE" -pointsize 22 -kerning 4 -annotate +150+220 'PINNED AIR' \
  -font "$BOLD_FONT" -fill "$INK" -pointsize 70 -annotate +150+340 '钉在屏幕上' \
  -font "$LIGHT_FONT" -fill "$SECONDARY" -pointsize 34 -annotate +150+412 '轻轻放在需要的位置，' \
  -annotate +150+458 '不挡住正在做的事。' \
  "$ASSET_DIR/minimal-pinned-shadow.png" -geometry +1110+220 -composite \
  "$FRAME_DIR/hero-pin.png"

make_canvas "$TMP_DIR/canvas.png"
magick "$TMP_DIR/canvas.png" \
  -font "$BOLD_FONT" -fill "$INK" -pointsize 66 -annotate +150+720 '工作继续，翻译一直在。' \
  "$FRAME_DIR/hero-pin-passing-bg.png"
magick -size 1750x260 xc:none \
  -font "$BOLD_FONT" -fill '#DCE3EC' -pointsize 86 -annotate +0+105 'Write. Read. Design. Build.' \
  -annotate +280+240 'The work keeps moving.' \
  "$ASSET_DIR/passing-text.png"
magick "$TMP_DIR/canvas.png" \
  -font "$BOLD_FONT" -fill '#DCE3EC' -pointsize 86 -annotate -120+370 'Write. Read. Design. Build.' \
  -annotate +160+505 'The work keeps moving.' \
  -font "$BOLD_FONT" -fill "$INK" -pointsize 66 -annotate +150+720 '工作继续，翻译一直在。' \
  "$ASSET_DIR/minimal-pinned-shadow.png" -geometry +1110+235 -composite \
  "$FRAME_DIR/hero-pin-passing.png"

make_canvas "$TMP_DIR/canvas.png"
magick "$TMP_DIR/canvas.png" \
  -font "$BOLD_FONT" -fill "$BLUE" -pointsize 21 -kerning 3 -annotate +150+235 'KEEP THE ORIGINAL' \
  -font "$BOLD_FONT" -fill "$INK" -pointsize 54 -annotate +150+350 'Keep reading in place.' \
  -fill '#EAF2FF' -stroke none -draw 'roundrectangle 140,390 1060,475 12,12' \
  -font "$BOLD_FONT" -fill "$INK" -pointsize 43 -annotate +160+450 'Meaning appears beside the original.' \
  -font "$LIGHT_FONT" -fill '#8A94A6' -pointsize 27 -annotate +150+560 'The words stay exactly where they are.' \
  -annotate +150+610 'Only Daisy appears beside them.' \
  -font "$BOLD_FONT" -fill "$INK" -pointsize 60 -annotate +1080+820 '原文不动，译文就到' \
  "$FRAME_DIR/popup-bg.png"
magick "$TMP_DIR/canvas.png" \
  -font "$BOLD_FONT" -fill "$BLUE" -pointsize 21 -kerning 3 -annotate +150+235 'KEEP THE ORIGINAL' \
  -font "$BOLD_FONT" -fill "$INK" -pointsize 54 -annotate +150+350 'Keep reading in place.' \
  -fill '#EAF2FF' -stroke none -draw 'roundrectangle 140,390 1060,475 12,12' \
  -font "$BOLD_FONT" -fill "$INK" -pointsize 43 -annotate +160+450 'Meaning appears beside the original.' \
  -font "$LIGHT_FONT" -fill '#8A94A6' -pointsize 27 -annotate +150+560 'The words stay exactly where they are.' \
  -annotate +150+610 'Only Daisy appears beside them.' \
  "$ASSET_DIR/quick-popup-shadow.png" -geometry +1090+470 -composite \
  -font "$BOLD_FONT" -fill "$INK" -pointsize 60 -annotate +1080+820 '原文不动，译文就到' \
  "$FRAME_DIR/popup.png"

for state in waiting result; do
  make_canvas "$TMP_DIR/canvas.png"
  state_asset="$ASSET_DIR/auto-${state}-shadow.png"
  if [[ $state == result ]]; then state_asset="$ASSET_DIR/minimal-auto-shadow.png"; fi
  magick "$TMP_DIR/canvas.png" \
    -font "$BOLD_FONT" -fill "$BLUE" -pointsize 22 -kerning 4 -annotate +150+260 'NO SUBMIT BUTTON' \
    -font "$BOLD_FONT" -fill "$INK" -pointsize 68 -annotate +150+380 '停下输入，自动翻译' \
    -font "$LIGHT_FONT" -fill "$SECONDARY" -pointsize 34 -annotate +150+455 '不复制，不切换，不粘贴。' \
    -annotate +150+503 '结果在原位自然出现。' \
    "$state_asset" -geometry +1070+185 -composite \
    "$FRAME_DIR/auto-$state.png"
done

make_canvas "$TMP_DIR/canvas.png"
magick "$TMP_DIR/canvas.png" \
  -font "$BOLD_FONT" -fill "$BLUE" -pointsize 22 -kerning 4 -annotate +150+260 'NO SUBMIT BUTTON' \
  -font "$BOLD_FONT" -fill "$INK" -pointsize 68 -annotate +150+380 '停下输入，自动翻译' \
  -font "$LIGHT_FONT" -fill "$SECONDARY" -pointsize 34 -annotate +150+455 '不复制，不切换，不粘贴。' \
  -annotate +150+503 '结果在原位自然出现。' \
  "$FRAME_DIR/auto-bg.png"

for provider in apple ollama openai deepseek; do
  provider_title='Apple System Translation'
  [[ $provider == ollama ]] && provider_title='Ollama · Local'
  [[ $provider == openai ]] && provider_title='OpenAI-compatible'
  [[ $provider == deepseek ]] && provider_title='DeepSeek'
  make_canvas "$TMP_DIR/canvas.png"
  magick "$TMP_DIR/canvas.png" \
    -font "$BOLD_FONT" -fill "$BLUE" -pointsize 22 -kerning 4 -annotate +130+245 'APPLE + AI SERVICES' \
    -font "$BOLD_FONT" -fill "$INK" -pointsize 64 -annotate +130+360 'Apple 起步，' \
    -annotate +130+440 '也能接入 AI' \
    -font "$LIGHT_FONT" -fill "$SECONDARY" -pointsize 34 -annotate +130+525 "$provider_title" \
    "$ASSET_DIR/settings-$provider-shadow.png" -geometry +970+80 -composite \
    "$FRAME_DIR/ai-$provider.png"
done

make_canvas "$TMP_DIR/canvas.png"
magick "$TMP_DIR/canvas.png" \
  -font "$BOLD_FONT" -fill "$BLUE" -pointsize 22 -kerning 4 -annotate +130+245 'YOUR MODEL, YOUR CHOICE' \
  -font "$BOLD_FONT" -fill "$INK" -pointsize 64 -annotate +130+360 '一个入口，' \
  -annotate +130+438 '多种引擎' \
  -font "$LIGHT_FONT" -fill "$SECONDARY" -pointsize 34 -annotate +130+525 '系统、本地、自定义服务。' \
  "$FRAME_DIR/ai-montage-bg.png"
magick "$TMP_DIR/canvas.png" \
  -font "$BOLD_FONT" -fill "$BLUE" -pointsize 22 -kerning 4 -annotate +130+245 'YOUR MODEL, YOUR CHOICE' \
  -font "$BOLD_FONT" -fill "$INK" -pointsize 64 -annotate +130+360 '一个入口，' \
  -annotate +130+438 '多种引擎' \
  -font "$LIGHT_FONT" -fill "$SECONDARY" -pointsize 34 -annotate +130+525 '系统、本地、自定义服务。' \
  "$ASSET_DIR/provider-apple-row-shadow.png" -geometry +700+175 -composite \
  "$ASSET_DIR/provider-ollama-row-shadow.png" -geometry +700+365 -composite \
  "$ASSET_DIR/provider-openai-row-shadow.png" -geometry +700+555 -composite \
  "$ASSET_DIR/provider-deepseek-row-shadow.png" -geometry +700+745 -composite \
  "$FRAME_DIR/ai-montage.png"

make_canvas "$TMP_DIR/canvas.png"
magick "$TMP_DIR/canvas.png" \
  -font "$BOLD_FONT" -fill "$BLUE" -pointsize 22 -kerning 4 -annotate +130+275 'ONE LIGHT TOOL' \
  -font "$BOLD_FONT" -fill "$INK" -pointsize 72 -annotate +130+395 '小而完整' \
  -font "$LIGHT_FONT" -fill "$SECONDARY" -pointsize 34 -annotate +130+480 '固定、浮层、自动翻译、' \
  -annotate +130+528 'AI 接入，都在 Daisy 里。' \
  "$FRAME_DIR/waterfall-bg.png"
magick -size 430x1500 xc:none \
  \( "$ASSET_DIR/minimal-pinned-shadow.png" -resize 360x \) -geometry +35+20 -composite \
  \( "$ASSET_DIR/quick-popup-shadow.png" -resize 400x \) -geometry +15+410 -composite \
  \( "$ASSET_DIR/settings-apple-shadow.png" -resize 400x \) -geometry +15+690 -composite \
  \( "$ASSET_DIR/minimal-auto-shadow.png" -resize 350x \) -geometry +40+1110 -composite \
  "$ASSET_DIR/waterfall-col-1.png"
magick -size 430x1500 xc:none \
  \( "$ASSET_DIR/settings-openai-shadow.png" -resize 400x \) -geometry +15+30 -composite \
  \( "$ASSET_DIR/minimal-auto-shadow.png" -resize 350x \) -geometry +40+440 -composite \
  \( "$ASSET_DIR/quick-popup-shadow.png" -resize 400x \) -geometry +15+850 -composite \
  \( "$ASSET_DIR/minimal-pinned-shadow.png" -resize 350x \) -geometry +40+1120 -composite \
  "$ASSET_DIR/waterfall-col-2.png"
magick -size 430x1500 xc:none \
  \( "$ASSET_DIR/quick-popup-shadow.png" -resize 400x \) -geometry +15+20 -composite \
  \( "$ASSET_DIR/settings-ollama-shadow.png" -resize 400x \) -geometry +15+300 -composite \
  \( "$ASSET_DIR/minimal-pinned-shadow.png" -resize 350x \) -geometry +40+730 -composite \
  \( "$ASSET_DIR/settings-deepseek-shadow.png" -resize 400x \) -geometry +15+1080 -composite \
  "$ASSET_DIR/waterfall-col-3.png"
magick "$ASSET_DIR/minimal-pinned-shadow.png" -resize 440x -alpha set -background none -rotate -5 "$TMP_DIR/pin.png"
magick "$ASSET_DIR/quick-popup-shadow.png" -resize 520x -alpha set -background none -rotate 4 "$TMP_DIR/popup.png"
magick "$ASSET_DIR/settings-apple-shadow.png" -resize 560x -alpha set -background none -rotate 3 "$TMP_DIR/settings.png"
magick "$ASSET_DIR/minimal-auto-shadow.png" -resize 400x -alpha set -background none -rotate -3 "$TMP_DIR/auto.png"
magick "$TMP_DIR/canvas.png" \
  "$TMP_DIR/pin.png" -geometry +690+110 -composite \
  "$TMP_DIR/popup.png" -geometry +1230+190 -composite \
  "$TMP_DIR/settings.png" -geometry +1050+545 -composite \
  "$TMP_DIR/auto.png" -geometry +570+640 -composite \
  -font "$BOLD_FONT" -fill "$BLUE" -pointsize 22 -kerning 4 -annotate +130+275 'ONE LIGHT TOOL' \
  -font "$BOLD_FONT" -fill "$INK" -pointsize 72 -annotate +130+395 '小而完整' \
  -font "$LIGHT_FONT" -fill "$SECONDARY" -pointsize 34 -annotate +130+480 '固定、浮层、自动翻译、' \
  -annotate +130+528 'AI 接入，都在 Daisy 里。' \
  "$FRAME_DIR/breadth.png"

make_canvas "$TMP_DIR/canvas.png"
cp "$TMP_DIR/canvas.png" "$FRAME_DIR/outro-bg.png"
magick "$ICON_PATH" -resize 132x132 "$TMP_DIR/icon.png"
magick -size 630x570 xc:none \
  -fill 'rgba(255,255,255,0.96)' -stroke '#E8ECF2' -strokewidth 2 -draw 'roundrectangle 0,0 629,569 42,42' \
  "$TMP_DIR/icon.png" -geometry +249+80 -composite \
  -font "$BOLD_FONT" -fill "$INK" -pointsize 88 -gravity north -annotate +0+265 'Daisy' \
  -font "$LIGHT_FONT" -fill '#344054' -stroke none -pointsize 34 -annotate +0+380 '翻译随处到，原文不动。' \
  -gravity northwest "$ASSET_DIR/outro-center.png"
magick "$ASSET_DIR/minimal-pinned-shadow.png" -resize 430x -alpha set -background none -rotate -5 "$TMP_DIR/outro-pin.png"
magick "$ASSET_DIR/quick-popup-shadow.png" -resize 460x -alpha set -background none -rotate 4 "$TMP_DIR/outro-popup.png"
magick "$ASSET_DIR/settings-openai-shadow.png" -resize 500x -alpha set -background none -rotate 3 "$TMP_DIR/outro-settings.png"
magick "$TMP_DIR/canvas.png" \
  "$TMP_DIR/outro-pin.png" -geometry +95+150 -composite \
  "$TMP_DIR/outro-popup.png" -geometry +1330+165 -composite \
  "$TMP_DIR/outro-settings.png" -geometry +1260+650 -composite \
  "$ASSET_DIR/minimal-auto-shadow.png" -geometry +130+710 -composite \
  -fill 'rgba(255,255,255,0.96)' -stroke '#E8ECF2' -strokewidth 2 -draw 'roundrectangle 645,260 1275,830 42,42' \
  "$TMP_DIR/icon.png" -geometry +894+340 -composite \
  -font "$BOLD_FONT" -fill "$INK" -pointsize 88 -gravity north -annotate +0+525 'Daisy' \
  -font "$LIGHT_FONT" -fill '#344054' -stroke none -pointsize 34 -annotate +0+640 '翻译随处到，原文不动。' \
  -gravity northwest "$FRAME_DIR/outro.png"

brand_card outro-pinned '钉在这里' '工作继续，翻译一直在。' 'DAISY · PINNED'
brand_card outro-auto '自动翻译' '输入停下，译文就到。' 'DAISY · AUTO'
brand_card outro-ai 'Daisy + AI' '本地、系统、自定义服务。' 'DAISY · EXTENSIBLE'

echo "Built styleframes in $FRAME_DIR"
