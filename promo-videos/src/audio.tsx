import {Audio, interpolate, Sequence, staticFile} from 'remotion';
import {clamp} from './theme';

export type AudioCue = {
  from: number;
  src: string;
  volume: number;
};

export const AUDIO_CUES = {
  overview: [
    {from: 11, src: 'transition-soft.mp3', volume: 0.28},
    {from: 92, src: 'whoosh-big.mp3', volume: 0.38},
    {from: 240, src: 'transition-soft.mp3', volume: 0.28},
    {from: 378, src: 'swoosh-quick.mp3', volume: 0.32},
    {from: 510, src: 'transition-soft.mp3', volume: 0.28},
    {from: 633, src: 'whoosh-big.mp3', volume: 0.34},
    {from: 750, src: 'riser-cine.mp3', volume: 0.34},
    {from: 786, src: 'impact-deep-whoosh.mp3', volume: 0.48},
    {from: 810, src: 'sparkle.mp3', volume: 0.3},
  ],
  pinned: [
    {from: 9, src: 'transition-soft.mp3', volume: 0.28},
    {from: 62, src: 'whoosh-big.mp3', volume: 0.4},
    {from: 210, src: 'transition-soft.mp3', volume: 0.26},
    {from: 330, src: 'riser-cine.mp3', volume: 0.34},
    {from: 366, src: 'impact-deep-whoosh.mp3', volume: 0.48},
    {from: 390, src: 'sparkle.mp3', volume: 0.3},
  ],
  auto: [
    {from: 9, src: 'transition-soft.mp3', volume: 0.28},
    {from: 62, src: 'whoosh-big.mp3', volume: 0.36},
    {from: 180, src: 'swoosh-quick.mp3', volume: 0.32},
    {from: 330, src: 'riser-cine.mp3', volume: 0.34},
    {from: 363, src: 'impact-deep-whoosh.mp3', volume: 0.46},
    {from: 384, src: 'sparkle.mp3', volume: 0.3},
  ],
  ai: [
    {from: 9, src: 'transition-soft.mp3', volume: 0.28},
    {from: 62, src: 'swoosh-quick.mp3', volume: 0.3},
    {from: 122, src: 'swoosh-quick.mp3', volume: 0.27},
    {from: 182, src: 'swoosh-quick.mp3', volume: 0.25},
    {from: 242, src: 'swoosh-quick.mp3', volume: 0.23},
    {from: 302, src: 'whoosh-big.mp3', volume: 0.34},
    {from: 360, src: 'riser-cine.mp3', volume: 0.34},
    {from: 390, src: 'impact-deep-whoosh.mp3', volume: 0.46},
    {from: 402, src: 'sparkle.mp3', volume: 0.3},
  ],
} satisfies Record<string, AudioCue[]>;

export const PromoAudio: React.FC<{
  withBgm: boolean;
  totalFrames: number;
  cues: AudioCue[];
}> = ({withBgm, totalFrames, cues}) => (
  <>
    {withBgm ? (
      <Audio
        src={staticFile('audio/bgm-tech-house.mp3')}
        loop
        volume={(frame) =>
          interpolate(frame, [0, 30, totalFrames - 60, totalFrames], [0, 0.3, 0.3, 0], clamp)
        }
      />
    ) : null}
    {cues.map((cue, index) => (
      <Sequence key={`${cue.src}-${cue.from}-${index}`} from={cue.from}>
        <Audio src={staticFile(`audio/${cue.src}`)} volume={cue.volume} />
      </Sequence>
    ))}
  </>
);
