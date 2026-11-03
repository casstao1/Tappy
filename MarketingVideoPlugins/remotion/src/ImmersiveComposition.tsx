import {Audio} from "@remotion/media";
import React from "react";
import {
  AbsoluteFill,
  Composition,
  Easing,
  Img,
  interpolate,
  spring,
  staticFile,
  useCurrentFrame,
} from "remotion";

const FPS = 30;
const DURATION_IN_FRAMES = 24 * FPS;

const clamp = {
  extrapolateLeft: "clamp" as const,
  extrapolateRight: "clamp" as const,
};

const fontFamily =
  "Inter, -apple-system, BlinkMacSystemFont, Helvetica Neue, sans-serif";

const colors = {
  ink: "#090A0C",
  charcoal: "#15171A",
  white: "#F8F8F6",
  muted: "#A8AAAE",
  pink: "#FFB6C1",
  cyan: "#74DDE3",
  green: "#9BCBA7",
  amber: "#EFCB77",
  lilac: "#C5B7F2",
};

type Theme = {
  id: string;
  name: string;
  micro: string;
  accent: string;
  accentTwo: string;
  deck: string;
  keyTop: string;
  keySide: string;
  glow: string;
};

const themes: Theme[] = [
  {
    id: "bubble",
    name: "Bubbles",
    micro: "airy / round / glossy",
    accent: "#79E0D8",
    accentTwo: "#FFB6C1",
    deck: "#13272A",
    keyTop: "#29656A",
    keySide: "#163D41",
    glow: "rgba(121,224,216,0.34)",
  },
  {
    id: "wet",
    name: "Wet Squishy Pop",
    micro: "soft / tactile / close",
    accent: "#FF9DB0",
    accentTwo: "#C5B7F2",
    deck: "#2B1922",
    keyTop: "#7D4052",
    keySide: "#4B2532",
    glow: "rgba(255,157,176,0.4)",
  },
  {
    id: "wax",
    name: "Wax Cracking",
    micro: "crisp / layered / brittle",
    accent: "#E9C8A8",
    accentTwo: "#C5B7F2",
    deck: "#29231F",
    keyTop: "#8E705C",
    keySide: "#554236",
    glow: "rgba(233,200,168,0.34)",
  },
  {
    id: "wood",
    name: "Wood and Sand Blocks",
    micro: "dry / warm / grounded",
    accent: "#B7D39E",
    accentTwo: "#D7A86E",
    deck: "#20271C",
    keyTop: "#5D704D",
    keySide: "#37442F",
    glow: "rgba(183,211,158,0.3)",
  },
  {
    id: "mechanical",
    name: "Mechanical Ticks",
    micro: "precise / compact / clean",
    accent: "#BFD5F5",
    accentTwo: "#74DDE3",
    deck: "#1D222A",
    keyTop: "#566375",
    keySide: "#343C48",
    glow: "rgba(191,213,245,0.32)",
  },
  {
    id: "star",
    name: "Star Level Up",
    micro: "bright / light / clear",
    accent: "#F5D46F",
    accentTwo: "#9BCBA7",
    deck: "#292617",
    keyTop: "#817130",
    keySide: "#4C431D",
    glow: "rgba(245,212,111,0.32)",
  },
  {
    id: "plastic",
    name: "Tapping Nails on Plastic",
    micro: "light / glossy / subtle",
    accent: "#78C8FF",
    accentTwo: "#FFB6C1",
    deck: "#17232E",
    keyTop: "#386684",
    keySide: "#234054",
    glow: "rgba(120,200,255,0.3)",
  },
];

const hitTimes = [
  0.34, 1.28, 1.39, 1.49, 1.6, 1.7, 1.81, 1.91, 2.18, 2.28, 2.38,
  2.48, 2.57, 2.67, 3.02, 3.11, 3.21, 3.3, 3.4, 3.49, 3.58, 3.68,
  4.2, 4.34, 4.47, 4.61, 4.74, 5.1, 5.24, 5.38, 5.52, 5.66, 6.0,
  6.14, 6.28, 6.42, 6.56, 6.9, 7.03, 7.16, 7.3, 7.43, 7.8, 7.92,
  8.03, 8.15, 8.26, 8.38, 8.7, 8.83, 8.96, 9.09, 9.22, 9.63, 9.92,
  10.25, 10.62, 11.03, 11.42, 11.82, 12.18, 13.05, 13.68, 14.05,
  15.03, 15.62, 15.71, 15.8, 15.89, 15.98, 16.07, 16.16, 16.42,
  16.52, 16.62, 16.72, 16.82, 16.92, 17.22, 17.31, 17.4, 17.5, 17.59,
  17.68, 17.77, 18.02, 18.11, 18.2, 18.28, 18.37, 18.46, 18.55, 18.82,
  18.92, 19.02, 19.12, 19.22, 19.32, 19.62, 19.72, 19.81, 19.91,
  20.0, 20.1, 20.48, 22.28, 22.94,
];

const sceneOpacity = (
  frame: number,
  start: number,
  end: number,
  edge = 5,
) =>
  Math.min(
    interpolate(frame, [start, start + edge], [0, 1], clamp),
    interpolate(frame, [end - edge, end], [1, 0], clamp),
  );

const easeIn = (frame: number, start: number, duration = 15) =>
  interpolate(frame, [start, start + duration], [0, 1], {
    ...clamp,
    easing: Easing.out(Easing.cubic),
  });

const pulseAt = (frame: number, width = 4) => {
  const values = hitTimes.map((time) =>
    interpolate(Math.abs(frame - time * FPS), [0, width], [1, 0], clamp),
  );
  return Math.max(...values);
};

const pulseForTimes = (frame: number, times: number[], width = 4) =>
  Math.max(
    ...times.map((time) =>
      interpolate(Math.abs(frame - time * FPS), [0, width], [1, 0], clamp),
    ),
  );

const AppIcon: React.FC<{size?: number; style?: React.CSSProperties}> = ({
  size = 120,
  style,
}) => (
  <Img
    src={staticFile("tappy-icon.png")}
    style={{
      width: size,
      height: size,
      borderRadius: size * 0.23,
      objectFit: "cover",
      boxShadow: "0 24px 60px rgba(0,0,0,0.35)",
      ...style,
    }}
  />
);

const Waveform: React.FC<{
  frame: number;
  accent: string;
  width?: number;
  quiet?: boolean;
  hits?: number[];
}> = ({frame, accent, width = 320, quiet = false, hits}) => {
  const pulse = hits ? pulseForTimes(frame, hits, 5) : pulseAt(frame, 5);
  return (
    <div
      style={{
        width,
        height: 48,
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        gap: 7,
      }}
    >
      {Array.from({length: 23}).map((_, index) => {
        const wave = Math.abs(Math.sin(index * 1.21 + frame * 0.055));
        const height = quiet ? 3 + wave * 3 : 5 + wave * 10 + pulse * 22;
        return (
          <span
            key={index}
            style={{
              width: 5,
              height,
              borderRadius: 5,
              backgroundColor: accent,
              opacity: quiet ? 0.38 : 0.42 + pulse * 0.5,
            }}
          />
        );
      })}
    </div>
  );
};

type MacKey = {
  label: string;
  units?: number;
  kind?: "function" | "space" | "arrow-stack";
};

const macKeys: MacKey[][] = [
  [
    {label: "esc", units: 1.25, kind: "function"},
    ...Array.from({length: 12}).map((_, index) => ({
      label: `F${index + 1}`,
      kind: "function" as const,
    })),
    {label: "power", units: 1.3, kind: "function"},
  ],
  [
    {label: "`"},
    ...Array.from({length: 10}).map((_, index) => ({
      label: String((index + 1) % 10),
    })),
    {label: "-"},
    {label: "="},
    {label: "delete", units: 1.8},
  ],
  [
    {label: "tab", units: 1.5},
    ..."QWERTYUIOP".split("").map((label) => ({label})),
    {label: "["},
    {label: "]"},
    {label: "\\"},
  ],
  [
    {label: "caps", units: 1.75},
    ..."ASDFGHJKL".split("").map((label) => ({label})),
    {label: ";"},
    {label: "'"},
    {label: "return", units: 2.15},
  ],
  [
    {label: "shift", units: 2.2},
    ..."ZXCVBNM".split("").map((label) => ({label})),
    {label: ","},
    {label: "."},
    {label: "/"},
    {label: "shift", units: 2.65},
  ],
  [
    {label: "fn"},
    {label: "control", units: 1.15},
    {label: "option", units: 1.2},
    {label: "command", units: 1.45},
    {label: "", units: 5.2, kind: "space"},
    {label: "command", units: 1.45},
    {label: "option", units: 1.2},
    {label: "<", units: 0.78},
    {label: "", units: 0.78, kind: "arrow-stack"},
    {label: ">", units: 0.78},
  ],
];

const keySequence = ["S", "E", "N", "D", "M", "O", "R", "E", "T", "A", "P", "P", "Y"];

