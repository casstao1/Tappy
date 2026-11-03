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
const DURATION_SECONDS = 31;

type Caption = {
  start: number;
  end: number;
  text: string;
};

const captions: Caption[] = [
  {start: 0, end: 4.2, text: "I made every key on my Mac sound satisfying."},
  {start: 4.2, end: 9.4, text: "Tappy lives in the menu bar."},
  {start: 9.4, end: 14.8, text: "It works wherever you type."},
  {start: 14.8, end: 21, text: "Choose the texture that feels right."},
  {start: 21, end: 25.7, text: "Eight sound packs. Two included."},
  {start: 25.7, end: 31, text: "Private, local playback. Free to download."},
];

const clamp = {
  extrapolateLeft: "clamp" as const,
  extrapolateRight: "clamp" as const,
};

const AudioReactiveOverlay: React.FC<{audioSource: string}> = ({audioSource}) => {
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
  const scaledBass = Math.min(1, bass * 4.8);
  const bars = frequencies.slice(0, 36);

  return (
    <AbsoluteFill style={{pointerEvents: "none"}}>
      <div
        style={{
          position: "absolute",
          inset: 0,
          boxShadow: `inset 0 0 ${48 + scaledBass * 120}px rgba(138,107,255,${0.08 + scaledBass * 0.24})`,
        }}
      />
      <div
        style={{
          position: "absolute",
          left: 116,
          right: 116,
          bottom: 22,
          height: 28,
          display: "flex",
          alignItems: "flex-end",
          justifyContent: "center",
          gap: 7,
          opacity: 0.28,
        }}
      >
        {bars.map((value, index) => {
          const height = 4 + Math.min(1, value * 5.2) * 23;
          return (
            <div
              key={index}
              style={{
                width: 11,
                height,
                borderRadius: 8,
                backgroundColor: index < 12 ? "#C9BBFF" : "#8A6BFF",
              }}
            />
          );
        })}
      </div>
    </AbsoluteFill>
  );
};

const SocialCaption: React.FC = () => {
  const frame = useCurrentFrame();
  const seconds = frame / FPS;
  const caption = captions.find(({start, end}) => seconds >= start && seconds < end) ?? captions[captions.length - 1];
  const localFrame = frame - caption.start * FPS;
  const durationFrames = (caption.end - caption.start) * FPS;
  const enter = interpolate(localFrame, [0, 10], [0, 1], {
    ...clamp,
    easing: Easing.bezier(0.16, 1, 0.3, 1),
  });
  const exit = interpolate(localFrame, [durationFrames - 9, durationFrames], [1, 0], {
    ...clamp,
    easing: Easing.in(Easing.cubic),
  });
  const opacity = Math.min(enter, exit);
  const translateY = interpolate(enter, [0, 1], [22, 0]);

  return (
    <div
      style={{
        position: "absolute",
        left: 120,
        right: 120,
        bottom: 68,
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        gap: 10,
        opacity,
        transform: `translateY(${translateY}px)`,
        textAlign: "center",
        color: "#F4F1FA",
        fontFamily: "Inter, Arial, sans-serif",
        fontSize: 30,
        fontWeight: 720,
        lineHeight: 1.16,
        textShadow: "0 3px 20px rgba(0,0,0,0.92)",
      }}
    >
      <span>{caption.text}</span>
      <span
        style={{
          width: 72,
          height: 3,
          borderRadius: 4,
          backgroundColor: "#8A6BFF",
          boxShadow: "0 0 18px rgba(138,107,255,0.72)",
        }}
      />
    </div>
  );
};

const ProgressRail: React.FC = () => {
  const frame = useCurrentFrame();
  const progress = interpolate(frame, [0, DURATION_SECONDS * FPS - 1], [0, 1], clamp);
  return (
    <div
      style={{
        position: "absolute",
        left: 0,
        right: 0,
        bottom: 0,
        height: 7,
        backgroundColor: "rgba(244,241,250,0.08)",
      }}
    >
      <div
        style={{
          width: `${progress * 100}%`,
          height: "100%",
          backgroundColor: "#8A6BFF",
          boxShadow: "0 0 18px rgba(138,107,255,0.72)",
        }}
      />
    </div>
  );
};

const TappyPluginVideo: React.FC = () => {
  const videoSource = staticFile("hyperframes-base.mp4");
  const audioSource = staticFile("tappy-audio.wav");

  return (
    <AbsoluteFill style={{backgroundColor: "#0B0913"}}>
      <Video
        src={videoSource}
        muted
        objectFit="cover"
        style={{width: "100%", height: "100%"}}
      />
      <Audio
        src={audioSource}
        volume={(frame) =>
          interpolate(frame, [0, 8, DURATION_SECONDS * FPS - 24, DURATION_SECONDS * FPS], [0, 1, 1, 0], clamp)
        }
      />
      <AudioReactiveOverlay audioSource={audioSource} />
      <SocialCaption />
      <ProgressRail />
    </AbsoluteFill>
  );
};

export const TappyComposition: React.FC = () => {
  return (
    <Composition
      id="TappyPluginPromo"
      component={TappyPluginVideo}
      durationInFrames={DURATION_SECONDS * FPS}
      fps={FPS}
      width={1080}
      height={1920}
    />
  );
};
