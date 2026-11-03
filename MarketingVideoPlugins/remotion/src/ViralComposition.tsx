import {Audio, Video} from "@remotion/media";
import {useWindowedAudioData, visualizeAudio} from "@remotion/media-utils";
import React from "react";
import {
  AbsoluteFill,
  Composition,
  Easing,
  interpolate,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";

const FPS = 30;
const DURATION_SECONDS = 15;

const clamp = {
  extrapolateLeft: "clamp" as const,
  extrapolateRight: "clamp" as const,
};

const soundHits = [
  0.78, 1.67, 2.54, 3.24, 3.36, 3.49, 3.62, 3.74, 3.87, 3.99,
  4.13, 4.25, 4.38, 4.51, 4.65, 4.79, 4.92, 5.04, 5.18, 5.31,
  5.44, 5.58, 5.71, 5.84, 5.98, 6.1, 6.24, 6.37, 6.5, 6.63,
  7.12, 7.34, 7.61, 7.89, 8.17, 8.43, 8.68, 8.82, 9.1, 9.38,
  9.67, 9.96, 10.24, 10.38, 10.61, 10.84, 11.08, 11.31, 11.55, 14.44,
];

const pulseAt = (frame: number, seconds: number, durationInFrames = 4) => {
  const distance = Math.abs(frame - seconds * FPS);
  return interpolate(distance, [0, durationInFrames], [1, 0], clamp);
};

const SoundReactiveLayer: React.FC<{audioSource: string}> = ({audioSource}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const {audioData, dataOffsetInSeconds} = useWindowedAudioData({
    src: audioSource,
    frame,
    fps,
    windowInSeconds: DURATION_SECONDS,
  });

  const impact = Math.max(...soundHits.map((seconds) => pulseAt(frame, seconds, 3)));
  const activationFlash = interpolate(frame, [84, 90, 96], [0, 0.82, 0], clamp);
  const carouselSnap = Math.max(pulseAt(frame, 8.68, 7), pulseAt(frame, 10.24, 7));

  if (!audioData) {
    return null;
  }

  const frequencies = visualizeAudio({
    fps,
    frame,
    audioData,
    numberOfSamples: 64,
    optimizeFor: "speed",
    dataOffsetInSeconds,
  });
  const bass = frequencies.slice(0, 12).reduce((sum, value) => sum + value, 0) / 12;
  const energy = Math.min(1, bass * 5.2 + impact * 0.36);
  const bars = frequencies.slice(0, 28);

  return (
    <AbsoluteFill style={{pointerEvents: "none"}}>
      <div
        style={{
          position: "absolute",
          inset: 0,
          boxShadow: `inset 0 0 ${44 + energy * 142}px rgba(255,182,193,${0.04 + energy * 0.2})`,
          backgroundColor: `rgba(255,182,193,${impact * 0.045})`,
        }}
      />
      <div
        style={{
          position: "absolute",
          inset: 0,
          opacity: activationFlash,
          backgroundColor: "#FFFFFF",
          mixBlendMode: "screen",
        }}
      />
      <div
        style={{
          position: "absolute",
          left: 62,
          right: 62,
          top: 888,
          height: 5,
          opacity: carouselSnap * 0.9,
          backgroundColor: "#FFB6C1",
          boxShadow: "0 0 34px 12px rgba(255,182,193,0.5)",
          transform: `scaleX(${0.24 + carouselSnap * 0.76})`,
        }}
      />
      <div
        style={{
          position: "absolute",
          left: 130,
          right: 130,
          bottom: 54,
          display: "flex",
          alignItems: "flex-end",
          justifyContent: "center",
          gap: 9,
          height: 42,
          opacity: 0.42,
        }}
      >
        {bars.map((value, index) => (
          <div
            key={index}
            style={{
              width: 16,
              height: 5 + Math.min(1, value * 5.8) * 36,
              borderRadius: 9,
              backgroundColor: index < 10 ? "#FFD5DC" : "#FFB6C1",
              boxShadow: impact > 0.2 ? "0 0 14px rgba(255,182,193,0.48)" : "none",
            }}
          />
        ))}
      </div>
    </AbsoluteFill>
  );
};

const ProgressRail: React.FC = () => {
  const frame = useCurrentFrame();
  const progress = interpolate(frame, [0, DURATION_SECONDS * FPS - 1], [0, 1], clamp);
  const reveal = interpolate(frame, [0, 12], [0, 1], {
    ...clamp,
    easing: Easing.bezier(0.16, 1, 0.3, 1),
  });

  return (
    <div
      style={{
        position: "absolute",
        left: 0,
        right: 0,
        bottom: 0,
        height: 7,
        opacity: reveal,
        backgroundColor: "rgba(255,255,255,0.12)",
      }}
    >
      <div
        style={{
          width: `${progress * 100}%`,
          height: "100%",
          backgroundColor: "#FFB6C1",
          boxShadow: "0 0 20px rgba(255,182,193,0.72)",
        }}
      />
    </div>
  );
};

const FinalBlackout: React.FC = () => {
  const frame = useCurrentFrame();
  const opacity = interpolate(frame, [14.52 * FPS, 14.7 * FPS], [0, 1], {
    ...clamp,
    easing: Easing.in(Easing.cubic),
  });

  return (
    <AbsoluteFill
      style={{
        pointerEvents: "none",
        opacity,
        backgroundColor: "#000000",
      }}
    />
  );
};

const TappyViralVideo: React.FC = () => {
  const videoSource = staticFile("tappy-viral-base.mp4");
  const audioSource = staticFile("tappy-viral-audio.wav");

  return (
    <AbsoluteFill style={{backgroundColor: "#1A1A1A"}}>
      <Video
        src={videoSource}
        muted
        objectFit="cover"
        style={{width: "100%", height: "100%"}}
      />
      <Audio src={audioSource} volume={1} />
      <SoundReactiveLayer audioSource={audioSource} />
      <ProgressRail />
      <FinalBlackout />
    </AbsoluteFill>
  );
};

export const TappyViralComposition: React.FC = () => {
  return (
    <Composition
      id="TappyViral15"
      component={TappyViralVideo}
      durationInFrames={DURATION_SECONDS * FPS}
      fps={FPS}
      width={1080}
      height={1920}
    />
  );
};
