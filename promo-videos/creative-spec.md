# Daisy Promo Video Creative Spec

Mode: autonomous free creation  
Status: final renders and QA complete  
Format: 1920×1080, 30fps, Simplified Chinese

## Stage 0 — Product brief

Daisy is a lightweight native macOS translator that stays available without
interrupting the current task. Its distinctive experience is not a conventional
copy → switch → paste translation workflow. It is a compact window that can be
pinned anywhere, can translate automatically after input settles, can show a
translation next to selected text, and can use Apple System Translation or the
user's own AI/translation service.

Primary audience: bilingual macOS users, readers, writers, developers, and
knowledge workers who translate small amounts of text throughout the day.

Core promise: **翻译随处到，原文不动。**

Must show:

- the real minimal Daisy window and its real pin control;
- a real quick-translate popup that appears near selected text;
- automatic translation and workflow controls without demonstrating the old
  copy/switch/paste loop;
- the real provider controls for Apple System Translation and configurable AI
  services;
- a coherent family of four videos: one overview around 30 seconds and three
  feature videos under 20 seconds.

Must avoid:

- using the repository's existing promo PNGs as video assets;
- rebuilding or imitating Daisy UI in HTML/React;
- API keys, personal clipboard contents, existing translation history, or
  private text;
- dark backgrounds, cyber-neon styling, handheld shake, or a dense tutorial
  pace;
- showing typing/copying/pasting as the primary story.

Data policy: only fictional demo copy is allowed. Settings captures must use a
provider state that exposes no secret values. Existing promo images are visual
reference only and will never be imported by the Remotion project.

Audio policy: a restrained product-promo music bed plus cinematic SFX. Every
composition is rendered twice from the same timeline: BGM on and BGM off (SFX
retained).

## Requirement-to-execution decisions

| Requirement | Execution decision |
|---|---|
| White, clean feeling | Pure white field, pale blue/mint atmospheric halos, high-key soft shadows, no dark interstitials |
| Only real Daisy UI | All product surfaces are PNG captures of Daisy's production SwiftUI views; motion may crop, mask, move, or relight those captures but never redraw their content |
| Do not use existing promo images | `assets/promo/*` is excluded from the video project and capture manifest |
| Pin anywhere | Treat the 340×308 minimal window as the hero object; show real unpinned and pinned states |
| Do not break original text | Quick popup is shown as an independent Daisy surface above simple editorial copy; the source copy remains fixed |
| Automatic translation | Reveal a settled real translated state and the real automation controls; do not show manual submission |
| AI connectivity | Use the real provider picker/settings UI, with Apple and service names visible but all credential values absent |
| At least four videos | `DaisyOverview` 900f; `DaisyPinned` 450f; `DaisyAuto` 450f; `DaisyAI` 450f |

## Stage 1 — Visual direction

Three directions were considered:

1. **Pinned Air** — white editorial space, one floating native window, quiet
   blue/mint light, generous holds. Best expression of “lightweight and always
   nearby.”
2. **macOS Utility Stage** — more full-window chrome and settings panels. It is
   accurate but reads like a product tutorial and underplays the floating habit.
3. **Translation Grid** — many snippets and windows moving in parallel. It adds
   energy but risks visual noise and resembles a batch translation workflow.

Selected direction: **Pinned Air**. It preserves Daisy's native semantic colors,
small rounded geometry, system typography, pin icon, and glass-like minimal
surface while giving the product enough white space to feel fast rather than
technical.

### Visual tokens

| Token | Value |
|---|---|
| Canvas | `#FFFFFF` |
| Near-white surface | `#F7F9FC` |
| Primary ink | `#111827` |
| Secondary ink | `#667085` |
| macOS accent blue | `#2F7DF6` |
| Daisy mint accent | `#32C9A3` |
| Blue halo | `rgba(47,125,246,.14)` |
| Mint halo | `rgba(50,201,163,.12)` |
| Product font | `-apple-system, BlinkMacSystemFont, "SF Pro Display", sans-serif` |
| Radius vocabulary | 6 / 10 / 12px from LeafiyDesign; captured windows retain their native radius |
| Shadow | two layers, `0 10px 24px rgba(17,24,39,.10)` + `0 38px 90px rgba(47,125,246,.12)` |