const SpeakerGrille: React.FC<{side: "left" | "right"}> = ({side}) => (
  <div
    style={{
      position: "absolute",
      top: 32,
      bottom: 38,
      width: 43,
      left: side === "left" ? 24 : undefined,
      right: side === "right" ? 24 : undefined,
      display: "grid",
      gridTemplateColumns: "repeat(5, 3px)",
      gridAutoRows: "3px",
      alignContent: "space-around",
      justifyContent: "space-between",
      opacity: 0.68,
    }}
  >
    {Array.from({length: 65}).map((_, index) => (
      <span
        key={index}
        style={{
          width: 3,
          height: 3,
          borderRadius: "50%",
          backgroundColor: "rgba(4,5,6,0.84)",
          boxShadow: "0 1px 0 rgba(255,255,255,0.055)",
        }}
      />
    ))}
  </div>
);

const Keyboard: React.FC<{
  frame: number;
  localFrame: number;
  theme: Theme;
  scale?: number;
  tilt?: number;
  macro?: boolean;
  hits?: number[];
}> = ({
  frame,
  localFrame,
  theme,
  scale = 1,
  tilt = 5,
  macro = false,
  hits,
}) => {
  const pulse = hits ? pulseForTimes(frame, hits, 3.5) : pulseAt(frame, 3.5);
  const active =
    keySequence[
      Math.floor(Math.max(0, localFrame) / 3) % keySequence.length
    ];

  return (
    <div
      style={{
        position: "relative",
        width: 930,
        padding: macro ? "25px 21px 39px" : "22px 20px 34px",
        borderRadius: 28,
        background:
          "linear-gradient(145deg, #4B4F54 0%, #34373B 49%, #26292D 100%)",
        border: "0.75px solid rgba(255,255,255,0.2)",
        boxShadow:
          "0 5px 0 #1D1F22, 0 70px 132px rgba(0,0,0,0.53), 0 18px 42px rgba(0,0,0,0.31), inset 0 1px 0 rgba(255,255,255,0.16)",
        transform: `perspective(1250px) rotateX(${tilt}deg) rotateZ(${Math.sin(localFrame * 0.018) * 0.34}deg) translateX(${Math.sin(localFrame * 0.012) * 2.4}px) scale(${scale + pulse * 0.003})`,
        transformOrigin: "center",
      }}
      data-sound-theme={theme.id}
    >
      <div
        style={{
          position: "absolute",
          inset: 0,
          borderRadius: 28,
          pointerEvents: "none",
          background:
            "linear-gradient(118deg, rgba(255,255,255,0.13) 0%, rgba(255,255,255,0.025) 27%, transparent 48%, rgba(255,255,255,0.045) 78%, transparent 100%)",
          boxShadow: "inset 0 -1px 0 rgba(0,0,0,0.5)",
        }}
      />
      <div
        style={{
          position: "absolute",
          top: macro ? 17 : 14,
          bottom: macro ? 30 : 26,
          left: macro ? 77 : 74,
          right: macro ? 77 : 74,
          borderRadius: 19,
          background: "linear-gradient(155deg, #151618, #090A0B)",
          border: "0.75px solid rgba(0,0,0,0.72)",
          boxShadow:
            "inset 0 12px 25px rgba(0,0,0,0.44), inset 0 1px 0 rgba(255,255,255,0.04)",
        }}
      />
      <SpeakerGrille side="left" />
      <SpeakerGrille side="right" />
      <div
        style={{
          position: "relative",
          marginLeft: macro ? 64 : 62,
          marginRight: macro ? 64 : 62,
        }}
      >
        {macKeys.map((row, rowIndex) => (
          <div
            key={rowIndex}
            style={{
              position: "relative",
              display: "flex",
              width: "100%",
              gap: macro ? 10 : 9,
              marginTop: rowIndex === 0 ? 0 : macro ? 10 : 9,
            }}
          >
            {row.map((key, index) => {
            const isActive = key.label === active && pulse > 0.08;
            const isFunction = key.kind === "function";
            const keyHeight = macro ? 56 : 49;
            const fontSize = isFunction
              ? 8
              : key.label.length > 6
                ? 8
                : key.label.length > 3
                  ? 9
                  : 13;

            if (key.kind === "arrow-stack") {
              return (
                <div
                  key={`${rowIndex}-${index}-arrows`}
                  style={{
                    height: keyHeight,
                    flex: `${key.units ?? 1} 1 0`,
                    minWidth: 0,
                    display: "flex",
                    flexDirection: "column",
                    gap: 4,
                  }}
                >
                  {["^", "v"].map((label) => (
                    <div
                      key={label}
                      style={{
                        flex: 1,
                        minHeight: 0,
                        borderRadius: 7,
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "center",
                        color: "rgba(250,250,250,0.72)",
                        fontSize: 9,
                        fontWeight: 620,
                        background: "linear-gradient(145deg, #2A2A2A, #1E1E1E)",
                        border: "0.75px solid rgba(255,255,255,0.08)",
                        boxShadow:
                          "0 2px 0 #090A0B, 0 4px 8px rgba(0,0,0,0.3), inset 0 1px 0 rgba(255,255,255,0.1)",
                      }}
                    >
                      {label}
                    </div>
                  ))}
                </div>
              );
            }

            const pressAmount = isActive
              ? Easing.inOut(Easing.cubic)(Math.min(1, pulse))
              : 0;

            return (
              <div
                key={`${rowIndex}-${index}-${key.label}`}
                style={{
                  height: keyHeight,
                  flex: `${key.units ?? 1} 1 0`,
                  minWidth: 0,
                  borderRadius: isFunction ? 6 : 8,
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                  color: `rgba(250,250,250,${0.72 + pressAmount * 0.23})`,
                  fontSize,
                  fontWeight: 620,
                  letterSpacing: 0,
                  background: `linear-gradient(145deg, rgb(${42 + pressAmount * 7}, ${42 + pressAmount * 7}, ${42 + pressAmount * 7}), rgb(${30 + pressAmount * 5}, ${30 + pressAmount * 5}, ${30 + pressAmount * 5}))`,
                  border: `0.75px solid rgba(255,255,255,${0.08 + pressAmount * 0.14})`,
                  boxShadow: `0 ${2 - pressAmount * 1.2}px 0 #090A0B, 0 ${4 - pressAmount * 1.5}px ${8 - pressAmount * 2}px rgba(0,0,0,${0.3 - pressAmount * 0.1}), inset 0 1px 0 rgba(255,255,255,${0.1 + pressAmount * 0.12})`,
                  transform: `translateY(${pressAmount * 3}px)`,
                  position: "relative",
                  isolation: "isolate",
                }}
              >
                <div
                  style={{
                    position: "absolute",
                    inset: -2,
                    zIndex: -1,
                    borderRadius: isFunction ? 7 : 9,
                    border: "1px solid rgba(255,255,255,0.52)",
                    opacity: pressAmount * 0.48,
                    transform: `scale(${0.96 + (1 - pressAmount) * 0.12})`,
                    boxShadow: `0 0 ${7 + (1 - pressAmount) * 9}px rgba(255,255,255,0.16)`,
                  }}
                />
                <span style={{position: "relative", zIndex: 1}}>
                  {key.kind === "space" ? "" : key.label}
                </span>
              </div>
            );
            })}
          </div>
        ))}
      </div>
    </div>
  );
};

const SoundTransition: React.FC<{
  frame: number;
  start: number;
  color: string;
  direction?: number;
}> = ({frame, start, color, direction = 1}) => {
  const local = frame - start;
  const progress = interpolate(local, [-2, 9], [0, 1], {
    ...clamp,
    easing: Easing.out(Easing.cubic),
  });
  const opacity = interpolate(local, [-2, 12, 18], [0, 0.22, 0], clamp);
  return (
    <div
      style={{
        position: "absolute",
        top: -100,
        bottom: -100,
        width: 360,
        left: direction > 0 ? -390 : undefined,
        right: direction < 0 ? -390 : undefined,
        backgroundColor: color,
        opacity,
        filter: "blur(75px)",
        transform: `translateX(${direction * progress * 1500}px) skewX(-12deg)`,
      }}
    />
  );
};

const IntroScene: React.FC<{frame: number}> = ({frame}) => {
  const opacity = sceneOpacity(frame, 0, 37, 4);
  const icon = spring({
    frame: frame - 9,
    fps: FPS,
    config: {damping: 17, mass: 0.7, stiffness: 115},
  });
  const title = easeIn(frame, 10, 10);
  const click = pulseForTimes(frame, [0.34], 6);

  return (
    <AbsoluteFill
      style={{
        opacity,
        alignItems: "center",
        justifyContent: "center",
        color: colors.white,
        backgroundColor: "#000",
      }}
    >
      <div
        style={{
          width: 118,
          height: 118,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          transform: `scale(${0.7 + icon * 0.3 + click * 0.03})`,
          opacity: icon,
        }}
      >
        <AppIcon size={98} />
      </div>
      <div
        style={{
          marginTop: 36,
          fontSize: 56,
          fontWeight: 850,
          opacity: title,
          transform: `translateY(${(1 - title) * 10}px)`,
        }}
      >
        Tappy
      </div>
      <div style={{marginTop: 20, opacity: title * 0.6}}>
        <Waveform frame={frame} accent={colors.pink} width={180} />
      </div>
    </AbsoluteFill>
  );
};

