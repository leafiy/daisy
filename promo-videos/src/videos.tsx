import {AbsoluteFill, Sequence} from 'remotion';
import {
  AIScene,
  AutoScene,
  BrandScene,
  HeroPinScene,
  OutroScene,
  PopupScene,
  WaterfallScene,
} from './scenes';
import {AUDIO_CUES, PromoAudio} from './audio';

export type VideoProps = {withBgm: boolean};

export const DaisyOverview: React.FC<VideoProps> = ({withBgm}) => (
  <AbsoluteFill>
    <Sequence from={0} durationInFrames={90} premountFor={30}>
      <BrandScene duration={90} />
    </Sequence>
    <Sequence from={90} durationInFrames={150} premountFor={30}>
      <HeroPinScene duration={150} />
    </Sequence>
    <Sequence from={240} durationInFrames={135} premountFor={30}>
      <PopupScene duration={135} />
    </Sequence>
    <Sequence from={375} durationInFrames={120} premountFor={30}>
      <AutoScene duration={120} />
    </Sequence>
    <Sequence from={495} durationInFrames={135} premountFor={30}>
      <AIScene duration={135} />
    </Sequence>
    <Sequence from={630} durationInFrames={120} premountFor={30}>
      <WaterfallScene duration={120} />
    </Sequence>
    <Sequence from={750} durationInFrames={150} premountFor={30}>
      <OutroScene duration={150} />
    </Sequence>
    <PromoAudio withBgm={withBgm} totalFrames={900} cues={AUDIO_CUES.overview} />
  </AbsoluteFill>
);

export const DaisyPinned: React.FC<VideoProps> = ({withBgm}) => (
  <AbsoluteFill>
    <Sequence from={0} durationInFrames={60} premountFor={20}>
      <BrandScene duration={60} title="钉住，不打断" detail="Daisy stays nearby" kicker="轻轻固定在需要的位置" />
    </Sequence>
    <Sequence from={60} durationInFrames={150} premountFor={30}>
      <HeroPinScene duration={150} compactCopy />
    </Sequence>
    <Sequence from={210} durationInFrames={120} premountFor={30}>
      <HeroPinScene duration={120} compactCopy showPassingText />
    </Sequence>
    <Sequence from={330} durationInFrames={120} premountFor={30}>
      <OutroScene duration={120} title="钉在这里" detail="工作继续，翻译一直在。" focusedAsset="pin" />
    </Sequence>
    <PromoAudio withBgm={withBgm} totalFrames={450} cues={AUDIO_CUES.pinned} />
  </AbsoluteFill>
);

export const DaisyAuto: React.FC<VideoProps> = ({withBgm}) => (
  <AbsoluteFill>
    <Sequence from={0} durationInFrames={60} premountFor={20}>
      <BrandScene duration={60} title="不用催" detail="它会自己开始" kicker="AUTO TRANSLATE" />
    </Sequence>
    <Sequence from={60} durationInFrames={270} premountFor={30}>
      <AutoScene duration={270} close />
    </Sequence>
    <Sequence from={330} durationInFrames={120} premountFor={30}>
      <OutroScene duration={120} title="自动翻译" detail="输入停下，译文就到。" focusedAsset="auto" />
    </Sequence>
    <PromoAudio withBgm={withBgm} totalFrames={450} cues={AUDIO_CUES.auto} />
  </AbsoluteFill>
);

export const DaisyAI: React.FC<VideoProps> = ({withBgm}) => (
  <AbsoluteFill>
    <Sequence from={0} durationInFrames={60} premountFor={20}>
      <BrandScene duration={60} title="从 Apple 开始" detail="也能接入你的 AI" kicker="YOUR MODEL, YOUR CHOICE" />
    </Sequence>
    <Sequence from={60} durationInFrames={300} premountFor={30}>
      <AIScene duration={300} close />
    </Sequence>
    <Sequence from={360} durationInFrames={90} premountFor={30}>
      <OutroScene duration={90} title="Daisy + AI" detail="本地、系统、自定义服务。" focusedAsset="ai" />
    </Sequence>
    <PromoAudio withBgm={withBgm} totalFrames={450} cues={AUDIO_CUES.ai} />
  </AbsoluteFill>
);
