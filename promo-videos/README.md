# Daisy promotional video suite

Deliverables are in `out/final/`:

- `DaisyOverview.mp4` — 30 seconds
- `DaisyPinned.mp4` — 15 seconds
- `DaisyAuto.mp4` — 15 seconds
- `DaisyAI.mp4` — 15 seconds
- matching `-no-bgm.mp4` versions that retain SFX

All product surfaces come from eleven Daisy production SwiftUI captures at 2×
with fictional in-memory state. The renderer animates those real textures for
the pin change, popup summon, automatic-result reveal, provider-row embedding,
waterfall, and final group-photo assembly. See `public/ui/layout.json` and
`Tests/DaisyTranslatorTests/PromoCaptureTests.swift`.

## Rebuild final MP4 files offline

Requires ImageMagick and FFmpeg:

```sh
scripts/build-styleframes.sh
scripts/render-offline.sh
```

## Render with Remotion

When npm registry access is available:

```sh
npm ci
npx remotion compositions src/index.ts
npx remotion render src/index.ts DaisyOverview out/final/DaisyOverview-remotion.mp4
```

The eight Remotion compositions share four visual timelines. `NoBgm`
compositions pass `withBgm: false`, so SFX remain mounted while the BGM bed is
omitted.

Creative decisions, storyboards, SFX timing, QA, and output hashes are in
`creative-spec.md`, `sfx-plan.md`, `qa-report.md`, and `render-manifest.json`.