const HumanTypingScene: React.FC<{frame: number}> = ({frame}) => {
  const start = 30;
  const end = 128;
  const local = frame - start;
  const opacity = sceneOpacity(frame, start, end, 6);
  const shot = Math.max(0, Math.min(3, Math.floor(local / 24)));
  const shotLocal = ((local % 24) + 24) % 24;
  const cutBreath = interpolate(shotLocal, [0, 4, 20, 23], [0, 1, 1, 0], clamp);
  const positions = ["50% 56%", "72% 66%", "34% 74%", "58% 82%"];
  const scales = [1.02, 1.3, 1.42, 1.24];
  const phrases = [
    "Every key.",
    "A tiny texture.",
    "Right under your fingers.",
    "Everywhere you type.",
  ];
  const typedLength = Math.floor(
    interpolate(shotLocal, [2, 17], [0, phrases[shot].length], clamp),
  );
  const pulse = pulseAt(frame, 4);

  return (
    <AbsoluteFill
      style={{
        opacity,
        overflow: "hidden",
        color: colors.white,
        backgroundColor: colors.ink,
      }}
    >
      <Img
        src={staticFile("tappy-hands-macro.png")}
        style={{
          position: "absolute",
          inset: -40,
          width: "calc(100% + 80px)",
          height: "calc(100% + 80px)",
          objectFit: "cover",
          objectPosition: positions[shot],
          filter: `saturate(0.88) contrast(1.03) blur(${(1 - cutBreath) * 5}px)`,
          transform: `scale(${scales[shot] + shotLocal * 0.0017}) translateY(${Math.sin(local * 0.025) * 7}px)`,
        }}
      />
      <AbsoluteFill
        style={{
          background:
            "linear-gradient(180deg, rgba(5,7,10,0.78) 0%, rgba(5,7,10,0.08) 45%, rgba(5,7,10,0.68) 100%)",
        }}
      />
      <div
        style={{
          position: "absolute",
          left: 64,
          right: 64,
          top: 150,
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
        }}
      >
        <div
          style={{
            padding: "16px 22px",
            borderRadius: 30,
            display: "flex",
            alignItems: "center",
            gap: 12,
            backgroundColor: "rgba(8,10,13,0.58)",
            border: "1px solid rgba(255,255,255,0.12)",
            backdropFilter: "blur(24px)",
            fontSize: 19,
            fontWeight: 750,
          }}
        >
          <span
            style={{
              width: 10,
              height: 10,
              borderRadius: "50%",
              backgroundColor: colors.pink,
              boxShadow: `0 0 ${12 + pulse * 18}px ${colors.pink}`,
            }}
          />
          Tapping Nails on Plastic
        </div>
        <Waveform frame={frame} accent={colors.cyan} width={220} />
      </div>
      <div
        style={{
          position: "absolute",
          left: 70,
          right: 70,
          bottom: 162,
          minHeight: 160,
          color: colors.white,
          fontSize: shot === 2 ? 62 : 74,
          lineHeight: 1.02,
          fontWeight: 850,
          textShadow: "0 8px 34px rgba(0,0,0,0.55)",
        }}
      >
        {phrases[shot].slice(0, typedLength)}
        <span style={{color: colors.pink, opacity: shotLocal % 12 < 7 ? 1 : 0}}>
          |
        </span>
      </div>
    </AbsoluteFill>
  );
};

const WorldScene: React.FC<{
  frame: number;
  theme: Theme;
  index: number;
  start: number;
  end: number;
}> = ({frame, theme, index, start, end}) => {
  const local = frame - start;
  const opacity = sceneOpacity(frame, start, end, 4);
  const enter = easeIn(frame, start, 9);
  const pulse = pulseAt(frame, 4);
  const displayWords = ["pop", "squish", "crack", "knock", "tick", "glow"];

  return (
    <AbsoluteFill
      style={{
        opacity,
        overflow: "hidden",
        color: colors.white,
        background: `radial-gradient(circle at 50% 34%, ${theme.glow}, transparent 42%), linear-gradient(155deg, ${theme.deck}, ${colors.ink} 72%)`,
      }}
    >
      <SoundTransition
        frame={frame}
        start={start}
        color={theme.accent}
        direction={index % 2 === 0 ? 1 : -1}
      />
      <div
        style={{
          position: "absolute",
          left: 68,
          right: 68,
          top: 112,
          display: "flex",
          alignItems: "flex-start",
          justifyContent: "space-between",
          transform: `translateY(${(1 - enter) * 22}px)`,
          opacity: enter,
        }}
      >
        <div>
          <div
            style={{
              color: theme.accent,
              fontSize: 19,
              fontWeight: 850,
              textTransform: "uppercase",
            }}
          >
            Sound {index + 1 < 10 ? `0${index + 1}` : index + 1}
          </div>
          <div
            style={{
              width: 760,
              marginTop: 13,
              fontSize: theme.name.length > 20 ? 50 : 62,
              lineHeight: 1,
              fontWeight: 850,
            }}
          >
            {theme.name}
          </div>
          <div
            style={{
              marginTop: 15,
              color: "rgba(248,248,246,0.52)",
              fontSize: 22,
              fontWeight: 650,
            }}
          >
            {theme.micro}
          </div>
        </div>
        <div
          style={{
            width: 62,
            height: 62,
            borderRadius: 21,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            color: colors.ink,
            backgroundColor: theme.accent,
            fontSize: 21,
            fontWeight: 900,
            transform: `scale(${1 + pulse * 0.1})`,
            boxShadow: `0 0 ${28 + pulse * 25}px ${theme.glow}`,
          }}
        >
          {displayWords[index].slice(0, 1).toUpperCase()}
        </div>
      </div>
      <div
        style={{
          position: "absolute",
          left: 75,
          top: 506,
          width: 930,
          transform: `translateY(${(1 - enter) * 70}px) scale(${0.93 + enter * 0.07})`,
        }}
      >
        <Keyboard
          frame={frame}
          localFrame={local}
          theme={theme}
          scale={1}
          tilt={index % 2 === 0 ? 13 : 8}
        />
      </div>
      <div
        style={{
          position: "absolute",
          left: 0,
          right: 0,
          bottom: 162,
          textAlign: "center",
          color: theme.accent,
          fontSize: 32,
          fontWeight: 850,
          transform: `scale(${1 + pulse * 0.055})`,
        }}
      >
        {displayWords[index]}
      </div>
      <div
        style={{
          position: "absolute",
          left: 0,
          right: 0,
          bottom: 86,
          display: "flex",
          justifyContent: "center",
        }}
      >
        <Waveform frame={frame} accent={theme.accent} width={260} />
      </div>
    </AbsoluteFill>
  );
};

const SoundWorlds: React.FC<{frame: number}> = ({frame}) => {
  const start = 126;
  const length = 27;
  return (
    <>
      {themes.slice(0, 6).map((theme, index) => (
        <WorldScene
          key={theme.id}
          frame={frame}
          theme={theme}
          index={index}
          start={start + index * length}
          end={start + (index + 1) * length + 2}
        />
      ))}
    </>
  );
};

const MacroSequence: React.FC<{frame: number}> = ({frame}) => {
  const start = 288;
  const end = 380;
  const local = frame - start;
  const shot = Math.max(0, Math.min(2, Math.floor(local / 30)));
  const shotStart = start + shot * 30;
  const shotLocal = frame - shotStart;
  const opacity = sceneOpacity(frame, start, end, 5);
  const shotOpacity = interpolate(shotLocal, [0, 4, 25, 29], [0, 1, 1, 0], clamp);
  const macroThemes = [themes[4], themes[1], themes[2]];
  const theme = macroThemes[shot];
  const labels = ["compact click", "soft press", "layered crack"];
  const pulse = pulseAt(frame, 5);

  return (
    <AbsoluteFill
      style={{
        opacity,
        overflow: "hidden",
        color: colors.white,
        backgroundColor: colors.ink,
      }}
    >
      <AbsoluteFill
        style={{
          opacity: shotOpacity,
          background: `radial-gradient(circle at ${shot === 1 ? "72% 38%" : "48% 42%"}, ${theme.glow}, transparent 48%), ${colors.ink}`,
        }}
      />
      {shot === 0 ? (
        <div
          style={{
            position: "absolute",
            left: -118,
            top: 390,
            transform: `scale(${1.42 + pulse * 0.02}) rotate(-5deg)`,
          }}
        >
          <Keyboard
            frame={frame}
            localFrame={local}
            theme={theme}
            scale={1.12}
            tilt={20}
            macro
          />
        </div>
      ) : null}
      {shot === 1 ? (
        <>
          <Img
            src={staticFile("tappy-hands-macro.png")}
            style={{
              position: "absolute",
              inset: 0,
              width: "100%",
              height: "100%",
              objectFit: "cover",
              objectPosition: "63% 77%",
              filter: "saturate(0.82) contrast(1.08)",
              transform: `scale(${1.55 + shotLocal * 0.002})`,
              opacity: shotOpacity,
            }}
          />
          <AbsoluteFill
            style={{
              background:
                "linear-gradient(180deg, rgba(6,7,9,0.75), transparent 50%, rgba(6,7,9,0.72))",
            }}
          />
        </>
      ) : null}
      {shot === 2 ? (
        <div
          style={{
            position: "absolute",
            left: 110,
            right: 110,
            top: 440,
            height: 610,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
          }}
        >
          <div
            style={{
              width: 620,
              height: 360,
              borderRadius: 54,
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              color: colors.ink,
              background: `linear-gradient(145deg, ${theme.accent}, ${theme.accentTwo})`,
              border: "2px solid rgba(255,255,255,0.42)",
              boxShadow: `0 ${42 - pulse * 24}px 0 ${theme.keySide}, 0 80px 140px rgba(0,0,0,0.58), 0 0 ${80 + pulse * 60}px ${theme.glow}`,
              transform: `translateY(${pulse * 28}px) scale(${1 - pulse * 0.018})`,
              fontSize: 64,
              fontWeight: 900,
            }}
          >
            return
          </div>
          {[0, 1, 2, 3].map((index) => (
            <span
              key={index}
              style={{
                position: "absolute",
                left: 260 + index * 80,
                top: 212 - pulse * (80 + index * 17),
                width: 7,
                height: 64 + index * 18,
                borderRadius: 8,
                backgroundColor: theme.accent,
                opacity: pulse * 0.64,
                transform: `rotate(${-24 + index * 17}deg)`,
              }}
            />
          ))}
        </div>
      ) : null}
      <div
        style={{
          position: "absolute",
          left: 72,
          top: 120,
          color: "rgba(248,248,246,0.5)",
          fontSize: 20,
          fontWeight: 800,
          textTransform: "uppercase",
        }}
      >
        macro {shot + 1 < 10 ? `0${shot + 1}` : shot + 1}
      </div>
      <div
        style={{
          position: "absolute",
          left: 72,
          top: 165,
          color: colors.white,
          fontSize: 72,
          lineHeight: 1,
          fontWeight: 850,
          opacity: shotOpacity,
        }}
      >
        {labels[shot]}
      </div>
      <div
        style={{
          position: "absolute",
          left: 72,
          right: 72,
          bottom: 110,
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
        }}
      >
        <span style={{color: theme.accent, fontSize: 23, fontWeight: 800}}>
          {theme.name}
        </span>
        <Waveform frame={frame} accent={theme.accent} width={210} />
      </div>
    </AbsoluteFill>
  );
};

