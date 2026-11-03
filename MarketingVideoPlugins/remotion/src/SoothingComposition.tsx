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
  0.9, 1.7, 2.45, 3.24, 3.8, 4.55, 5.35, 6.15, 7.45, 8.15, 8.85,
  9.42, 9.75, 10.4, 11.05, 11.7, 12.65, 13.42, 14.38,
];

const pulseAt = (frame: number, seconds: number, durationInFrames = 6) => {
  const distance = Math.abs(frame - seconds * FPS);
  return interpolate(distance, [0, durationInFrames], [1, 0], clamp);
};

const SoothingReactiveLayer: React.FC<{audioSource: string}> = ({audioSource}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const {audioData, dataOffsetInSeconds} = useWindowedAudioData({
    src: audioSource,
    frame,
    fps,
    windowInSeconds: DURATION_SECONDS,
  });

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
  const impact = Math.max(...soundHits.map((seconds) => pulseAt(frame, seconds)));
  const energy = Math.min(1, bass * 4 + impact * 0.28);
  const line = frequencies.slice(0, 32);

  return (
    <AbsoluteFill style={{pointerEvents: "none"}}>
      <div
        style={{
          position: "absolute",
          inset: 0,
          boxShadow: `inset 0 0 ${70 + energy * 90}px rgba(255,182,193,${0.025 + energy * 0.09})`,
        }}
      />
      <div
        style={{
          position: "absolute",
          left: 190,
          right: 190,
          bottom: 54,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          gap: 8,
          height: 18,
          opacity: 0.18,
        }}
      >
        {line.map((value, index) => (
          <div
            key={index}
            style={{
              width: 10,
              height: 2 + Math.min(1, value * 5) * 11,
              borderRadius: 6,
              backgroundColor: index < 16 ? "#FFB6C1" : "#C9B9FF",
            }}
          />
        ))}
      </div>
    </AbsoluteFill>
  );
};

const FinalBlackout: React.FC = () => {
  const frame = useCurrentFrame();
  const opacity = interpolate(frame, [14.56 * FPS, 14.76 * FPS], [0, 1], {
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

const TappySoothingVideo: React.FC = () => {
  const videoSource = staticFile("tappy-soothing-base.mp4");
  const audioSource = staticFile("tappy-soothing-audio.wav");

  return (
    <AbsoluteFill style={{backgroundColor: "#151416"}}>
      <Video
        src={videoSource}
        muted
        objectFit="cover"
        style={{width: "100%", height: "100%"}}
      />
      <Audio src={audioSource} volume={1} />
      <SoothingReactiveLayer audioSource={audioSource} />
      <FinalBlackout />
    </AbsoluteFill>
  );
};

export const TappySoothingComposition: React.FC = () => {
  return (
    <Composition
      id="TappySoothing15"
      component={TappySoothingVideo}
      durationInFrames={DURATION_SECONDS * FPS}
      fps={FPS}
      width={1080}
      height={1920}
    />
  );
};