Typography scale: 104px hero, 62px section title, 32px explanatory line,
22px small label. Captions stay outside captured UI and never mimic macOS
controls.

### Motion personality tokens

Brand axes: medium energy (0.58), friendly/precise tone (0.42). Starting preset:
friendly small utility, adjusted to be slightly faster and less bouncy.

| Token | Value |
|---|---|
| Standard entrance | 24–27f, `cubic-bezier(.25,.46,.45,.94)` |
| Hero lift | 10f, `cubic-bezier(.2,1.25,.3,1)` |
| Hero hover | 44–54f, 3–4px amplitude |
| Reseat | 18f, then ≥15f true stillness |
| Batch landing | 12f + 4f press recovery; max overshoot 1.04 |
| Camera | mostly front-facing; oblique hero max 22° Y / 5° X for UI readability |
| Hold | brand ≥30f; settled feature ≥18f; batch completion ≥15f |
| Shake | forbidden |

Styleframe files live in `styleframes/`. They intentionally use only a safe
preflight capture of the running Daisy window and the real app icon.

Environment note: the managed workspace blocked both localhost binding and
browser access to `file://` URLs, so the early HTML styleframe could not be
exported without bypassing browser security policy. Production UI was instead
captured at 2× directly from Daisy's existing `TranslatorView`,
`DaisySettingsView`, and `QuickTranslatePopupContent`, using fictional in-memory
state. The capture harness reads no user clipboard, history, settings, or keys.
Every offline 1920×1080 mirror and every shot acceptance frame was reviewed
before final encoding.

## Stage 2 — Function-to-shot mapping

Each selected card and style key was validated against
`gallery/api/library.json`; its full recipe and exact demo source were read.

| Function | Primary shot card / style | Accurate implementation source | Adaptation |
|---|---|---|---|
| Minimal window + pin | `spotlight-hero-card` / `spotlight-hero-card` | `template/src/aifl/live/SceneOpen.tsx` | White high-key spotlight; real Daisy window replaces page card; full lift→hover→reseat arc retained |
| Selection popup | `command-palette-summon` / `command-palette-summon` | `demos/interaction/command-palette-summon/CommandPaletteSummon.tsx` | Real Daisy popup replaces the fake palette; 15f overshoot landing and ≥40f selected hold retained; no fabricated candidates or keycap UI |
| Automatic translation | `line-carry-transition` / `line-carry-transition` | `demos/transition/line-carry-transition/LineCarryTransition.tsx` | A native blue rule connects real source and result crops; 60f camera carry and 36f still ending retained |
| AI/provider choice | `row-embed` / `row-embed` | `template/src/aifl/live/SceneDetail.tsx` | Real picker/menu rows are texture crops and land back into their true slots; one bottom seam per row |
| Product breadth | `page-waterfall-wall` / `page-waterfall-wall` | `demos/ui-entrance/page-waterfall-wall/PageWaterfallWall.tsx` + `assets/lib/VerticalTicker.tsx` | Three columns contain only real Daisy captures; white background, 12/9/14s loops, center column reversed |
| Suite finale | `outro-group-photo-launch` / `outro-group-photo-launch` | `template/src/aifl/live/SceneOutroLive.tsx` | Real Daisy window, popup, settings and icon form the group photo; no gold dust, dark stage, or fake UI; overshoot and 30f wordmark hold retained |

## Stage 3 — Storyboards

### Video 1 — `DaisyOverview` (900f / 30s)

| # | Time | Shot | Key motion |
|---|---|---|---|
| 1 | 0–3s | Real icon + “Daisy / 翻译随处到” | icon settles, wordmark holds 1s |
| 2 | 3–8s | Real minimal window becomes the single hero | spotlight locks, 3D push, lift→hover→reseat; caption “钉在屏幕上” |
| 3 | 8–12.5s | Real quick popup above unchanged editorial copy | background breathes back, popup overshoot lands; caption “原文不动，译文就到” |
| 4 | 12.5–16.5s | Real workflow settings hands off to a settled translated window | blue rule grows and carries the camera; caption “停下输入，自动翻译” |
| 5 | 16.5–21s | Real provider picker/settings | provider rows embed into true slots; caption “Apple 起步，也能接入 AI” |
| 6 | 21–25s | Real Daisy surfaces in a three-column waterfall | gentle 3D wall, no readable claim beyond “小而完整” |
| 7 | 25–30s | Real UI cutouts return around icon and Daisy wordmark | group-photo assembly, app icon/wordmark peak, 1s still sign-off |