const packs = [
  {name: "Tapping Nails on Plastic", color: "#78C8FF", mark: "P"},
  {name: "Wood and Sand Blocks", color: "#9BCBA7", mark: "W"},
  {name: "Wet Squishy Pop", color: "#FF9DB0", mark: "S"},
  {name: "Wax Cracking", color: "#E9C8A8", mark: "C"},
];

const CustomizationScene: React.FC<{frame: number}> = ({frame}) => {
  const start = 376;
  const end = 476;
  const local = frame - start;
  const shot = Math.max(0, Math.min(2, Math.floor(local / 33)));
  const shotLocal = ((local % 33) + 33) % 33;
  const opacity = sceneOpacity(frame, start, end, 6);
  const cardIn = spring({
    frame: frame - start,
    fps: FPS,
    config: {damping: 18, mass: 0.8, stiffness: 105},
  });
  const selected = shot === 0 ? 2 : 3;
  const cursorY = shot === 0 ? 530 : shot === 1 ? 625 : 1046;
  const tap = interpolate(shotLocal, [8, 12, 17], [0, 1, 0], clamp);
  const slider = interpolate(shotLocal, [6, 24], [0.46, 0.84], clamp);

  return (
    <AbsoluteFill
      style={{
        opacity,
        overflow: "hidden",
        color: colors.white,
        background:
          "radial-gradient(circle at 52% 22%, rgba(116,221,227,0.12), transparent 36%), linear-gradient(160deg, #11161A, #090A0C 76%)",
      }}
    >
      <div
        style={{
          position: "absolute",
          left: 66,
          right: 66,
          top: 92,
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
        }}
      >
        <div>
          <div
            style={{
              color: colors.cyan,
              fontSize: 19,
              fontWeight: 850,
              textTransform: "uppercase",
            }}
          >
            Make it yours
          </div>
          <div style={{marginTop: 10, fontSize: 58, fontWeight: 850}}>
            Pick a feeling.
          </div>
        </div>
        <Waveform frame={frame} accent={shot === 1 ? colors.pink : colors.cyan} width={190} />
      </div>
      <div
        style={{
          position: "absolute",
          left: 96,
          right: 96,
          top: 285,
          minHeight: 1180,
          padding: "38px 38px 42px",
          borderRadius: 48,
          backgroundColor: "rgba(30,32,35,0.9)",
          border: "1px solid rgba(255,255,255,0.13)",
          boxShadow: "0 58px 130px rgba(0,0,0,0.52)",
          transform: `translateY(${(1 - cardIn) * 90}px) scale(${0.95 + cardIn * 0.05})`,
        }}
      >
        <div
          style={{
            display: "flex",
            alignItems: "center",
            justifyContent: "space-between",
            paddingBottom: 28,
            borderBottom: "1px solid rgba(255,255,255,0.1)",
          }}
        >
          <div style={{display: "flex", alignItems: "center", gap: 18}}>
            <AppIcon size={62} style={{borderRadius: 15, boxShadow: "none"}} />
            <div>
              <div style={{fontSize: 31, fontWeight: 850}}>Tappy</div>
              <div
                style={{
                  marginTop: 3,
                  color: "rgba(248,248,246,0.5)",
                  fontSize: 18,
                  fontWeight: 650,
                }}
              >
                Auditory typing feedback
              </div>
            </div>
          </div>
          <div
            style={{
              display: "flex",
              alignItems: "center",
              gap: 10,
              color: "#61DC87",
              fontSize: 20,
              fontWeight: 800,
            }}
          >
            <span
              style={{width: 12, height: 12, borderRadius: "50%", backgroundColor: "#61DC87"}}
            />
            Active
          </div>
        </div>
        <div style={{paddingTop: 22}}>
          {packs.map((pack, index) => {
            const isSelected = index === selected;
            return (
              <div
                key={pack.name}
                style={{
                  height: 116,
                  padding: "0 12px",
                  display: "flex",
                  alignItems: "center",
                  gap: 20,
                  borderBottom: "1px solid rgba(255,255,255,0.065)",
                  backgroundColor: isSelected ? `${pack.color}12` : "transparent",
                }}
              >
                <span
                  style={{
                    width: 68,
                    height: 68,
                    borderRadius: 19,
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                    color: pack.color,
                    backgroundColor: `${pack.color}1F`,
                    fontSize: 24,
                    fontWeight: 900,
                  }}
                >
                  {pack.mark}
                </span>
                <span style={{flex: 1, fontSize: 25, fontWeight: isSelected ? 820 : 650}}>
                  {pack.name}
                </span>
                {isSelected ? (
                  <span style={{color: pack.color, fontSize: 30, fontWeight: 900}}>✓</span>
                ) : null}
              </div>
            );
          })}
        </div>
        <div
          style={{
            marginTop: 30,
            paddingTop: 30,
            borderTop: "1px solid rgba(255,255,255,0.1)",
          }}
        >
          <div
            style={{
              display: "flex",
              alignItems: "center",
              justifyContent: "space-between",
              fontSize: 22,
              fontWeight: 750,
            }}
          >
            <span>Feedback Volume</span>
            <span style={{color: "rgba(248,248,246,0.5)"}}>{Math.round(slider * 100)}%</span>
          </div>
          <div
            style={{
              position: "relative",
              height: 7,
              marginTop: 26,
              borderRadius: 8,
              backgroundColor: "rgba(255,255,255,0.13)",
            }}
          >
            <div
              style={{
                width: `${slider * 100}%`,
                height: "100%",
                borderRadius: 8,
                background: `linear-gradient(90deg, ${colors.cyan}, ${colors.pink})`,
              }}
            />
            <div
              style={{
                position: "absolute",
                left: `calc(${slider * 100}% - 16px)`,
                top: -12,
                width: 32,
                height: 32,
                borderRadius: "50%",
                backgroundColor: colors.white,
                boxShadow: "0 8px 20px rgba(0,0,0,0.4)",
              }}
            />
          </div>
        </div>
        <div
          style={{
            marginTop: 52,
            display: "flex",
            alignItems: "center",
            justifyContent: "space-between",
          }}
        >
          <div style={{fontSize: 22, fontWeight: 750}}>Accent</div>
          <div style={{display: "flex", gap: 13}}>
            {[colors.pink, colors.cyan, colors.green, colors.amber].map((color, index) => (
              <span
                key={color}
                style={{
                  width: 44,
                  height: 44,
                  borderRadius: "50%",
                  backgroundColor: color,
                  border:
                    shot === 2 && index === 1
                      ? "5px solid rgba(255,255,255,0.88)"
                      : "3px solid rgba(255,255,255,0.1)",
                }}
              />
            ))}
          </div>
        </div>
      </div>
      <div
        style={{
          position: "absolute",
          left: 760,
          top: cursorY,
          width: 42,
          height: 42,
          borderRadius: "50%",
          backgroundColor: "rgba(248,248,246,0.92)",
          border: "7px solid rgba(116,221,227,0.2)",
          boxShadow: `0 0 ${24 + tap * 34}px rgba(116,221,227,${0.3 + tap * 0.35})`,
          transform: `scale(${1 - tap * 0.18})`,
        }}
      />
    </AbsoluteFill>
  );
};

