import type {CSSProperties} from 'react';
import {
  AbsoluteFill,
  Easing,
  Img,
  interpolate,
  spring,
  useCurrentFrame,
  useVideoConfig,
} from 'remotion';
import {COLORS, clamp, easeHero, easeOut, fade} from './theme';
import {
  AppIcon,
  asset,
  BrandLockup,
  Caption,
  Capture,
  Kicker,
  SceneMarker,
  SoftCanvas,
} from './ui';

export const BrandScene: React.FC<{
  duration: number;
  title?: string;
  detail?: string;
  kicker?: string;
}> = ({duration, title = 'Daisy', detail = '翻译随处到', kicker = '轻快 · 原生 · 随处可用'}) => {
  const frame = useCurrentFrame();
  const opacity = fade(frame, duration, 16, 14);

  return (
    <SoftCanvas>
      <AbsoluteFill
        style={{
          opacity,
          alignItems: 'center',
          justifyContent: 'center',
        }}
      >
        <div style={{transform: 'translateY(-22px)'}}>
          <BrandLockup title={title} detail={detail} />
          <Kicker style={{marginLeft: 188, marginTop: 34}}>{kicker}</Kicker>
        </div>
      </AbsoluteFill>
    </SoftCanvas>
  );
};

export const HeroPinScene: React.FC<{
  duration: number;
  compactCopy?: boolean;
  showPassingText?: boolean;
}> = ({duration, compactCopy = false, showPassingText = false}) => {
  const frame = useCurrentFrame();
  const opacity = fade(frame, duration, 12, 16);
  const enter = interpolate(frame, [0, 30], [0, 1], {
    ...clamp,
    easing: easeHero,
  });
  const settleStart = Math.max(50, duration - 44);
  const reseat = interpolate(frame, [settleStart, settleStart + 20], [0, 1], {
    ...clamp,
    easing: easeOut,
  });
  const hover = frame > 30 && frame < settleStart ? Math.sin((frame - 30) / 13) * 5 : 0;
  const tilt = (1 - enter) * -19 * (1 - reseat);
  const y = (1 - enter) * 120 + hover + reseat * -hover;
  const scale = 0.82 + enter * 0.24 - reseat * 0.02;
  const pinPulse = interpolate(frame, [36, 45, 56], [0, 1, 0], clamp);
  const textTravel = interpolate(frame, [0, duration], [240, -540], {
    ...clamp,
    easing: Easing.linear,
  });

  return (
    <SoftCanvas>
      <AbsoluteFill style={{opacity}}>
        <SceneMarker label="ALWAYS NEAR" />
        {showPassingText ? (
          <div
            style={{
              position: 'absolute',
              left: 120,
              right: 80,
              top: 220,
              transform: `translateX(${textTravel}px)`,
              color: '#D7DEE8',
              fontSize: 82,
              fontWeight: 720,
              letterSpacing: '-0.045em',
              lineHeight: 1.34,
              whiteSpace: 'nowrap',
            }}
          >
            Write. Read. Design. Build. The work keeps moving.
          </div>
        ) : null}
        <div
          style={{
            position: 'absolute',
            left: compactCopy ? 132 : 154,
            top: compactCopy ? 298 : 318,
            width: 640,
            zIndex: 2,
          }}
        >
          <Kicker>PINNED AIR</Kicker>
          <Caption
            title="钉在屏幕上"
            detail={compactCopy ? '工作继续，翻译一直在。' : '轻轻放在需要的位置，不挡住正在做的事。'}
            style={{marginTop: 28}}
          />
        </div>
        <div
          style={{
            position: 'absolute',
            left: 1140,
            top: 214,
            perspective: 1400,
            transformStyle: 'preserve-3d',
          }}
        >
          <div
            style={{
              position: 'absolute',
              width: 720,
              height: 720,
              left: -100,
              top: -42,
              borderRadius: '50%',
              background:
                'radial-gradient(circle, rgba(47,125,246,.18), rgba(50,201,163,.07) 42%, transparent 70%)',
              opacity: 0.9,
              filter: 'blur(18px)',
            }}
          />
          <div
            style={{
              position: 'relative',
              transformOrigin: '50% 55%',
              transform: `translate3d(-50%, ${y}px, 0) rotateX(${(1 - enter) * 4}deg) rotateY(${tilt}deg) scale(${scale})`,
              transformStyle: 'preserve-3d',
            }}
          >
            <Capture name="minimal-pinned" width={620} />
            <div
              style={{
                position: 'absolute',
                right: 22,
                top: 10,
                width: 54,
                height: 54,
                borderRadius: '50%',
                border: `3px solid rgba(47,125,246,${0.72 * pinPulse})`,
                boxShadow: `0 0 0 ${12 * pinPulse}px rgba(47,125,246,${0.11 * pinPulse})`,
              }}
            />
          </div>
        </div>
      </AbsoluteFill>
    </SoftCanvas>
  );
};

