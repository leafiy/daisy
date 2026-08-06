import {Easing, interpolate} from 'remotion';

export const COLORS = {
  white: '#FFFFFF',
  surface: '#F7F9FC',
  ink: '#111827',
  secondary: '#667085',
  blue: '#2F7DF6',
  mint: '#32C9A3',
  line: '#D9E1EC',
};

export const FONT =
  '-apple-system, BlinkMacSystemFont, "SF Pro Display", "PingFang SC", "Helvetica Neue", sans-serif';

export const clamp = {
  extrapolateLeft: 'clamp' as const,
  extrapolateRight: 'clamp' as const,
};

export const easeOut = Easing.bezier(0.25, 0.46, 0.45, 0.94);
export const easeHero = Easing.bezier(0.2, 1, 0.3, 1);

export const fade = (
  frame: number,
  duration: number,
  fadeIn = 18,
  fadeOut = 18,
) => {
  const enter = interpolate(frame, [0, fadeIn], [0, 1], clamp);
  const exit = interpolate(frame, [duration - fadeOut, duration], [1, 0], clamp);
  return Math.min(enter, exit);
};

export const settle = (frame: number, from: number, to: number) =>
  interpolate(frame, [from, to], [0, 1], {
    ...clamp,
    easing: easeOut,
  });
