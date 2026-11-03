import {Video} from "@remotion/media";
import React from "react";
import {
  AbsoluteFill,
  Composition,
  Easing,
  interpolate,
  Sequence,
  staticFile,
  useCurrentFrame,
} from "remotion";

const FPS = 30;
const SOURCE_FRAMES = 17 * FPS;
const ENDING_START = 388;
const OVERLAY_START = 394;
const OVERLAY_HOLD_END = 436;
const OVERLAY_END = 447;

const clamp = {
  extrapolateLeft: "clamp" as const,
  extrapolateRight: "clamp" as const,
};

const FullFrameVideo: React.FC<{src: string; trimBefore?: number}> = ({
  src,
  trimBefore,
}) => (
  <Video
    src={staticFile(src)}
    trimBefore={trimBefore}
    objectFit="cover"
    style={{width: "100%", height: "100%"}}
  />
);

const MoreSoundsOverlay: React.FC = () => {
  const frame = useCurrentFrame();
  const enter = interpolate(frame, [OVERLAY_START, OVERLAY_START + 12], [0, 1], {
    ...clamp,
    easing: Easing.out(Easing.cubic),
  });
  const leave = interpolate(frame, [OVERLAY_HOLD_END, OVERLAY_END], [1, 0], {
    ...clamp,
    easing: Easing.in(Easing.cubic),
  });
  const visibility = Math.min(enter, leave);

  return (
    <AbsoluteFill
      style={{
        pointerEvents: "none",
        color: "#F8F8F6",
        fontFamily:
          "Inter, -apple-system, BlinkMacSystemFont, Helvetica Neue, sans-serif",
      }}
    >
      <div
        style={{
          position: "absolute",
          top: 940,
          left: 0,
          right: 0,
          display: "flex",
          alignItems: "baseline",
          justifyContent: "center",
          gap: 14,
          opacity: visibility,
          filter: `blur(${(1 - visibility) * 5}px)`,
          transform: `translateY(${(1 - enter) * 18 - (1 - leave) * 8}px)`,
        }}
      >
        <span style={{color: "#FFB6C1", fontSize: 48, fontWeight: 720}}>
          +
        </span>
        <span style={{fontSize: 46, fontWeight: 720}}>
          more sounds
        </span>
      </div>
    </AbsoluteFill>
  );
};

const TappyMoreSoundsOverlay: React.FC = () => (
  <AbsoluteFill style={{backgroundColor: "#070809"}}>
    <Sequence durationInFrames={ENDING_START}>
      <FullFrameVideo src="tappy-reordered-showcase-base.mp4" />
    </Sequence>
    <Sequence
      from={ENDING_START}
      durationInFrames={SOURCE_FRAMES - ENDING_START}
    >
      <FullFrameVideo
        src="tappy-bubbles-source.mp4"
        trimBefore={ENDING_START}
      />
    </Sequence>
    <MoreSoundsOverlay />
  </AbsoluteFill>
);

export const TappyMoreSoundsInsertComposition: React.FC = () => (
  <Composition
    id="TappyBubblesWithMoreSoundsOverlay"
    component={TappyMoreSoundsOverlay}
    durationInFrames={SOURCE_FRAMES}
    fps={FPS}
    width={1080}
    height={1920}
  />
);