export const PopupScene: React.FC<{duration: number}> = ({duration}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const opacity = fade(frame, duration, 12, 15);
  const appear = spring({
    frame: frame - 20,
    fps,
    config: {damping: 13, mass: 0.65, stiffness: 190},
    durationInFrames: 28,
  });
  const pageShift = interpolate(frame, [0, 30], [28, 0], {
    ...clamp,
    easing: easeOut,
  });

  return (
    <SoftCanvas accent="mint">
      <AbsoluteFill style={{opacity}}>
        <SceneMarker label="KEEP THE ORIGINAL" />
        <div
          style={{
            position: 'absolute',
            left: 150,
            top: 180 + pageShift,
            width: 1020,
            height: 700,
            padding: '72px 0',
          }}
        >
          <Kicker>NOTES · RESEARCH</Kicker>
          <div
            style={{
              marginTop: 38,
              fontSize: 54,
              lineHeight: 1.34,
              fontWeight: 720,
              letterSpacing: '-0.035em',
              color: COLORS.ink,
            }}
          >
            Keep reading in place.
            <br />
            <span
              style={{
                display: 'inline-block',
                marginTop: 26,
                padding: '5px 12px 9px',
                borderRadius: 10,
                background: 'rgba(47,125,246,.12)',
                boxShadow: 'inset 0 -3px 0 rgba(47,125,246,.22)',
              }}
            >
              Meaning can appear beside the original.
            </span>
          </div>
          <div
            style={{
              marginTop: 38,
              width: 720,
              fontSize: 28,
              lineHeight: 1.7,
              color: '#8A94A6',
            }}
          >
            The page stays exactly where it is. Daisy adds a lightweight translation surface nearby,
            then gets out of the way.
          </div>
        </div>
        <div
          style={{
            position: 'absolute',
            right: 130,
            top: 466,
            transformOrigin: '18% 0%',
            transform: `translateY(${(1 - appear) * 50}px) scale(${0.88 + appear * 0.12})`,
            opacity: appear,
          }}
        >
          <Capture name="quick-popup" width={660} />
        </div>
        <Caption
          title="原文不动，译文就到"
          detail="选中文字，真实 Daisy 浮层就出现在旁边。"
          style={{position: 'absolute', right: 150, top: 720, width: 630}}
        />
      </AbsoluteFill>
    </SoftCanvas>
  );
};

