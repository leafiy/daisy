import type {CSSProperties, ReactNode} from 'react';
import {AbsoluteFill, Img, interpolate, staticFile, useCurrentFrame} from 'remotion';
import {COLORS, FONT, clamp, easeOut} from './theme';

export const asset = (name: string) => staticFile(`ui/white/${name}.png`);

export const SoftCanvas: React.FC<{
  children: ReactNode;
  accent?: 'blue' | 'mint' | 'both';
  style?: CSSProperties;
}> = ({children, accent = 'both', style}) => {
  const frame = useCurrentFrame();
  const drift = Math.sin(frame / 55) * 16;
  const blue = accent !== 'mint';
  const mint = accent !== 'blue';

  return (
    <AbsoluteFill
      style={{
        overflow: 'hidden',
        backgroundColor: COLORS.white,
        color: COLORS.ink,
        fontFamily: FONT,
        ...style,
      }}
    >
      {blue ? (
        <div
          style={{
            position: 'absolute',
            width: 900,
            height: 620,
            left: 720 + drift,
            top: -250,
            borderRadius: '50%',
            background:
              'radial-gradient(circle, rgba(47,125,246,.15) 0%, rgba(47,125,246,.055) 42%, transparent 72%)',
            filter: 'blur(10px)',
          }}
        />
      ) : null}
      {mint ? (
        <div
          style={{
            position: 'absolute',
            width: 820,
            height: 580,
            left: -220 - drift,
            top: 590,
            borderRadius: '50%',
            background:
              'radial-gradient(circle, rgba(50,201,163,.13) 0%, rgba(50,201,163,.045) 45%, transparent 72%)',
            filter: 'blur(12px)',
          }}
        />
      ) : null}
      <div
        style={{
          position: 'absolute',
          inset: 0,
          opacity: 0.32,
          backgroundImage:
            'linear-gradient(rgba(17,24,39,.024) 1px, transparent 1px), linear-gradient(90deg, rgba(17,24,39,.024) 1px, transparent 1px)',
          backgroundSize: '96px 96px',
          maskImage: 'linear-gradient(to bottom, transparent, black 18%, black 82%, transparent)',
        }}
      />
      {children}
    </AbsoluteFill>
  );
};

export const AppIcon: React.FC<{size?: number; style?: CSSProperties}> = ({
  size = 124,
  style,
}) => (
  <Img
    src={staticFile('ui/daisy-icon.png')}
    style={{
      width: size,
      height: size,
      objectFit: 'contain',
      filter: 'drop-shadow(0 18px 34px rgba(47,125,246,.18))',
      ...style,
    }}
  />
);

export const Capture: React.FC<{
  name: string;
  width: number;
  style?: CSSProperties;
  shadow?: boolean;
}> = ({name, width, style, shadow = true}) => (
  <Img
    src={asset(name)}
    style={{
      width,
      height: 'auto',
      display: 'block',
      filter: shadow
        ? 'drop-shadow(0 22px 32px rgba(17,24,39,.11)) drop-shadow(0 46px 88px rgba(47,125,246,.10))'
        : undefined,
      ...style,
    }}
  />
);

export const Kicker: React.FC<{children: ReactNode; style?: CSSProperties}> = ({
  children,
  style,
}) => (
  <div
    style={{
      fontSize: 22,
      lineHeight: 1,
      letterSpacing: '0.14em',
      textTransform: 'uppercase',
      color: COLORS.blue,
      fontWeight: 700,
      ...style,
    }}
  >
    {children}
  </div>
);

export const Caption: React.FC<{
  title: string;
  detail?: string;
  align?: 'left' | 'center';
  style?: CSSProperties;
}> = ({title, detail, align = 'left', style}) => (
  <div style={{textAlign: align, ...style}}>
    <div
      style={{
        fontSize: 62,
        lineHeight: 1.08,
        letterSpacing: '-0.045em',
        fontWeight: 760,
        color: COLORS.ink,
      }}
    >
      {title}
    </div>
    {detail ? (
      <div
        style={{
          marginTop: 18,
          fontSize: 29,
          lineHeight: 1.4,
          letterSpacing: '-0.015em',
          color: COLORS.secondary,
          fontWeight: 480,
        }}
      >
        {detail}
      </div>
    ) : null}
  </div>
);

export const BrandLockup: React.FC<{
  title?: string;
  detail?: string;
  compact?: boolean;
}> = ({title = 'Daisy', detail = '翻译随处到', compact = false}) => {
  const frame = useCurrentFrame();
  const iconProgress = interpolate(frame, [0, 24], [0, 1], {
    ...clamp,
    easing: easeOut,
  });
  const copyProgress = interpolate(frame, [12, 38], [0, 1], {
    ...clamp,
    easing: easeOut,
  });

  return (
    <div
      style={{
        display: 'flex',
        alignItems: 'center',
        gap: compact ? 28 : 42,
      }}
    >
      <AppIcon
        size={compact ? 106 : 144}
        style={{
          opacity: iconProgress,
          transform: `translateY(${(1 - iconProgress) * 34}px) scale(${0.86 + iconProgress * 0.14})`,
        }}
      />
      <div
        style={{
          opacity: copyProgress,
          transform: `translateX(${(1 - copyProgress) * 34}px)`,
        }}
      >
        <div
          style={{
            fontSize: compact ? 74 : 106,
            lineHeight: 0.94,
            fontWeight: 790,
            letterSpacing: '-0.065em',
          }}
        >
          {title}
        </div>
        <div
          style={{
            marginTop: compact ? 13 : 20,
            fontSize: compact ? 30 : 38,
            fontWeight: 520,
            color: COLORS.secondary,
            letterSpacing: '-0.02em',
          }}
        >
          {detail}
        </div>
      </div>
    </div>
  );
};

export const SceneMarker: React.FC<{label: string}> = ({label}) => (
  <div
    style={{
      position: 'absolute',
      top: 64,
      left: 74,
      display: 'flex',
      alignItems: 'center',
      gap: 14,
      color: COLORS.secondary,
      fontSize: 21,
      fontWeight: 620,
      letterSpacing: '0.05em',
    }}
  >
    <AppIcon size={34} style={{filter: 'none'}} />
    {label}
  </div>
);