const montagePhrases = [
  "meet me at 8?",
  "that sounds perfect",
  "one more thought",
  "this feels so good",
  "tiny crack, tiny calm",
  "sent",
];

const MontageBeat: React.FC<{
  frame: number;
  index: number;
  start: number;
  end: number;
}> = ({frame, index, start, end}) => {
  const local = frame - start;
  const themeOrder = [themes[0], themes[1], themes[3], themes[4], themes[2], themes[6]];
  const theme = themeOrder[index];
  const opacity = sceneOpacity(frame, start, end, 3);
  const typed = montagePhrases[index].slice(
    0,
    Math.floor(interpolate(local, [1, 16], [0, montagePhrases[index].length], clamp)),
  );
  const bubbleSide = index % 2 === 0 ? "flex-start" : "flex-end";

  return (
    <AbsoluteFill
      style={{
        opacity,
        overflow: "hidden",
        color: colors.white,
        background: `linear-gradient(${145 + index * 8}deg, ${theme.deck}, ${colors.ink} 68%)`,
      }}
    >
      <div
        style={{
          position: "absolute",
          left: 72,
          right: 72,
          top: 100,
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
        }}
      >
        <span style={{fontSize: 21, fontWeight: 800, color: "rgba(248,248,246,0.56)"}}>
          Messages
        </span>
        <span style={{fontSize: 20, fontWeight: 800, color: theme.accent}}>
          {theme.name}
        </span>
      </div>
      <div
        style={{
          position: "absolute",
          left: 74,
          right: 74,
          top: 260,
          height: 460,
          display: "flex",
          flexDirection: "column",
          alignItems: bubbleSide,
          justifyContent: "center",
        }}
      >
        <div
          style={{
            maxWidth: 780,
            minWidth: 360,
            minHeight: 120,
            padding: "30px 38px",
            borderRadius: 42,
            color: index % 2 === 0 ? colors.ink : colors.white,
            backgroundColor:
              index % 2 === 0 ? theme.accent : "rgba(248,248,246,0.11)",
            border: "1px solid rgba(255,255,255,0.13)",
            boxShadow: `0 28px 70px ${theme.glow}`,
            fontSize: 43,
            lineHeight: 1.2,
            fontWeight: 720,
          }}
        >
          {typed}
          <span style={{opacity: local % 10 < 6 ? 1 : 0}}>|</span>
        </div>
      </div>
      <div
        style={{
          position: "absolute",
          left: 76,
          top: 840,
          transform: `scale(1.02) translateY(${Math.sin(local * 0.1) * 5}px)`,
        }}
      >
        <Keyboard frame={frame} localFrame={local} theme={theme} scale={1} tilt={10} />
      </div>
      <div
        style={{
          position: "absolute",
          left: 0,
          right: 0,
          bottom: 86,
          display: "flex",
          justifyContent: "center",
        }}
      >
        <Waveform frame={frame} accent={theme.accent} width={260} />
      </div>
    </AbsoluteFill>
  );
};

const TypingMontage: React.FC<{frame: number}> = ({frame}) => {
  const start = 468;
  const length = 24;
  return (
    <>
      {montagePhrases.map((phrase, index) => (
        <MontageBeat
          key={phrase}
          frame={frame}
          index={index}
          start={start + index * length}
          end={start + (index + 1) * length + 2}
        />
      ))}
    </>
  );
};

const StoreButton: React.FC<{frame: number; hits?: number[]}> = ({frame, hits}) => {
  const pulse = pulseForTimes(frame, hits ?? [22.28, 22.94], 6);
  return (
    <div
      style={{
        width: 750,
        height: 128,
        borderRadius: 30,
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        gap: 20,
        color: colors.ink,
        backgroundColor: colors.white,
        border: "1px solid rgba(255,255,255,0.7)",
        boxShadow: `0 28px 80px rgba(0,0,0,0.42), 0 0 ${pulse * 34}px rgba(255,182,193,0.3)`,
        transform: `scale(${1 + pulse * 0.012})`,
      }}
    >
      <AppIcon size={68} style={{borderRadius: 16, boxShadow: "none"}} />
      <div>
        <div style={{fontSize: 18, fontWeight: 700}}>Download on the</div>
        <div style={{marginTop: 2, fontSize: 37, fontWeight: 880}}>
          Mac App Store
        </div>
      </div>
    </div>
  );
};

const EndingScene: React.FC<{frame: number}> = ({frame}) => {
  const start = 606;
  const local = frame - start;
  const opacity = sceneOpacity(frame, start, 720, 5);
  const finalPulse = pulseForTimes(frame, [20.48], 7);
  const icon = spring({
    frame: local - 18,
    fps: FPS,
    config: {damping: 17, mass: 0.75, stiffness: 105},
  });
  const tagline = easeIn(frame, start + 38, 16);
  const store = spring({
    frame: local - 62,
    fps: FPS,
    config: {damping: 18, mass: 0.8, stiffness: 105},
  });
  const fade = interpolate(frame, [704, 719], [0, 1], {
    ...clamp,
    easing: Easing.in(Easing.cubic),
  });

  return (
    <AbsoluteFill
      style={{
        opacity,
        overflow: "hidden",
        alignItems: "center",
        justifyContent: "center",
        color: colors.white,
        background:
          "radial-gradient(circle at 50% 43%, rgba(255,182,193,0.12), transparent 34%), #070809",
      }}
    >
      <div
        style={{
          position: "absolute",
          top: 280,
          width: 3,
          height: interpolate(finalPulse, [0, 1], [0, 170], clamp),
          borderRadius: 8,
          backgroundColor: colors.pink,
          opacity: finalPulse * 0.65,
          boxShadow: "0 0 30px rgba(255,182,193,0.48)",
        }}
      />
      <div
        style={{
          transform: `translateY(-250px) scale(${0.8 + icon * 0.2})`,
          opacity: icon,
        }}
      >
        <AppIcon size={142} />
      </div>
      <div
        style={{
          position: "absolute",
          top: 730,
          width: 900,
          textAlign: "center",
          opacity: tagline,
          transform: `translateY(${(1 - tagline) * 22}px)`,
        }}
      >
        <div style={{fontSize: 82, lineHeight: 1, fontWeight: 880}}>
          Type. Hear. Relax.
        </div>
        <div
          style={{
            width: 690,
            margin: "28px auto 0",
            color: "rgba(248,248,246,0.52)",
            fontSize: 27,
            lineHeight: 1.3,
            fontWeight: 620,
          }}
        >
          Satisfying keyboard sounds, everywhere you type on your Mac.
        </div>
      </div>
      <div
        style={{
          position: "absolute",
          top: 1110,
          opacity: store,
          transform: `translateY(${(1 - store) * 42}px) scale(${0.96 + store * 0.04})`,
        }}
      >
        <StoreButton frame={frame} />
      </div>
      <div
        style={{
          position: "absolute",
          bottom: 210,
          display: "flex",
          alignItems: "center",
          gap: 15,
          color: "rgba(248,248,246,0.46)",
          fontSize: 20,
          fontWeight: 720,
        }}
      >
        <span
          style={{
            width: 9,
            height: 9,
            borderRadius: "50%",
            backgroundColor: colors.pink,
          }}
        />
        Tappy for macOS
      </div>
      <AbsoluteFill style={{backgroundColor: "#000", opacity: fade}} />
    </AbsoluteFill>
  );
};

const TappyImmersive24: React.FC = () => {
  const frame = useCurrentFrame();

  return (
    <AbsoluteFill
      style={{
        overflow: "hidden",
        color: colors.white,
        backgroundColor: colors.ink,
        fontFamily,
      }}
    >
      <Audio src={staticFile("tappy-immersive-24s.wav")} volume={1} />
      <IntroScene frame={frame} />
      <HumanTypingScene frame={frame} />
      <SoundWorlds frame={frame} />
      <MacroSequence frame={frame} />
      <CustomizationScene frame={frame} />
      <TypingMontage frame={frame} />
      <EndingScene frame={frame} />
    </AbsoluteFill>
  );
};

const V2_DURATION_IN_FRAMES = 16 * FPS;

type JourneyTheme = {
  theme: Theme;
  start: number;
  end: number;
  hits: number[];
  messages: [string, string, string];
  burstStarts: [number, number, number];
};

const v2BubbleHits = [
  1.15, 1.25, 1.35, 1.45, 1.55, 1.65, 1.75, 1.95, 2.045, 2.14,
  2.235, 2.33, 2.425, 2.52, 2.615, 2.85, 2.955, 3.06, 3.165, 3.27,
  3.375, 3.48,
];

const v2WetHits = [
  3.9, 4.005, 4.11, 4.215, 4.32, 4.425, 4.53, 4.72, 4.82, 4.92,
  5.02, 5.12, 5.22, 5.32, 5.55, 5.655, 5.76, 5.865, 5.97, 6.075,
  6.18,
];

const v2WaxHits = [
  6.65, 6.755, 6.86, 6.965, 7.07, 7.175, 7.28, 7.47, 7.57, 7.67,
  7.77, 7.87, 7.97, 8.07, 8.3, 8.405, 8.51, 8.615, 8.72, 8.825,
  8.93,
];