export const AutoScene: React.FC<{duration: number; close?: boolean}> = ({
  duration,
  close = false,
}) => {
  const frame = useCurrentFrame();
  const opacity = fade(frame, duration, 12, 15);
  const enter = interpolate(frame, [0, 24], [0, 1], {
    ...clamp,
    easing: easeOut,
  });
  const workflowHold = close ? 72 : 32;
  const windowIn = interpolate(frame, [workflowHold - 12, workflowHold + 12], [0, 1], {
    ...clamp,
    easing: easeOut,
  });
  const revealStart = workflowHold + (close ? 48 : 28);
  const reveal = interpolate(frame, [revealStart, revealStart + 24], [0, 1], {
    ...clamp,
    easing: easeOut,
  });
  const carry = interpolate(frame, [revealStart - 8, revealStart + 22], [0, 1], {
    ...clamp,
    easing: Easing.bezier(0.65, 0, 0.35, 1),
  });
  const windowWidth = close ? 730 : 640;
  const windowLeft = close ? 840 : 1080;

  return (
    <SoftCanvas>
      <AbsoluteFill style={{opacity}}>
        <SceneMarker label="AUTO TRANSLATE" />
        <div style={{position: 'absolute', left: 150, top: 315, width: 670}}>
          <Kicker>NO SUBMIT BUTTON</Kicker>
          <Caption
            title="停下输入，自动翻译"
            detail="不演示复制、切换或粘贴。结果在原位自然出现。"
            style={{marginTop: 28}}
          />
          <div
            style={{
              marginTop: 46,
              width: 520,
              height: 5,
              borderRadius: 5,
              background: '#E9EEF5',
              overflow: 'hidden',
            }}
          >
            <div
              style={{
                width: `${carry * 100}%`,
                height: '100%',
                borderRadius: 5,
                background: `linear-gradient(90deg, ${COLORS.blue}, ${COLORS.mint})`,
              }}
            />
          </div>
        </div>
        <div
          style={{
            position: 'absolute',
            left: 820,
            top: 190,
            width: 1040,
            height: 590,
            overflow: 'hidden',
            opacity: enter * (1 - windowIn),
            filter: 'drop-shadow(0 24px 48px rgba(17,24,39,.11))',
          }}
        >
          <Img
            src={asset('settings-workflow')}
            style={{
              position: 'absolute',
              width: 1400,
              height: 'auto',
              left: -87,
              top: -620,
            }}
          />
        </div>
        <div
          style={{
            position: 'absolute',
            left: windowLeft,
            top: 210,
            transform: `translateX(${(1 - enter) * 70}px) scale(${0.94 + enter * 0.06})`,
            opacity: enter * windowIn,
          }}
        >
          <div style={{position: 'relative', width: windowWidth}}>
            <Capture name="minimal-auto" width={windowWidth} />
            <Img
              src={asset('minimal-empty')}
              style={{
                position: 'absolute',
                inset: 0,
                width: windowWidth,
                height: 'auto',
                clipPath: 'inset(54.7% 0 0 0)',
                opacity: 1 - reveal,
                filter: 'drop-shadow(0 22px 32px rgba(17,24,39,.11))',
              }}
            />
            <div
              style={{
                position: 'absolute',
                left: windowWidth * 0.5 - 2,
                top: windowWidth * 0.34,
                width: 4,
                height: windowWidth * 0.21 * carry,
                borderRadius: 4,
                background: `linear-gradient(${COLORS.blue}, ${COLORS.mint})`,
                opacity: carry * (1 - reveal * 0.65),
                boxShadow: '0 0 20px rgba(47,125,246,.32)',
              }}
            />
          </div>
        </div>
      </AbsoluteFill>
    </SoftCanvas>
  );
};

const providerStates = [
  {assetName: 'settings-apple', label: 'Apple System Translation', color: '#2F7DF6'},
  {assetName: 'settings-ollama', label: 'Ollama · Local', color: '#32C9A3'},
  {assetName: 'settings-openai', label: 'OpenAI-compatible', color: '#7C6CF2'},
  {assetName: 'settings-deepseek', label: 'DeepSeek', color: '#2F7DF6'},
];

