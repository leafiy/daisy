# Daisy promo sound plan

Audio is timeline-level, never embedded inside scene components. The BGM bed is
the installed `video-shotcraft` tech-house track at gain 0.30 with a 1-second
fade-in and 2-second fade-out. SFX use only the product-promo vocabulary:
transition, whoosh, riser, impact, and sparkle. No game-style UI tones are used.

All times below are milliseconds from each composition start. The executable
registry is `scripts/render-offline.sh`.

| Composition | Events |
|---|---|
| DaisyOverview | transition 350; whoosh 3050; transition 8000; quick swoosh 12600; transition 17000; whoosh 21100; riser 25000; impact 26200; sparkle 27000 |
| DaisyPinned | transition 300; whoosh 2050; transition 7000; riser 11000; impact 12200; sparkle 13000 |
| DaisyAuto | transition 300; whoosh 2050; quick swoosh 6000; riser 11000; impact 12100; sparkle 12800 |
| DaisyAI | transition 300; quick swooshes 2050 / 4050 / 6050 / 8050 with descending gain; whoosh 10050; riser 12000; impact 13000; sparkle 13400 |

Every BGM/no-BGM pair is mixed from one video-only timeline. `-no-bgm.mp4`
omits only the BGM input and retains all registered SFX.