const v2MechanicalHits = [
  9.4, 9.495, 9.59, 9.685, 9.78, 9.875, 9.97, 10.065, 10.22, 10.315,
  10.41, 10.505, 10.6, 10.695, 10.79, 10.885, 11.04, 11.14, 11.24,
  11.34, 11.44, 11.54, 11.64,
];

const v2Journeys: JourneyTheme[] = [
  {
    theme: themes[0],
    start: 29,
    end: 114,
    hits: v2BubbleHits,
    messages: ["hey, are you free?", "meet me at 8", "perfect"],
    burstStarts: [5, 29, 56],
  },
  {
    theme: themes[1],
    start: 110,
    end: 199,
    hits: v2WetHits,
    messages: ["one more little pop", "that feels nice", "keep going"],
    burstStarts: [7, 32, 57],
  },
  {
    theme: themes[2],
    start: 195,
    end: 284,
    hits: v2WaxHits,
    messages: ["listen to that crack", "so satisfying", "again"],
    burstStarts: [5, 29, 54],
  },
  {
    theme: themes[4],
    start: 280,
    end: 358,
    hits: v2MechanicalHits,
    messages: ["okay, almost done", "one last thought", "sent"],
    burstStarts: [2, 27, 52],
  },
];

const V2MessageStream: React.FC<{
  localFrame: number;
  journey: JourneyTheme;
}> = ({localFrame, journey}) => (
  <div
    style={{
      width: 900,
      minHeight: 350,
      display: "flex",
      flexDirection: "column",
      justifyContent: "center",
      gap: 18,
    }}
  >
    {journey.messages.map((message, index) => {
      const burstStart = journey.burstStarts[index];
      const progress = interpolate(
        localFrame,
        [burstStart, burstStart + 17],
        [0, message.length],
        clamp,
      );
      const visible = localFrame >= burstStart;
      const complete = localFrame >= burstStart + 17;
      const text = message.slice(0, Math.floor(progress));
      const right = index % 2 === 1;
      return (
        <div
          key={message}
          style={{
            alignSelf: right ? "flex-end" : "flex-start",
            minWidth: 250,
            maxWidth: 760,
            minHeight: 84,
            padding: "22px 30px",
            borderRadius: 32,
            display: visible ? "flex" : "none",
            alignItems: "center",
            color: right ? colors.white : colors.ink,
            backgroundColor: right
              ? "rgba(248,248,246,0.1)"
              : journey.theme.accent,
            border: "1px solid rgba(255,255,255,0.12)",
            boxShadow: `0 18px 55px ${journey.theme.glow}`,
            opacity: complete && index < 2 ? 0.62 : 1,
            fontSize: 34,
            lineHeight: 1.15,
            fontWeight: 730,
          }}
        >
          {text}
          {!complete ? (
            <span
              style={{
                marginLeft: 3,
                color: right ? journey.theme.accent : colors.ink,
                opacity: localFrame % 10 < 6 ? 1 : 0,
              }}
            >
              |
            </span>
          ) : null}
        </div>
      );
    })}
  </div>
);

const V2ThemeScene: React.FC<{
  frame: number;
  journey: JourneyTheme;
  index: number;
}> = ({frame, journey, index}) => {
  const local = frame - journey.start;
  const duration = journey.end - journey.start;
  const opacity = sceneOpacity(frame, journey.start, journey.end, 6);
  const enter = easeIn(frame, journey.start, 12);
  const pulse = pulseForTimes(frame, journey.hits, 4);
  const drift = interpolate(local, [0, duration], [-12, 14], clamp);

  return (
    <AbsoluteFill
      style={{
        opacity,
        overflow: "hidden",
        color: colors.white,
        background: `radial-gradient(circle at 50% 42%, ${journey.theme.glow}, transparent 48%), linear-gradient(155deg, ${journey.theme.deck}, ${colors.ink} 74%)`,
      }}
    >
      <SoundTransition
        frame={frame}
        start={journey.start}
        color={journey.theme.accent}
        direction={index % 2 === 0 ? 1 : -1}
      />
      <div
        style={{
          position: "absolute",
          left: 68,
          right: 68,
          top: 96,
          display: "flex",
          alignItems: "flex-start",
          justifyContent: "space-between",
          opacity: enter,
          transform: `translateY(${(1 - enter) * 18}px)`,
        }}
      >
        <div>
          <div
            style={{
              color: journey.theme.accent,
              fontSize: 19,
              fontWeight: 850,
              textTransform: "uppercase",
            }}
          >
            Sound {index + 1 < 10 ? `0${index + 1}` : index + 1}
          </div>
          <div
            style={{
              width: 790,
              marginTop: 13,
              fontSize: journey.theme.name.length > 20 ? 50 : 62,
              lineHeight: 1,
              fontWeight: 860,
            }}
          >
            {journey.theme.name}
          </div>
          <div
            style={{
              marginTop: 15,
              color: "rgba(248,248,246,0.52)",
              fontSize: 22,
              fontWeight: 650,
            }}
          >
            {journey.theme.micro}
          </div>
        </div>
        <div
          style={{
            width: 52,
            height: 52,
            marginTop: 4,
            borderRadius: 18,
            backgroundColor: journey.theme.accent,
            boxShadow: `0 0 ${26 + pulse * 24}px ${journey.theme.glow}`,
            transform: `scale(${1 + pulse * 0.09})`,
          }}
        />
      </div>
      <div
        style={{
          position: "absolute",
          left: 90,
          right: 90,
          top: 300,
          transform: `translateY(${Math.sin(local * 0.035) * 5}px)`,
        }}
      >
        <V2MessageStream localFrame={local} journey={journey} />
      </div>
      <div
        style={{
          position: "absolute",
          left: 74,
          top: 850,
          transform: `translateY(${drift}px) scale(${0.985 + enter * 0.015})`,
        }}
      >
        <Keyboard
          frame={frame}
          localFrame={local}
          theme={journey.theme}
          scale={1}
          tilt={9 + index * 1.2}
          hits={journey.hits}
        />
      </div>
      <div
        style={{
          position: "absolute",
          left: 0,
          right: 0,
          bottom: 112,
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          gap: 12,
        }}
      >
        <div
          style={{
            color: "rgba(248,248,246,0.42)",
            fontSize: 18,
            fontWeight: 750,
          }}
        >
          typing in real time
        </div>
        <Waveform
          frame={frame}
          accent={journey.theme.accent}
          width={300}
          hits={journey.hits}
        />
      </div>
    </AbsoluteFill>
  );
};

const V2Ending: React.FC<{frame: number}> = ({frame}) => {
  const start = 354;
  const local = frame - start;
  const opacity = sceneOpacity(frame, start, V2_DURATION_IN_FRAMES, 5);
  const endHits = [11.8, 13.72, 14.62];
  const finalPulse = pulseForTimes(frame, endHits, 7);
  const icon = spring({
    frame: local - 10,
    fps: FPS,
    config: {damping: 17, mass: 0.75, stiffness: 108},
  });
  const tagline = easeIn(frame, start + 28, 16);
  const store = spring({
    frame: local - 64,
    fps: FPS,
    config: {damping: 18, mass: 0.78, stiffness: 104},
  });
  const fade = interpolate(frame, [468, 479], [0, 1], {
    ...clamp,
    easing: Easing.in(Easing.cubic),
  });

  return (
    <AbsoluteFill
      style={{
        opacity,
        overflow: "hidden",
        alignItems: "center",
        justifyContent: "center",
        color: colors.white,
        background:
          "radial-gradient(circle at 50% 43%, rgba(255,182,193,0.12), transparent 34%), #070809",
      }}
    >
      <div
        style={{
          position: "absolute",
          top: 300,
          width: 3,
          height: finalPulse * 135,
          borderRadius: 8,
          backgroundColor: colors.pink,
          opacity: finalPulse * 0.62,
          boxShadow: "0 0 30px rgba(255,182,193,0.45)",
        }}
      />
      <div
        style={{
          transform: `translateY(-245px) scale(${0.82 + icon * 0.18})`,
          opacity: icon,
        }}
      >
        <AppIcon size={142} />
      </div>
      <div
        style={{
          position: "absolute",
          top: 730,
          width: 900,
          textAlign: "center",
          opacity: tagline,
          transform: `translateY(${(1 - tagline) * 20}px)`,
        }}
      >
        <div style={{fontSize: 82, lineHeight: 1, fontWeight: 880}}>
          Type. Hear. Relax.
        </div>
        <div
          style={{
            width: 690,
            margin: "28px auto 0",
            color: "rgba(248,248,246,0.52)",
            fontSize: 27,
            lineHeight: 1.3,
            fontWeight: 620,
          }}
        >
          Satisfying keyboard sounds, everywhere you type on your Mac.
        </div>
      </div>
      <div
        style={{
          position: "absolute",
          top: 1110,
          opacity: store,
          transform: `translateY(${(1 - store) * 38}px) scale(${0.96 + store * 0.04})`,
        }}
      >
        <StoreButton frame={frame} hits={endHits.slice(1)} />
      </div>
      <div
        style={{
          position: "absolute",
          bottom: 210,
          display: "flex",
          alignItems: "center",
          gap: 15,
          color: "rgba(248,248,246,0.46)",
          fontSize: 20,
          fontWeight: 720,
        }}
      >
        <span
          style={{
            width: 9,
            height: 9,
            borderRadius: "50%",
            backgroundColor: colors.pink,
          }}
        />
        Tappy for macOS
      </div>
      <AbsoluteFill style={{backgroundColor: "#000", opacity: fade}} />
    </AbsoluteFill>
  );
};