Frame plan:

| shot | from | duration | Content | Acceptance frames |
|---|---:|---:|---|---|
| brand | 0 | 90 | icon + wordmark | 36, 74 |
| hero | 90 | 150 | pinned minimal window | 136, 220 |
| popup | 240 | 135 | quick translate popup | 275, 350 |
| auto | 375 | 120 | automation → translated state | 415, 485 |
| ai | 495 | 135 | real provider UI | 535, 610 |
| breadth | 630 | 120 | waterfall wall | 660, 730 |
| outro | 750 | 150 | group photo + sign-off | 790, 875 |

### Video 2 — `DaisyPinned` (450f / 15s)

| # | Time | Shot | Key motion |
|---|---|---|---|
| 1 | 0–2s | Icon + “钉住，不打断” | light brand settle |
| 2 | 2–7s | Real minimal window as hero | spotlight lift arc, pin state changes only via real captured UI |
| 3 | 7–11s | Window stays fixed while editorial copy passes behind | product remains motionless after landing; caption “工作继续，翻译一直在” |
| 4 | 11–15s | Close on real pin + wordmark | one soft outline pulse, 1s sign-off hold |

### Video 3 — `DaisyAuto` (450f / 15s)

| # | Time | Shot | Key motion |
|---|---|---|---|
| 1 | 0–2s | Icon + “不用催，它会自己开始” | light brand settle |
| 2 | 2–6s | Real Workflow pane | restrained pan across Auto Translate / Watch Clipboard / Auto Copy controls |
| 3 | 6–11s | Real source/result crops | line-carry connects panels; result arrives already settled, no typing or submit action |
| 4 | 11–15s | Real filled minimal window + wordmark | caption “输入停下，译文就到”; 1s hold |

### Video 4 — `DaisyAI` (450f / 15s)

| # | Time | Shot | Key motion |
|---|---|---|---|
| 1 | 0–2s | Icon + “从 Apple 开始” | light brand settle |
| 2 | 2–5s | Real General/provider pane | straight-on readable establishment |
| 3 | 5–9s | Real provider rows | row-embed with true texture crops, no credential fields |
| 4 | 9–12s | Safe real provider states | Apple / Ollama / OpenAI-compatible labels; slow crop travel |
| 5 | 12–15s | Icon + “也能接入你的 AI” | soft blue/mint halo, 1s hold |

## Production approval

The four storyboards cover every required feature, use one primary movement
idea per shot, preserve reading holds, and keep every product surface sourced
from Daisy's production views. Stages 0–3 are therefore approved for final UI
capture and implementation.

## Stage 4 — Production UI capture

`PromoCaptureTests` renders production Daisy views through `NSHostingView` at
2×. The resulting eleven raw captures, their white-background derivatives, exact
pixel sizes, and approved crop regions are recorded in `public/ui/layout.json`.
Two narrow source seams keep the capture path on production UI: a Debug-only
function returns the existing private quick-translate popup as `AnyView`, and
the existing Workflow pane is factored into an internal view that the settings
screen and capture test both render. Release behavior is unchanged.

## Stages 5–7 — Implementation, sound, and final renders

The Remotion implementation lives in `src/` and defines the eight requested
compositions (four BGM + four no-BGM). Package installation could not complete
inside the managed environment because npm registry DNS is unavailable. A
deterministic ImageMagick/FFmpeg renderer in `scripts/` therefore mirrors the
same storyboards using the same production UI textures, white visual tokens,
shot timings, dynamic pin/popup/row/waterfall/outro motion, and centralized
cinematic SFX plan. The delivered MP4 files are
1920×1080, 30fps; the overview is exactly 30 seconds and the three feature
videos are exactly 15 seconds. BGM and no-BGM pairs have identical encoded video
stream hashes, while no-BGM versions retain SFX.
