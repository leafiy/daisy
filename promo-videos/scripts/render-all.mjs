import {mkdirSync} from 'node:fs';
import {spawnSync} from 'node:child_process';

mkdirSync('out/final', {recursive: true});

const renders = [
  ['DaisyOverview', 'DaisyOverview-remotion.mp4'],
  ['DaisyOverviewNoBgm', 'DaisyOverview-remotion-no-bgm.mp4'],
  ['DaisyPinned', 'DaisyPinned-remotion.mp4'],
  ['DaisyPinnedNoBgm', 'DaisyPinned-remotion-no-bgm.mp4'],
  ['DaisyAuto', 'DaisyAuto-remotion.mp4'],
  ['DaisyAutoNoBgm', 'DaisyAuto-remotion-no-bgm.mp4'],
  ['DaisyAI', 'DaisyAI-remotion.mp4'],
  ['DaisyAINoBgm', 'DaisyAI-remotion-no-bgm.mp4'],
];

for (const [composition, filename] of renders) {
  const result = spawnSync(
    'npx',
    [
      'remotion',
      'render',
      'src/index.ts',
      composition,
      `out/final/${filename}`,
      '--codec=h264',
      '--crf=17',
    ],
    {stdio: 'inherit'},
  );
  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }
}