const TappyImmersiveV2: React.FC = () => {
  const frame = useCurrentFrame();

  return (
    <AbsoluteFill
      style={{
        overflow: "hidden",
        color: colors.white,
        backgroundColor: colors.ink,
        fontFamily,
      }}
    >
      <Audio src={staticFile("tappy-immersive-v2.wav")} volume={1} />
      <IntroScene frame={frame} />
      {v2Journeys.map((journey, index) => (
        <V2ThemeScene
          key={journey.theme.id}
          frame={frame}
          journey={journey}
          index={index}
        />
      ))}
      <V2Ending frame={frame} />
    </AbsoluteFill>
  );
};

const V3_DURATION_IN_FRAMES = 17 * FPS;
const v3IntroHits = [0.34, 0.75, 1.48, 1.62, 1.76, 1.9, 2.05];
const shiftV3Hits = (hits: number[]) => hits.map((time) => time + 1.2);

const v3Journeys: JourneyTheme[] = [
  {
    theme: themes[1],
    start: 62,
    end: 146,
    hits: shiftV3Hits(v2BubbleHits),
    messages: ["one more little pop", "that feels nice", "keep going"],
    burstStarts: [8, 32, 59],
  },
  {
    theme: themes[2],
    start: 142,
    end: 231,
    hits: shiftV3Hits(v2WetHits),
    messages: ["listen to that crack", "so satisfying", "again"],
    burstStarts: [11, 36, 61],
  },
  {
    theme: themes[6],
    start: 227,
    end: 316,
    hits: shiftV3Hits(v2WaxHits),
    messages: ["hey, are you free?", "meet me at 8", "perfect"],
    burstStarts: [8, 32, 57],
  },
  {
    theme: themes[0],
    start: 312,
    end: 392,
    hits: shiftV3Hits(v2MechanicalHits),
    messages: ["okay, almost done", "one last thought", "sent"],
    burstStarts: [6, 31, 56],
  },
];

const woodBrushTheme: Theme = {
  id: "wood-brush",
  name: "Wood Brush",
  micro: "textured / warm / soft",
  accent: "#D7A06E",
  accentTwo: "#E9C8A8",
  deck: "#271B15",
  keyTop: "#79533A",
  keySide: "#493124",
  glow: "rgba(215,160,110,0.34)",
};

const v3LibraryThemes = [
  themes[3],
  themes[4],
  themes[5],
  woodBrushTheme,
];
const v3LibraryHits = [13.13, 13.4, 13.67, 13.94];
const V3_LIBRARY_START = 393;
const V3_LIBRARY_SLOT = 8;

const V3OpeningSequence: React.FC<{frame: number}> = ({frame}) => {
  const journey = v3Journeys[0];
  const opacity = sceneOpacity(frame, 0, journey.end, 6);
  const logo = spring({
    frame: frame - 8,
    fps: FPS,
    config: {damping: 17, mass: 0.72, stiffness: 112},
  });
  const copyIn = easeIn(frame, 16, 15);
  const transition = interpolate(frame, [42, 68], [0, 1], {
    ...clamp,
    easing: Easing.inOut(Easing.cubic),
  });
  const demoReveal = interpolate(frame, [52, 70], [0, 1], {
    ...clamp,
    easing: Easing.out(Easing.cubic),
  });
  const titleFade = interpolate(transition, [0.62, 1], [1, 0], clamp);
  const keyboardProgress = interpolate(frame, [40, 68], [0, 1], {
    ...clamp,
    easing: Easing.inOut(Easing.cubic),
  });
  const cameraDrift = interpolate(
    frame,
    [70, journey.end],
    [0, 12],
    clamp,
  );
  const openingHits = [...v3IntroHits, ...journey.hits];
  const localFrame = frame - journey.start;
  const pulse = pulseForTimes(frame, openingHits, 5);
  const motionBlur = Math.sin(transition * Math.PI) * 2.4;

  return (
    <AbsoluteFill
      style={{
        opacity,
        overflow: "hidden",
        color: colors.white,
        backgroundColor: "#050607",
      }}
    >
      <AbsoluteFill
        style={{
          opacity: transition,
          background: `radial-gradient(circle at 50% 42%, ${journey.theme.glow}, transparent 48%), linear-gradient(155deg, ${journey.theme.deck}, ${colors.ink} 74%)`,
        }}
      />
      <div
        style={{
          position: "absolute",
          left: interpolate(transition, [0, 1], [477, 960], clamp),
          top: interpolate(transition, [0, 1], [570, 100], clamp),
          opacity: logo * interpolate(transition, [0.75, 1], [1, 0], clamp),
          filter: `blur(${motionBlur}px)`,
          transform: `scale(${0.82 + logo * 0.18 - transition * 0.58 + pulse * 0.018})`,
          transformOrigin: "top left",
        }}
      >
        <AppIcon size={126} />
      </div>
      <div
        style={{
          position: "absolute",
          left: 80,
          top: 760,
          width: 920,
          textAlign: "center",
          opacity: copyIn * titleFade,
          filter: `blur(${(1 - copyIn) * 9 + motionBlur}px)`,
          transform: `translateY(${(1 - copyIn) * 22 - transition * 590}px) scale(${1 - transition * 0.44})`,
          transformOrigin: "center",
        }}
      >
        <div style={{fontSize: 66, lineHeight: 1.06, fontWeight: 860}}>
          Turn every tap into ASMR.
        </div>
      </div>
      <div
        style={{
          position: "absolute",
          left: 68,
          right: 68,
          top: 96,
          display: "flex",
          alignItems: "flex-start",
          justifyContent: "space-between",
          opacity: demoReveal,
          filter: `blur(${(1 - demoReveal) * 4}px)`,
          transform: `translateY(${(1 - demoReveal) * 16}px)`,
        }}
      >
        <div>
          <div
            style={{
              color: journey.theme.accent,
              fontSize: 19,
              fontWeight: 850,
              textTransform: "uppercase",
            }}
          >
            Sound 01
          </div>
          <div
            style={{
              width: 790,
              marginTop: 13,
              fontSize: 50,
              lineHeight: 1,
              fontWeight: 860,
            }}
          >
            {journey.theme.name}
          </div>
          <div
            style={{
              marginTop: 15,
              color: "rgba(248,248,246,0.52)",
              fontSize: 22,
              fontWeight: 650,
            }}
          >
            {journey.theme.micro}
          </div>
        </div>
        <div
          style={{
            width: 52,
            height: 52,
            marginTop: 4,
            borderRadius: 18,
            backgroundColor: journey.theme.accent,
            boxShadow: `0 0 ${26 + pulse * 24}px ${journey.theme.glow}`,
            transform: `scale(${1 + pulse * 0.09})`,
          }}
        />
      </div>
      <div
        style={{
          position: "absolute",
          left: 90,
          right: 90,
          top: 300,
          opacity: demoReveal,
          transform: `translateY(${Math.sin(Math.max(0, localFrame) * 0.035) * 5}px)`,
        }}
      >
        <V2MessageStream localFrame={localFrame} journey={journey} />
      </div>
      <div
        style={{
          position: "absolute",
          left: 74,
          top: 850,
          opacity: interpolate(frame, [39, 50], [0, 1], clamp),
          filter: `blur(${(1 - keyboardProgress) * 7 + motionBlur * 0.55}px)`,
          transform: `translateY(${(1 - keyboardProgress) * 230 + cameraDrift}px) scale(${0.2 + keyboardProgress * 0.8})`,
          transformOrigin: "center 42%",
        }}
      >
        <Keyboard
          frame={frame}
          localFrame={Math.max(0, frame - 40)}
          theme={journey.theme}
          scale={1}
          tilt={10}
          hits={openingHits}
        />
      </div>
      <div
        style={{
          position: "absolute",
          left: 0,
          right: 0,
          bottom: 110,
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          gap: 12,
          opacity: interpolate(frame, [55, 70], [0, 1], clamp),
        }}
      >
        <div
          style={{
            color: "rgba(248,248,246,0.42)",
            fontSize: 18,
            fontWeight: 750,
          }}
        >
          typing in real time
        </div>
        <Waveform
          frame={frame}
          accent={journey.theme.accent}
          width={300}
          hits={openingHits}
        />
      </div>
    </AbsoluteFill>
  );
};

