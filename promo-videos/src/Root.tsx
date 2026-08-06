import {Composition} from 'remotion';
import {DaisyAI, DaisyAuto, DaisyOverview, DaisyPinned} from './videos';

const VIDEO = {
  fps: 30,
  width: 1920,
  height: 1080,
};

export const Root: React.FC = () => (
  <>
    <Composition
      id="DaisyOverview"
      component={DaisyOverview}
      durationInFrames={900}
      {...VIDEO}
      defaultProps={{withBgm: true}}
    />
    <Composition
      id="DaisyOverviewNoBgm"
      component={DaisyOverview}
      durationInFrames={900}
      {...VIDEO}
      defaultProps={{withBgm: false}}
    />
    <Composition
      id="DaisyPinned"
      component={DaisyPinned}
      durationInFrames={450}
      {...VIDEO}
      defaultProps={{withBgm: true}}
    />
    <Composition
      id="DaisyPinnedNoBgm"
      component={DaisyPinned}
      durationInFrames={450}
      {...VIDEO}
      defaultProps={{withBgm: false}}
    />
    <Composition
      id="DaisyAuto"
      component={DaisyAuto}
      durationInFrames={450}
      {...VIDEO}
      defaultProps={{withBgm: true}}
    />
    <Composition
      id="DaisyAutoNoBgm"
      component={DaisyAuto}
      durationInFrames={450}
      {...VIDEO}
      defaultProps={{withBgm: false}}
    />
    <Composition
      id="DaisyAI"
      component={DaisyAI}
      durationInFrames={450}
      {...VIDEO}
      defaultProps={{withBgm: true}}
    />
    <Composition
      id="DaisyAINoBgm"
      component={DaisyAI}
      durationInFrames={450}
      {...VIDEO}
      defaultProps={{withBgm: false}}
    />
  </>
);