const ProviderRow: React.FC<{
  assetName: string;
  label: string;
  color: string;
  index: number;
  frame: number;
}> = ({assetName, color, index, frame}) => {
  const start = 18 + index * 13;
  const p = interpolate(frame, [start, start + 20], [0, 1], {
    ...clamp,
    easing: easeOut,
  });
  return (
    <div
      style={{
        position: 'absolute',
        left: 700,
        top: 175 + index * 190,
        width: 1160,
        height: 128,
        borderRadius: 18,
        overflow: 'hidden',
        background: COLORS.white,
        border: '1px solid rgba(17,24,39,.08)',
        boxShadow: '0 16px 38px rgba(17,24,39,.09)',
        opacity: p,
        transform: `translateX(${(1 - p) * 100}px) scale(${0.97 + p * 0.03})`,
      }}
    >
      <Img
        src={asset(assetName)}
        style={{
          position: 'absolute',
          width: 1400,
          height: 'auto',
          left: -120,
          top: -474,
        }}
      />
      <div
        style={{
          position: 'absolute',
          left: 0,
          top: 0,
          bottom: 0,
          width: 7,
          background: color,
        }}
      />
    </div>
  );
};

export const AIScene: React.FC<{duration: number; close?: boolean}> = ({
  duration,
  close = false,
}) => {
  const frame = useCurrentFrame();
  const opacity = fade(frame, duration, 12, 15);
  const panelEnter = interpolate(frame, [0, 28], [0, 1], {
    ...clamp,
    easing: easeOut,
  });
  const rowsOpacity = interpolate(frame, [16, 32, duration - 48, duration - 26], [0, 1, 1, 0], clamp);
  const panelScale = close ? 0.82 : 0.67;

  return (
    <SoftCanvas accent="blue">
      <AbsoluteFill style={{opacity}}>
        <SceneMarker label="YOUR MODEL, YOUR CHOICE" />
        <div style={{position: 'absolute', left: 140, top: 278, width: 600}}>
          <Kicker>APPLE + AI SERVICES</Kicker>
          <Caption
            title="Apple 起步，也能接入 AI"
            detail="真实设置界面，凭据留空。支持本地与自定义服务。"
            style={{marginTop: 28}}
          />
        </div>
        <div
          style={{
            position: 'absolute',
            left: close ? 805 : 1115,
            top: close ? 95 : 130,
            opacity: panelEnter * (1 - rowsOpacity * 0.82),
            transform: `translateY(${(1 - panelEnter) * 70}px) scale(${panelScale})`,
            transformOrigin: 'top left',
          }}
        >
          <Capture name="settings-openai" width={1400} />
        </div>
        <div style={{opacity: rowsOpacity}}>
          {providerStates.map((provider, index) => (
            <ProviderRow key={provider.assetName} {...provider} index={index} frame={frame} />
          ))}
        </div>
      </AbsoluteFill>
    </SoftCanvas>
  );
};

const waterfallAssets = [
  'minimal-empty',
  'quick-popup',
  'settings-apple',
  'minimal-pinned',
  'settings-ollama',
  'minimal-auto',
  'settings-openai',
  'standard-auto',
  'settings-deepseek',
];

export const WaterfallScene: React.FC<{duration: number}> = ({duration}) => {
  const frame = useCurrentFrame();
  const opacity = fade(frame, duration, 12, 15);
  const enter = interpolate(frame, [0, 24], [0, 1], {
    ...clamp,
    easing: easeOut,
  });

  return (
    <SoftCanvas>
      <AbsoluteFill style={{opacity, perspective: 1700}}>
        <SceneMarker label="SMALL, COMPLETE" />
        <div
          style={{
            position: 'absolute',
            left: 112,
            top: 226,
            width: 420,
            zIndex: 5,
          }}
        >
          <Kicker>ONE LIGHT TOOL</Kicker>
          <Caption title="小而完整" detail="固定、浮层、自动翻译、AI 接入，都在同一个 Daisy 里。" style={{marginTop: 28}} />
        </div>
        <div
          style={{
            position: 'absolute',
            left: 620,
            top: -160,
            width: 1420,
            height: 1400,
            display: 'flex',
            gap: 34,
            transform: `rotateX(4deg) rotateY(-13deg) translateY(${(1 - enter) * 90}px)`,
            transformStyle: 'preserve-3d',
            opacity: enter,
          }}
        >
          {[0, 1, 2].map((column) => {
            const direction = column === 1 ? 1 : -1;
            const travel = ((frame * (0.72 + column * 0.12) * direction) % 520) - 260;
            return (
              <div
                key={column}
                style={{
                  width: 420,
                  display: 'flex',
                  flexDirection: 'column',
                  gap: 28,
                  transform: `translateY(${travel + column * 70}px)`,
                }}
              >
                {[...waterfallAssets, ...waterfallAssets].slice(column * 2, column * 2 + 8).map((name, index) => (
                  <div
                    key={`${column}-${index}-${name}`}
                    style={{
                      padding: 12,
                      borderRadius: 24,
                      background: 'rgba(255,255,255,.94)',
                      boxShadow: '0 18px 48px rgba(17,24,39,.10)',
                      border: '1px solid rgba(17,24,39,.055)',
                    }}
                  >
                    <Capture name={name} width={396} shadow={false} style={{borderRadius: 14}} />
                  </div>
                ))}
              </div>
            );
          })}
        </div>
      </AbsoluteFill>
    </SoftCanvas>
  );
};