const V3LibraryGlimpse: React.FC<{
  frame: number;
  theme: Theme;
  index: number;
}> = ({frame, theme, index}) => {
  const start = V3_LIBRARY_START + index * V3_LIBRARY_SLOT;
  const local = frame - start;
  const reveal = interpolate(local, [-2, 1, 6, 10], [0, 1, 1, 0], {
    ...clamp,
    easing: Easing.inOut(Easing.cubic),
  });
  const travel = interpolate(local, [-2, 10], [-42, 36], clamp);
  const direction = index % 2 === 0 ? 1 : -1;
  const edgeBlur =
    interpolate(local, [-2, 1], [8, 0], clamp) +
    interpolate(local, [6, 10], [0, 8], clamp);

  return (
    <AbsoluteFill
      style={{
        opacity: reveal,
        overflow: "hidden",
        background: `linear-gradient(150deg, ${theme.deck}, ${colors.ink} 72%)`,
        filter: `blur(${edgeBlur}px)`,
        transform: `scale(1.035) translateX(${travel * direction}px)`,
      }}
    >
      <AbsoluteFill
        style={{
          background: `linear-gradient(118deg, transparent 16%, ${theme.glow} 52%, transparent 82%)`,
          opacity: 0.9,
        }}
      />
      <div
        style={{
          position: "absolute",
          left: 72,
          top: 112,
        }}
      >
        <div
          style={{
            color: theme.accent,
            fontSize: 18,
            fontWeight: 850,
            textTransform: "uppercase",
          }}
        >
          More inside Tappy
        </div>
        <div
          style={{
            width: 850,
            marginTop: 14,
            fontSize: theme.name.length > 18 ? 54 : 64,
            lineHeight: 1,
            fontWeight: 870,
          }}
        >
          {theme.name}
        </div>
      </div>
      <div
        style={{
          position: "absolute",
          left: 30,
          top: 620,
          transform: `scale(1.18) rotateZ(${direction * 1.2}deg)`,
          transformOrigin: "center",
        }}
      >
        <Keyboard
          frame={frame}
          localFrame={Math.max(0, local)}
          theme={theme}
          scale={1}
          tilt={12 + index}
          hits={[v3LibraryHits[index]]}
        />
      </div>
    </AbsoluteFill>
  );
};

const V3LibraryCard: React.FC<{
  theme: Theme;
  index: number;
  frame: number;
}> = ({theme, index, frame}) => {
  const fanIn = interpolate(frame, [425 + index, 432 + index], [0, 1], {
    ...clamp,
    easing: Easing.out(Easing.cubic),
  });
  const collapse = interpolate(frame, [433, 455], [0, 1], {
    ...clamp,
    easing: Easing.inOut(Easing.cubic),
  });
  const offset = index - (v3LibraryThemes.length - 1) / 2;
  const x = offset * 202 * (1 - collapse);
  const y = Math.abs(offset) * 24 * (1 - collapse);
  const rotation = offset * 7.5 * (1 - collapse);
  const opacity = fanIn * interpolate(collapse, [0.58, 1], [1, 0], clamp);

  return (
    <div
      style={{
        position: "absolute",
        left: "50%",
        top: 560,
        width: 218,
        height: 286,
        marginLeft: -109,
        borderRadius: 34,
        padding: "30px 24px",
        overflow: "hidden",
        opacity,
        background: `linear-gradient(155deg, ${theme.keyTop}, ${theme.deck})`,
        border: `1px solid ${theme.accent}66`,
        boxShadow: `0 28px 70px rgba(0,0,0,0.42), 0 0 34px ${theme.glow}`,
        filter: `blur(${collapse * 8}px)`,
        transform: `translateX(${x}px) translateY(${(1 - fanIn) * 90 + y - collapse * 28}px) rotate(${rotation}deg) scale(${0.84 + fanIn * 0.16 - collapse * 0.36})`,
      }}
    >
      <div
        style={{
          color: theme.accent,
          fontSize: 16,
          fontWeight: 820,
          whiteSpace: "nowrap",
        }}
      >
        {theme.name}
      </div>
      <div
        style={{
          display: "grid",
          gridTemplateColumns: "repeat(3, 1fr)",
          gap: 10,
          marginTop: 32,
        }}
      >
        {Array.from({length: 9}).map((_, keyIndex) => (
          <div
            key={keyIndex}
            style={{
              height: 42,
              borderRadius: theme.id === "bubble" ? 15 : 10,
              backgroundColor:
                keyIndex === (index * 2 + 1) % 9
                  ? theme.accent
                  : theme.keySide,
              border: "1px solid rgba(255,255,255,0.09)",
              boxShadow: `0 5px 0 ${theme.deck}`,
            }}
          />
        ))}
      </div>
    </div>
  );
};

const V3Ending: React.FC<{frame: number}> = ({frame}) => {
  const start = 388;
  const opacity = sceneOpacity(frame, start, V3_DURATION_IN_FRAMES, 5);
  const endHits = [...v3LibraryHits, 15.9];
  const finalPulse = pulseForTimes(frame, endHits, 7);
  const icon = spring({
    frame: frame - 442,
    fps: FPS,
    config: {damping: 18, mass: 0.72, stiffness: 106},
  });
  const wordmark = spring({
    frame: frame - 452,
    fps: FPS,
    config: {damping: 19, mass: 0.76, stiffness: 100},
  });
  const discovery = easeIn(frame, 460, 17);
  const settle = interpolate(frame, [433, 457], [0, 1], {
    ...clamp,
    easing: Easing.inOut(Easing.cubic),
  });
  const fade = interpolate(frame, [497, 509], [0, 1], {
    ...clamp,
    easing: Easing.in(Easing.cubic),
  });

  return (
    <AbsoluteFill
      style={{
        opacity,
        overflow: "hidden",
        alignItems: "center",
        justifyContent: "center",
        color: colors.white,
        background:
          "linear-gradient(160deg, rgba(255,182,193,0.055), transparent 44%), #070809",
      }}
    >
      {v3LibraryThemes.map((theme, index) => (
        <V3LibraryGlimpse
          key={theme.id}
          frame={frame}
          theme={theme}
          index={index}
        />
      ))}
      {v3LibraryThemes.map((theme, index) => (
        <V3LibraryCard
          key={`card-${theme.id}`}
          frame={frame}
          theme={theme}
          index={index}
        />
      ))}
      <div
        style={{
          position: "absolute",
          left: "50%",
          top: 492,
          width: 220,
          height: 220,
          marginLeft: -110,
          borderRadius: 58,
          border: `2px solid ${colors.pink}`,
          opacity: finalPulse * settle * 0.42,
          boxShadow: "0 0 38px rgba(255,182,193,0.25)",
          transform: `scale(${0.72 + finalPulse * 0.44})`,
        }}
      />
      <div
        style={{
          position: "absolute",
          top: 532,
          left: 0,
          right: 0,
          display: "flex",
          justifyContent: "center",
          opacity: icon * settle,
          filter: `blur(${(1 - Math.min(1, icon)) * 7}px)`,
          transform: `translateY(${(1 - icon) * 22}px) scale(${0.78 + icon * 0.22})`,
        }}
      >
        <AppIcon size={154} />
      </div>
      <div
        style={{
          position: "absolute",
          top: 742,
          width: 900,
          textAlign: "center",
          opacity: wordmark,
          filter: `blur(${(1 - Math.min(1, wordmark)) * 5}px)`,
          transform: `translateY(${(1 - wordmark) * 18}px)`,
        }}
      >
        <div style={{fontSize: 80, lineHeight: 1, fontWeight: 880}}>
          Tappy
        </div>
      </div>
      <div
        style={{
          position: "absolute",
          top: 880,
          width: 930,
          textAlign: "center",
          opacity: discovery,
          filter: `blur(${(1 - discovery) * 7}px)`,
          transform: `translateY(${(1 - discovery) * 22}px)`,
        }}
      >
        <div style={{fontSize: 54, lineHeight: 1.08, fontWeight: 760}}>
          Discover 100+ ASMR Sounds
        </div>
      </div>
      <AbsoluteFill style={{backgroundColor: "#000", opacity: fade}} />
    </AbsoluteFill>
  );
};

const TappyImmersiveV3: React.FC = () => {
  const frame = useCurrentFrame();

  return (
    <AbsoluteFill
      style={{
        overflow: "hidden",
        color: colors.white,
        backgroundColor: colors.ink,
        fontFamily,
      }}
    >
      <Audio src={staticFile("tappy-immersive-v3.wav")} volume={1} />
      <V3OpeningSequence frame={frame} />
      {v3Journeys.slice(1).map((journey, index) => (
        <V2ThemeScene
          key={journey.theme.id}
          frame={frame}
          journey={journey}
          index={index + 1}
        />
      ))}
      <V3Ending frame={frame} />
    </AbsoluteFill>
  );
};

export const TappyImmersiveComposition: React.FC = () => (
  <>
    <Composition
      id="TappyImmersiveASMR24"
      component={TappyImmersive24}
      durationInFrames={DURATION_IN_FRAMES}
      fps={FPS}
      width={1080}
      height={1920}
    />
    <Composition
      id="TappyImmersiveASMRV2"
      component={TappyImmersiveV2}
      durationInFrames={V2_DURATION_IN_FRAMES}
      fps={FPS}
      width={1080}
      height={1920}
    />
    <Composition
      id="TappyImmersiveASMRV3"
      component={TappyImmersiveV3}
      durationInFrames={V3_DURATION_IN_FRAMES}
      fps={FPS}
      width={1080}
      height={1920}
    />
  </>
);
