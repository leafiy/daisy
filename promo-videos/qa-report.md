# Daisy promo self-QA

Date: 2026-08-05  
Mode: autonomous free creation  
Evidence: `out/qa/*-contact-sheet.png`, `out/final/*.mp4`

## Delivery checks

- Four compositions: one 30.000s overview and three 15.000s feature videos.
- All files: H.264, 1920×1080, 30fps, AAC 48kHz stereo.
- Audio peaks: −4.6dB to −1.8dB; no clipping.
- BGM/no-BGM video-stream MD5 hashes match for all four pairs.
- Fifty-three timeline acceptance frames plus two full-resolution proof frames
  reviewed across the four final encoded videos.
- Eleven real UI captures are 2× production SwiftUI renders with fictional state.
- Repository `assets/promo/*` files are not referenced by the capture manifest,
  Remotion source, styleframe builder, or render pipeline.
- `swift test --disable-sandbox`: 73 tests executed, one capture test skipped
  without `PROMO_CAPTURE_DIR`, zero failures. The capture harness compiled as
  part of the passing suite and produced the eleven current source captures in
  its explicit capture run.

## Aesthetic rules

- R1 ✓ Brand and final wordmarks hold at least 1 second.
- R2 ✓ Motion is eased camera drift and white-field fades; no fast linear UI flights. Batch provider states settle before the next cut.
- R3 ✓ Primary feature shots run 4–5 seconds; no simulated fast typing or hurried interaction.
- Q1 ✓ All existing Daisy product surfaces are real captures of production views; demo copy is fictional and credential fields are blank.
- Q2 ✓ UI textures are captured at 2× and displayed at or below source size.
- Q3 ✓ No handheld shake; the deterministic camera drift is smooth and sub-pixel stable.
- Q4 ✓ No repeated glints or uncropped sweep effects.
- Q5 ✓ Opening and feature openings use one subject and one clear claim.
- Q6 ✓ Settings and text-heavy surfaces remain front-facing; only group-photo cards receive shallow rotation.
- Q7 N/A The dark material object-special shot is intentionally omitted because the user requires a white clean background.
- Q8 ✓ Overview outro forms a release-style group photo containing pin, popup, translation, settings, icon, and wordmark.
- Q9 ✓ Provider row crops come from their true `Type` row slots; no fabricated rows are suspended over a fake page.
- Q10 N/A No mock document/product page is presented as Daisy UI; editorial copy is explicitly background context.
- Q11 ✓ Primary Chinese captions are 60–92px; auxiliary copy is 34–36px. Small text inside screenshots is product texture unless the shot is the readable provider close-up.
- S1 ✓ Tech-house bed plus cinematic whoosh/impact/riser/sparkle vocabulary; no game UI tones.
- S2 ✓ SFX timing is centralized in `sfx-plan.md` and `render-offline.sh`; AI provider swooshes use descending gain.
- S3 ✓ SFX was mixed only after shot durations were locked; final times match the encoded composition boundaries.
- S4 ✓ No fake click or typing action is shown; riser/impact/sparkle follow the actual outro assembly and settle.
- C1 ✓ Every feature sequence carries a concrete caption; only clean brand sign-offs omit explanatory copy.
- C2 ✓ Claims name the actual behavior: pinned window, automatic translation, and Apple/AI provider choice.
- C3 N/A Captions are screen-space editorial titles; no 3D page annotation is used.
- P1 ✓ Final acceptance frames were extracted from encoded MP4s, including
  mid-action pin, popup, line-carry, provider-row, waterfall, and outro states.
- P2 ✓ Gallery recipes were mapped individually in `creative-spec.md`; the white product direction was not applied as a global tilted-camera effect.
- P3 N/A No ambiguous user feedback was interpreted during production.
- P4 ✓ Each required feature maps to a distinct shot and a distinct 15-second feature video.

## Known production constraint

The Remotion project is complete but could not be executed in this managed
environment because npm registry DNS is blocked. Final MP4s use the documented
dynamic offline renderer. This affects the availability of Remotion-generated
proof, not the real-UI source policy, motion coverage, durations, video pair
identity, or encoded deliverables.

## Independent final review

The clean-context final reviewer returned **PASS** with no must-fix issues. It
confirmed product-goal coverage, white visual consistency, readable pacing,
storyboard order, genuine production UI, and safe fictional data in the latest
encoded MP4s. Gallery parameter fidelity was not independently measured against
reference samples, while BGM/no-BGM video identity was verified separately by
the stream-MD5 checks above.