export const OutroScene: React.FC<{
  duration: number;
  title?: string;
  detail?: string;
  focusedAsset?: 'pin' | 'auto' | 'ai';
}> = ({duration, title = 'Daisy', detail = '翻译随处到，原文不动。', focusedAsset}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const opacity = fade(frame, duration, 12, 8);
  const assemble = spring({
    frame: frame - 8,
    fps,
    config: {damping: 14, stiffness: 120, mass: 0.85},
    durationInFrames: 46,
  });
  const wordmark = interpolate(frame, [24, 52], [0, 1], {
    ...clamp,
    easing: easeOut,
  });
  const choices = {
    pin: 'minimal-pinned',
    auto: 'minimal-auto',
    ai: 'settings-openai',
  } as const;
  const mainAsset = focusedAsset ? choices[focusedAsset] : 'minimal-pinned';

  const cardStyle = (x: number, y: number, rotation: number, delay: number): CSSProperties => {
    const p = interpolate(assemble, [delay, 1], [0, 1], clamp);
    return {
      position: 'absolute',
      left: x,
      top: y,
      opacity: p,
      transform: `translateY(${(1 - p) * 130}px) rotate(${rotation * p}deg) scale(${0.82 + p * 0.18})`,
    };
  };

  return (
    <SoftCanvas>
      <AbsoluteFill style={{opacity}}>
        <div style={cardStyle(170, 214, -5, 0.03)}>
          <Capture name="quick-popup" width={500} />
        </div>
        <div style={cardStyle(1225, 166, 4, 0.12)}>
          <Capture name="settings-apple" width={560} />
        </div>
        <div style={cardStyle(130, 685, 5, 0.2)}>
          <Capture name="minimal-auto" width={430} />
        </div>
        <div style={cardStyle(1340, 710, -4, 0.26)}>
          <Capture name={mainAsset} width={focusedAsset === 'ai' ? 520 : 430} />
        </div>
        <div
          style={{
            position: 'absolute',
            left: '50%',
            top: '50%',
            transform: `translate(-50%, -50%) scale(${0.88 + wordmark * 0.12})`,
            opacity: wordmark,
            padding: '52px 68px 48px',
            borderRadius: 42,
            background: 'rgba(255,255,255,.92)',
            boxShadow: '0 34px 110px rgba(47,125,246,.14)',
            border: '1px solid rgba(17,24,39,.055)',
          }}
        >
          <div style={{display: 'flex', flexDirection: 'column', alignItems: 'center'}}>
            <AppIcon size={126} />
            <div
              style={{
                marginTop: 18,
                fontSize: 92,
                lineHeight: 0.95,
                fontWeight: 790,
                letterSpacing: '-0.065em',
              }}
            >
              {title}
            </div>
            <div
              style={{
                marginTop: 17,
                color: COLORS.secondary,
                fontSize: 30,
                fontWeight: 520,
                whiteSpace: 'nowrap',
              }}
            >
              {detail}
            </div>
          </div>
        </div>
      </AbsoluteFill>
    </SoftCanvas>
  );
};
