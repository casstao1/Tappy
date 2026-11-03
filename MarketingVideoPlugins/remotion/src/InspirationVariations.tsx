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
const DURATION_IN_FRAMES = 15 * FPS;

const colors = {
  charcoal: "#171619",
  charcoalSoft: "#242126",
  ivory: "#F7F6F2",
  pink: "#FFB6C1",
  rose: "#D88998",
  lavender: "#C8B9FF",
  gray: "#6B676D",
  green: "#4ED77B",
};

const clamp = {
  extrapolateLeft: "clamp" as const,
  extrapolateRight: "clamp" as const,
};

const editorialHits = [
  0.8, 1.55, 2.35, 3.15, 3.7, 4.35, 5.05, 5.8, 6.72, 7.2, 8.0,
  8.85, 9.7, 11.82, 12.58, 13.32, 14.12,
];

const textureHits = [
  0.92, 1.92, 3.05, 4.15, 5.18, 6.08, 6.72, 7.18, 7.98, 8.78,
  9.58, 10.38, 11.18, 12.25, 13.05, 14.0,
];

const ritualHits = [
  0.8, 1.38, 1.98, 2.72, 3.32, 4.08, 5.0, 5.8, 6.62, 7.45, 8.2,
  9.0, 9.82, 10.62, 12.0, 12.8, 13.58, 14.3,
];

const sceneOpacity = (
  frame: number,
  start: number,
  end: number,
  fadeFrames = 12,
) =>
  Math.min(
    interpolate(frame, [start, start + fadeFrames], [0, 1], clamp),
    interpolate(frame, [end - fadeFrames, end], [1, 0], clamp),
  );

const enter = (frame: number, at: number, duration = 18) =>
  interpolate(frame, [at, at + duration], [0, 1], {
    ...clamp,
    easing: Easing.out(Easing.cubic),
  });

const pulseAt = (frame: number, hits: number[], width = 6) => {
  return Math.max(
    ...hits.map((hit) =>
      interpolate(Math.abs(frame - hit * FPS), [0, width], [1, 0], clamp),
    ),
  );
};

const frameToSeconds = (frame: number) => frame / FPS;

const fontFamily =
  "Inter, -apple-system, BlinkMacSystemFont, Helvetica Neue, sans-serif";

const AppIcon: React.FC<{size?: number; style?: React.CSSProperties}> = ({
  size = 120,
  style,
}) => (
  <Img
    src={staticFile("tappy-icon.png")}
    style={{
      width: size,
      height: size,
      borderRadius: size * 0.24,
      objectFit: "cover",
      filter: "drop-shadow(0 22px 28px rgba(0,0,0,0.28))",
      ...style,
    }}
  />
);

const WavePill: React.FC<{
  frame: number;
  hits: number[];
  label: string;
  accent: string;
  light?: boolean;
  width?: number;
}> = ({frame, hits, label, accent, light = false, width = 700}) => {
  const pulse = pulseAt(frame, hits, 8);
  return (
    <div
      style={{
        width,
        height: 142,
        borderRadius: 71,
        display: "flex",
        alignItems: "center",
        justifyContent: "space-between",
        padding: "0 46px",
        color: light ? colors.charcoal : colors.ivory,
        backgroundColor: light ? "rgba(247,246,242,0.94)" : colors.charcoal,
        boxShadow: light
          ? "0 22px 60px rgba(23,22,25,0.16)"
          : "0 26px 74px rgba(0,0,0,0.3)",
        transform: `scale(${1 + pulse * 0.018})`,
      }}
    >
      <span
        style={{
          fontSize: 23,
          fontWeight: 800,
          color: light ? colors.gray : "rgba(247,246,242,0.68)",
          minWidth: 180,
        }}
      >
        {label}
      </span>
      <div
        style={{
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          gap: 10,
          height: 74,
        }}
      >
        {Array.from({length: 13}).map((_, index) => {
          const rhythm =
            0.32 +
            Math.abs(Math.sin(index * 1.38 + frame * 0.055)) * 0.32 +
            pulse * (0.28 + (index % 5) * 0.08);
          return (
            <span
              key={index}
              style={{
                width: 9,
                height: 15 + rhythm * 54,
                borderRadius: 9,
                backgroundColor: accent,
              }}
            />
          );
        })}
      </div>
      <span
        style={{
          minWidth: 110,
          textAlign: "right",
          fontSize: 21,
          fontWeight: 800,
          color: light ? colors.gray : "rgba(247,246,242,0.5)",
          fontVariantNumeric: "tabular-nums",
        }}
      >
        {frameToSeconds(frame).toFixed(1)}s
      </span>
    </div>
  );
};

const StoreButton: React.FC<{dark?: boolean}> = ({dark = false}) => (
  <div
    style={{
      width: 790,
      minHeight: 132,
      borderRadius: 30,
      display: "flex",
      alignItems: "center",
      justifyContent: "center",
      gap: 20,
      color: dark ? colors.ivory : colors.charcoal,
      backgroundColor: dark ? colors.charcoal : colors.ivory,
      border: dark
        ? "2px solid rgba(247,246,242,0.18)"
        : "2px solid rgba(23,22,25,0.12)",
      boxShadow: "0 26px 64px rgba(0,0,0,0.22)",
    }}
  >
    <AppIcon size={70} style={{borderRadius: 17, filter: "none"}} />
    <div style={{display: "flex", flexDirection: "column"}}>
      <span style={{fontSize: 20, fontWeight: 700}}>Download on the</span>
      <span style={{fontSize: 40, fontWeight: 900, marginTop: 3}}>
        Mac App Store
      </span>
    </div>
  </div>
);

const Eyebrow: React.FC<{
  children: React.ReactNode;
  color?: string;
}> = ({children, color = colors.rose}) => (
  <div
    style={{
      color,
      fontSize: 22,
      fontWeight: 900,
      textTransform: "uppercase",
    }}
  >
    {children}
  </div>
);

const FinalBlack: React.FC = () => {
  const frame = useCurrentFrame();
  const opacity = interpolate(frame, [442, 449], [0, 1], {
    ...clamp,
    easing: Easing.in(Easing.cubic),
  });
  return <AbsoluteFill style={{backgroundColor: "#000", opacity}} />;
};

const AudioAccent: React.FC<{
  frame: number;
  hits: number[];
  colors: [string, string];
}> = ({frame, hits, colors: accentColors}) => {
  const pulse = pulseAt(frame, hits, 7);
  return (
    <div
      style={{
        position: "absolute",
        left: 250,
        right: 250,
        bottom: 52,
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        gap: 7,
        height: 18,
        opacity: 0.18 + pulse * 0.18,
      }}
    >
      {Array.from({length: 28}).map((_, index) => (
        <span
          key={index}
          style={{
            width: 10,
            height:
              2 +
              (0.15 + Math.abs(Math.sin(index * 0.9 + frame * 0.06))) *
                (5 + pulse * 9),
            borderRadius: 8,
            backgroundColor: index < 14 ? accentColors[0] : accentColors[1],
          }}
        />
      ))}
    </div>
  );
};

const EditorialVariation: React.FC = () => {
  const frame = useCurrentFrame();
  const introOpacity = sceneOpacity(frame, 0, 88, 14);
  const controlOpacity = sceneOpacity(frame, 72, 205, 16);
  const textureOpacity = sceneOpacity(frame, 188, 348, 16);
  const closeOpacity = sceneOpacity(frame, 332, 450, 16);
  const iconIn = enter(frame, 8, 22);
  const titleIn = enter(frame, 18, 24);
  const controlIn = enter(frame, 92, 22);
  const toggle = spring({
    frame: frame - 96,
    fps: FPS,
    config: {damping: 14, mass: 0.7, stiffness: 110},
  });
  const isWax = frame >= 236;
  const typed = "tiny sounds, wherever you type.".slice(
    0,
    Math.floor(interpolate(frame, [108, 181], [0, 31], clamp)),
  );

  return (
    <AbsoluteFill
      style={{
        backgroundColor: colors.ivory,
        color: colors.charcoal,
        fontFamily,
        overflow: "hidden",
      }}
    >
      <Audio src={staticFile("tappy-editorial.wav")} volume={1} />

      <AbsoluteFill
        style={{
          opacity: introOpacity,
          alignItems: "center",
          justifyContent: "center",
          textAlign: "center",
        }}
      >
        <div
          style={{
            transform: `translateY(${(1 - iconIn) * 28}px) scale(${0.9 + iconIn * 0.1})`,
            opacity: iconIn,
          }}
        >
          <AppIcon size={148} />
        </div>
        <div
          style={{
            width: 74,
            height: 4,
            marginTop: 46,
            borderRadius: 4,
            backgroundColor: colors.rose,
            transform: `scaleX(${titleIn})`,
          }}
        />
        <h1
          style={{
            width: 850,
            margin: "42px 0 0",
            fontSize: 92,
            lineHeight: 0.98,
            fontWeight: 900,
            opacity: titleIn,
            transform: `translateY(${(1 - titleIn) * 26}px)`,
          }}
        >
          Your Mac is quiet.
        </h1>
        <p
          style={{
            width: 760,
            margin: "30px 0 0",
            color: colors.gray,
            fontSize: 33,
            lineHeight: 1.24,
            fontWeight: 600,
            opacity: enter(frame, 34, 22),
          }}
        >
          That does not mean typing has to feel silent.
        </p>
      </AbsoluteFill>

      <AbsoluteFill
        style={{
          opacity: controlOpacity,
          alignItems: "center",
          paddingTop: 180,
          textAlign: "center",
        }}
      >
        <Eyebrow>Tappy lives in your menu bar</Eyebrow>
        <h2
          style={{
            width: 880,
            margin: "28px 0 0",
            fontSize: 84,
            lineHeight: 1,
            fontWeight: 900,
          }}
        >
          Turn on a little texture.
        </h2>
        <div
          style={{
            width: 850,
            height: 82,
            marginTop: 92,
            padding: "0 30px",
            border: "2px solid rgba(23,22,25,0.1)",
            borderRadius: 24,
            display: "flex",
            alignItems: "center",
            justifyContent: "space-between",
            backgroundColor: "#FFFFFF",
            boxShadow: "0 18px 54px rgba(23,22,25,0.09)",
            opacity: controlIn,
            transform: `translateY(${(1 - controlIn) * 30}px)`,
            fontSize: 20,
            fontWeight: 800,
          }}
        >
          <span>Finder&nbsp;&nbsp;&nbsp; File&nbsp;&nbsp;&nbsp; Edit</span>
          <span style={{display: "flex", alignItems: "center", gap: 14}}>
            <AppIcon size={38} style={{borderRadius: 9, filter: "none"}} />
            <span>Tappy</span>
            <span>9:41</span>
          </span>
        </div>
        <div style={{marginTop: 24, opacity: controlIn}}>
          <WavePill
            frame={frame}
            hits={editorialHits}
            label="Wet Squishy Pop"
            accent={colors.pink}
          />
        </div>
        <div
          style={{
            width: 720,
            minHeight: 110,
            marginTop: 42,
            padding: "28px 32px",
            borderRadius: 24,
            border: "2px solid rgba(23,22,25,0.1)",
            color: colors.charcoal,
            backgroundColor: "rgba(255,255,255,0.72)",
            fontSize: 33,
            fontWeight: 700,
            textAlign: "left",
          }}
        >
          {typed}
          <span style={{color: colors.rose, opacity: frame % 18 < 9 ? 1 : 0}}>
            |
          </span>
        </div>
        <div
          style={{
            width: 138,
            height: 76,
            marginTop: 48,
            padding: 8,
            borderRadius: 38,
            backgroundColor: "rgba(23,22,25,0.12)",
            display: "flex",
            alignItems: "center",
          }}
        >
          <span
            style={{
              width: 60,
              height: 60,
              borderRadius: "50%",
              backgroundColor: colors.charcoal,
              transform: `translateX(${toggle * 62}px)`,
              boxShadow: "0 8px 18px rgba(0,0,0,0.24)",
            }}
          />
        </div>
      </AbsoluteFill>

      <AbsoluteFill
        style={{
          opacity: textureOpacity,
          alignItems: "center",
          justifyContent: "center",
          backgroundColor: colors.rose,
          textAlign: "center",
        }}
      >
        {["soft", "tactile", "crisp", "settling"].map((word, index) => (
          <div
            key={word}
            style={{
              position: "absolute",
              left: index % 2 === 0 ? 68 : undefined,
              right: index % 2 === 1 ? 68 : undefined,
              top: 230 + index * 320,
              color: "rgba(247,246,242,0.23)",
              fontSize: 72,
              fontWeight: 900,
              transform: `translateX(${Math.sin(frame * 0.015 + index) * 20}px)`,
            }}
          >
            {word}
          </div>
        ))}
        <div
          style={{
            color: "rgba(23,22,25,0.68)",
            fontSize: 22,
            fontWeight: 900,
            textTransform: "uppercase",
          }}
        >
          Choose your texture
        </div>
        <h2
          style={{
            width: 900,
            margin: "28px 0 70px",
            color: colors.ivory,
            fontSize: 88,
            lineHeight: 0.98,
            fontWeight: 900,
          }}
        >
          {isWax ? "A crisp little crack." : "A soft little pop."}
        </h2>
        <WavePill
          frame={frame}
          hits={editorialHits}
          label={isWax ? "Wax Cracking" : "Wet Squishy Pop"}
          accent={isWax ? colors.lavender : colors.pink}
          width={760}
        />
        <div
          style={{
            marginTop: 54,
            color: "rgba(23,22,25,0.72)",
            fontSize: 28,
            fontWeight: 800,
          }}
        >
          Real Tappy sounds. Timed to every key.
        </div>
      </AbsoluteFill>

      <AbsoluteFill
        style={{
          opacity: closeOpacity,
          alignItems: "center",
          justifyContent: "center",
          backgroundColor: colors.ivory,
          textAlign: "center",
        }}
      >
        <AppIcon
          size={154}
          style={{
            transform: `scale(${0.96 + pulseAt(frame, editorialHits, 8) * 0.035})`,
          }}
        />
        <Eyebrow>Tappy for macOS</Eyebrow>
        <h2
          style={{
            width: 890,
            margin: "30px 0 0",
            fontSize: 88,
            lineHeight: 0.98,
            fontWeight: 900,
          }}
        >
          Make typing feel alive.
        </h2>
        <p
          style={{
            width: 760,
            margin: "30px 0 54px",
            color: colors.gray,
            fontSize: 31,
            lineHeight: 1.22,
            fontWeight: 600,
          }}
        >
          Wet Squishy Pop, Wax Cracking, and more in every Mac app.
        </p>
        <StoreButton />
      </AbsoluteFill>

      <AudioAccent
        frame={frame}
        hits={editorialHits}
        colors={[colors.pink, colors.lavender]}
      />
      <FinalBlack />
    </AbsoluteFill>
  );
};

const WetTextureArt: React.FC<{frame: number}> = ({frame}) => {
  const pulse = pulseAt(frame, textureHits, 9);
  return (
    <div
      style={{
        position: "relative",
        width: 620,
        height: 620,
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
      }}
    >
      {[520, 400, 280].map((size, index) => (
        <span
          key={size}
          style={{
            position: "absolute",
            width: size,
            height: size,
            borderRadius: `${42 - index * 4}%`,
            border: `3px solid rgba(255,182,193,${0.2 + index * 0.18})`,
            backgroundColor:
              index === 2 ? "rgba(255,182,193,0.06)" : "transparent",
            transform: `scale(${1 + pulse * (0.018 + index * 0.014)}) rotate(${Math.sin(frame * 0.014 + index) * 2}deg)`,
          }}
        />
      ))}
      <span
        style={{
          width: 92,
          height: 92,
          borderRadius: 32,
          backgroundColor: colors.pink,
          boxShadow: `0 0 ${42 + pulse * 50}px rgba(255,182,193,0.38)`,
          transform: `scale(${1 + pulse * 0.12})`,
        }}
      />
    </div>
  );
};

const WaxTextureArt: React.FC<{frame: number}> = ({frame}) => {
  const pulse = pulseAt(frame, textureHits, 8);
  const lines = [
    {height: 240, x: -70, y: -55, rotate: -31},
    {height: 190, x: 50, y: -78, rotate: 24},
    {height: 150, x: -128, y: 80, rotate: 62},
    {height: 160, x: 122, y: 66, rotate: -58},
    {height: 122, x: 4, y: 134, rotate: 8},
  ];
  return (
    <div
      style={{
        position: "relative",
        width: 620,
        height: 620,
        borderRadius: 64,
        border: "2px solid rgba(200,185,255,0.2)",
        backgroundColor: "rgba(200,185,255,0.035)",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
      }}
    >
      {lines.map((line, index) => (
        <span
          key={index}
          style={{
            position: "absolute",
            width: 6,
            height: line.height,
            borderRadius: 6,
            backgroundColor: `rgba(200,185,255,${0.42 + pulse * 0.32})`,
            transformOrigin: "bottom",
            transform: `translate(${line.x}px, ${line.y}px) rotate(${line.rotate}deg) scaleY(${0.78 + pulse * 0.22})`,
          }}
        />
      ))}
      <span
        style={{
          width: 96,
          height: 96,
          border: `3px solid ${colors.lavender}`,
          borderRadius: 28,
          backgroundColor: "rgba(200,185,255,0.08)",
          boxShadow: `0 0 ${38 + pulse * 44}px rgba(200,185,255,0.28)`,
          transform: `scale(${1 + pulse * 0.1})`,
        }}
      />
    </div>
  );
};

const TextureStudyVariation: React.FC = () => {
  const frame = useCurrentFrame();
  const introOpacity = sceneOpacity(frame, 0, 88, 14);
  const wetOpacity = sceneOpacity(frame, 68, 222, 16);
  const waxOpacity = sceneOpacity(frame, 202, 356, 16);
  const closeOpacity = sceneOpacity(frame, 336, 450, 16);
  const intro = enter(frame, 12, 24);

  return (
    <AbsoluteFill
      style={{
        backgroundColor: colors.charcoal,
        color: colors.ivory,
        fontFamily,
        overflow: "hidden",
      }}
    >
      <Audio src={staticFile("tappy-texture-study.wav")} volume={1} />

      <AbsoluteFill
        style={{
          opacity: introOpacity,
          alignItems: "center",
          justifyContent: "center",
          textAlign: "center",
        }}
      >
        <Eyebrow color={colors.pink}>A Tappy sound study</Eyebrow>
        <h1
          style={{
            width: 900,
            margin: "32px 0 0",
            fontSize: 96,
            lineHeight: 0.96,
            fontWeight: 900,
            opacity: intro,
            transform: `translateY(${(1 - intro) * 28}px)`,
          }}
        >
          Two textures. One keyboard.
        </h1>
        <p
          style={{
            width: 720,
            margin: "34px 0 0",
            color: "rgba(247,246,242,0.56)",
            fontSize: 32,
            lineHeight: 1.22,
            fontWeight: 600,
          }}
        >
          Put on headphones. Let each key settle into place.
        </p>
        <div style={{marginTop: 78}}>
          <WavePill
            frame={frame}
            hits={textureHits}
            label="listen"
            accent={colors.pink}
            width={720}
          />
        </div>
      </AbsoluteFill>

      <AbsoluteFill
        style={{
          opacity: wetOpacity,
          alignItems: "center",
          paddingTop: 150,
          textAlign: "center",
        }}
      >
        <Eyebrow color={colors.pink}>Texture 01</Eyebrow>
        <h2
          style={{
            margin: "24px 0 0",
            fontSize: 84,
            lineHeight: 1,
            fontWeight: 900,
          }}
        >
          Wet Squishy Pop
        </h2>
        <p
          style={{
            margin: "22px 0 34px",
            color: "rgba(247,246,242,0.55)",
            fontSize: 29,
            fontWeight: 600,
          }}
        >
          rounded / tactile / soft finish
        </p>
        <WetTextureArt frame={frame} />
        <div style={{marginTop: 20}}>
          <WavePill
            frame={frame}
            hits={textureHits}
            label="Wet Squishy Pop"
            accent={colors.pink}
            width={760}
          />
        </div>
      </AbsoluteFill>

      <AbsoluteFill
        style={{
          opacity: waxOpacity,
          alignItems: "center",
          paddingTop: 150,
          textAlign: "center",
          backgroundColor: "#19181D",
        }}
      >
        <Eyebrow color={colors.lavender}>Texture 02</Eyebrow>
        <h2
          style={{
            margin: "24px 0 0",
            fontSize: 84,
            lineHeight: 1,
            fontWeight: 900,
          }}
        >
          Wax Cracking
        </h2>
        <p
          style={{
            margin: "22px 0 34px",
            color: "rgba(247,246,242,0.55)",
            fontSize: 29,
            fontWeight: 600,
          }}
        >
          crisp / layered / delicate snap
        </p>
        <WaxTextureArt frame={frame} />
        <div style={{marginTop: 20}}>
          <WavePill
            frame={frame}
            hits={textureHits}
            label="Wax Cracking"
            accent={colors.lavender}
            width={760}
          />
        </div>
      </AbsoluteFill>

      <AbsoluteFill
        style={{
          opacity: closeOpacity,
          alignItems: "center",
          justifyContent: "center",
          textAlign: "center",
          backgroundColor: colors.charcoal,
        }}
      >
        <div style={{display: "flex", gap: 22, marginBottom: 44}}>
          <div
            style={{
              width: 270,
              height: 104,
              borderRadius: 26,
              border: "2px solid rgba(255,182,193,0.28)",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              color: colors.pink,
              fontSize: 24,
              fontWeight: 900,
            }}
          >
            Wet Squishy Pop
          </div>
          <div
            style={{
              width: 270,
              height: 104,
              borderRadius: 26,
              border: "2px solid rgba(200,185,255,0.28)",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              color: colors.lavender,
              fontSize: 24,
              fontWeight: 900,
            }}
          >
            Wax Cracking
          </div>
        </div>
        <AppIcon size={146} />
        <h2
          style={{
            width: 870,
            margin: "42px 0 0",
            fontSize: 86,
            lineHeight: 0.98,
            fontWeight: 900,
          }}
        >
          Find your typing rhythm.
        </h2>
        <p
          style={{
            width: 730,
            margin: "30px 0 50px",
            color: "rgba(247,246,242,0.58)",
            fontSize: 30,
            lineHeight: 1.22,
            fontWeight: 600,
          }}
        >
          Tappy brings tactile ASMR feedback to every Mac app.
        </p>
        <StoreButton />
      </AbsoluteFill>

      <AudioAccent
        frame={frame}
        hits={textureHits}
        colors={[colors.pink, colors.lavender]}
      />
      <FinalBlack />
    </AbsoluteFill>
  );
};

const PackRow: React.FC<{
  name: string;
  color: string;
  code: string;
  selected?: boolean;
  premium?: boolean;
  pulse?: number;
}> = ({name, color, code, selected = false, premium = false, pulse = 0}) => (
  <div
    style={{
      height: 116,
      display: "flex",
      alignItems: "center",
      gap: 24,
      padding: "0 28px",
      borderRadius: 24,
      border: selected ? `2px solid ${color}` : "2px solid transparent",
      backgroundColor: selected ? `${color}16` : "transparent",
      transform: `scale(${1 + pulse * 0.012})`,
    }}
  >
    <span
      style={{
        width: 68,
        height: 68,
        borderRadius: 18,
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        color,
        backgroundColor: `${color}20`,
        fontSize: 25,
        fontWeight: 900,
      }}
    >
      {code}
    </span>
    <span
      style={{
        flex: 1,
        color: colors.ivory,
        fontSize: 29,
        fontWeight: selected ? 900 : 700,
      }}
    >
      {name}
    </span>
    {premium ? (
      <span
        style={{
          padding: "7px 11px",
          borderRadius: 10,
          color: "rgba(247,246,242,0.5)",
          backgroundColor: "rgba(247,246,242,0.08)",
          fontSize: 16,
          fontWeight: 900,
        }}
      >
        PRO
      </span>
    ) : null}
    {selected ? (
      <span style={{color, fontSize: 18, fontWeight: 900}}>PLAYING</span>
    ) : null}
  </div>
);

const MenuRitualVariation: React.FC = () => {
  const frame = useCurrentFrame();
  const introOpacity = sceneOpacity(frame, 0, 94, 14);
  const menuOpacity = sceneOpacity(frame, 76, 252, 16);
  const documentOpacity = sceneOpacity(frame, 234, 366, 16);
  const closeOpacity = sceneOpacity(frame, 348, 450, 16);
  const menuIn = enter(frame, 92, 22);
  const selectedWax = frame >= 168;
  const pulse = pulseAt(frame, ritualHits, 8);
  const typed = "typing should feel as good as it sounds.".slice(
    0,
    Math.floor(interpolate(frame, [256, 344], [0, 40], clamp)),
  );

  return (
    <AbsoluteFill
      style={{
        backgroundColor: colors.charcoal,
        color: colors.ivory,
        fontFamily,
        overflow: "hidden",
      }}
    >
      <Audio src={staticFile("tappy-menu-ritual.wav")} volume={1} />
      <Img
        src={staticFile("cozy-desk.png")}
        style={{
          position: "absolute",
          inset: -80,
          width: 1240,
          height: 2080,
          objectFit: "cover",
          filter: "blur(18px) saturate(0.62) brightness(0.34)",
          transform: "scale(1.12)",
        }}
      />
      <AbsoluteFill style={{backgroundColor: "rgba(15,14,18,0.42)"}} />

      <AbsoluteFill
        style={{
          opacity: introOpacity,
          alignItems: "center",
          justifyContent: "center",
          textAlign: "center",
        }}
      >
        <AppIcon size={150} />
        <Eyebrow color={colors.pink}>A quieter menu bar ritual</Eyebrow>
        <h1
          style={{
            width: 900,
            margin: "32px 0 0",
            fontSize: 92,
            lineHeight: 0.97,
            fontWeight: 900,
          }}
        >
          Pick a sound. Start typing.
        </h1>
        <p
          style={{
            width: 730,
            margin: "30px 0 0",
            color: "rgba(247,246,242,0.62)",
            fontSize: 31,
            lineHeight: 1.24,
            fontWeight: 600,
          }}
        >
          Tappy stays out of the way until you need it.
        </p>
      </AbsoluteFill>

      <AbsoluteFill style={{opacity: menuOpacity, alignItems: "center"}}>
        <div
          style={{
            width: "100%",
            height: 92,
            padding: "0 48px",
            display: "flex",
            alignItems: "center",
            justifyContent: "space-between",
            borderBottom: "2px solid rgba(247,246,242,0.12)",
            backgroundColor: "rgba(20,19,23,0.9)",
            fontSize: 21,
            fontWeight: 800,
          }}
        >
          <span>Finder&nbsp;&nbsp;&nbsp; File&nbsp;&nbsp;&nbsp; Edit&nbsp;&nbsp;&nbsp; View</span>
          <span style={{display: "flex", alignItems: "center", gap: 16}}>
            <AppIcon size={42} style={{borderRadius: 10, filter: "none"}} />
            <span>Tappy</span>
            <span>9:41</span>
          </span>
        </div>

        <div
          style={{
            position: "relative",
            width: 790,
            marginTop: 72,
            padding: "38px 34px 32px",
            border: "2px solid rgba(247,246,242,0.17)",
            borderRadius: 42,
            backgroundColor: "rgba(24,23,26,0.96)",
            boxShadow: "0 36px 90px rgba(0,0,0,0.46)",
            opacity: menuIn,
            transform: `translateY(${(1 - menuIn) * 38}px) scale(${0.97 + menuIn * 0.03})`,
          }}
        >
          <div
            style={{
              position: "absolute",
              top: -20,
              left: "50%",
              width: 40,
              height: 40,
              borderTop: "2px solid rgba(247,246,242,0.17)",
              borderLeft: "2px solid rgba(247,246,242,0.17)",
              backgroundColor: "rgba(24,23,26,0.96)",
              transform: "translateX(-50%) rotate(45deg)",
            }}
          />
          <div
            style={{
              display: "flex",
              alignItems: "center",
              justifyContent: "space-between",
              padding: "0 16px 24px",
              borderBottom: "2px solid rgba(247,246,242,0.12)",
            }}
          >
            <div>
              <div style={{fontSize: 42, fontWeight: 900}}>Tappy</div>
              <div
                style={{
                  marginTop: 6,
                  color: "rgba(247,246,242,0.5)",
                  fontSize: 21,
                  fontWeight: 700,
                }}
              >
                Auditory typing feedback
              </div>
            </div>
            <div
              style={{
                display: "flex",
                alignItems: "center",
                gap: 10,
                color: "rgba(247,246,242,0.62)",
                fontSize: 22,
                fontWeight: 800,
              }}
            >
              <span
                style={{
                  width: 14,
                  height: 14,
                  borderRadius: "50%",
                  backgroundColor: colors.green,
                }}
              />
              Active
            </div>
          </div>
          <div style={{paddingTop: 14}}>
            <PackRow
              name="Tapping Nails on Plastic"
              color="#7DC1FF"
              code="P"
            />
            <PackRow
              name="Wood and Sand Blocks"
              color="#64D87C"
              code="W"
            />
            <PackRow
              name="Wet Squishy Pop"
              color={colors.pink}
              code="S"
              premium
              selected={!selectedWax}
              pulse={!selectedWax ? pulse : 0}
            />
            <PackRow
              name="Wax Cracking"
              color={colors.lavender}
              code="C"
              premium
              selected={selectedWax}
              pulse={selectedWax ? pulse : 0}
            />
          </div>
          <div
            style={{
              marginTop: 18,
              padding: "26px 22px 4px",
              borderTop: "2px solid rgba(247,246,242,0.12)",
            }}
          >
            <div
              style={{
                display: "flex",
                alignItems: "center",
                justifyContent: "space-between",
                color: "rgba(247,246,242,0.72)",
                fontSize: 21,
                fontWeight: 800,
              }}
            >
              <span>Feedback Volume</span>
              <span>72%</span>
            </div>
            <div
              style={{
                position: "relative",
                height: 9,
                marginTop: 22,
                borderRadius: 9,
                backgroundColor: "rgba(247,246,242,0.14)",
              }}
            >
              <span
                style={{
                  position: "absolute",
                  left: 0,
                  top: 0,
                  width: "72%",
                  height: "100%",
                  borderRadius: 9,
                  backgroundColor: selectedWax ? colors.lavender : colors.pink,
                }}
              />
            </div>
          </div>
        </div>
      </AbsoluteFill>

      <AbsoluteFill
        style={{
          opacity: documentOpacity,
          alignItems: "center",
          justifyContent: "center",
        }}
      >
        <div
          style={{
            width: 880,
            minHeight: 850,
            padding: "76px 70px",
            borderRadius: 36,
            color: colors.charcoal,
            backgroundColor: colors.ivory,
            boxShadow: "0 36px 90px rgba(0,0,0,0.42)",
          }}
        >
          <div
            style={{
              display: "flex",
              alignItems: "center",
              justifyContent: "space-between",
            }}
          >
            <Eyebrow>New note</Eyebrow>
            <span style={{color: colors.gray, fontSize: 20, fontWeight: 800}}>
              9:41 AM
            </span>
          </div>
          <h2
            style={{
              margin: "72px 0 0",
              fontSize: 72,
              lineHeight: 1.02,
              fontWeight: 900,
            }}
          >
            {typed}
            <span style={{color: colors.rose, opacity: frame % 18 < 9 ? 1 : 0}}>
              |
            </span>
          </h2>
          <p
            style={{
              margin: "36px 0 90px",
              color: colors.gray,
              fontSize: 29,
              lineHeight: 1.3,
              fontWeight: 600,
            }}
          >
            Tappy plays locally and never reads, records, or transmits what you type.
          </p>
          <WavePill
            frame={frame}
            hits={ritualHits}
            label={frame < 295 ? "Wet Squishy Pop" : "Wax Cracking"}
            accent={frame < 295 ? colors.pink : colors.lavender}
            width={740}
          />
        </div>
      </AbsoluteFill>

      <AbsoluteFill
        style={{
          opacity: closeOpacity,
          alignItems: "center",
          justifyContent: "center",
          textAlign: "center",
          backgroundColor: "rgba(15,14,18,0.5)",
        }}
      >
        <AppIcon size={154} />
        <Eyebrow color={colors.pink}>Tappy for macOS</Eyebrow>
        <h2
          style={{
            width: 890,
            margin: "30px 0 0",
            fontSize: 86,
            lineHeight: 0.98,
            fontWeight: 900,
          }}
        >
          Your favorite sound, one click away.
        </h2>
        <p
          style={{
            width: 740,
            margin: "30px 0 50px",
            color: "rgba(247,246,242,0.62)",
            fontSize: 30,
            lineHeight: 1.22,
            fontWeight: 600,
          }}
        >
          Quick controls from the menu bar. Gentle feedback everywhere you type.
        </p>
        <StoreButton />
      </AbsoluteFill>

      <AudioAccent
        frame={frame}
        hits={ritualHits}
        colors={[colors.pink, colors.lavender]}
      />
      <FinalBlack />
    </AbsoluteFill>
  );
};

export const TappyInspirationVariationCompositions: React.FC = () => {
  return (
    <>
      <Composition
        id="TappyEditorial15"
        component={EditorialVariation}
        durationInFrames={DURATION_IN_FRAMES}
        fps={FPS}
        width={1080}
        height={1920}
      />
      <Composition
        id="TappyTextureStudy15"
        component={TextureStudyVariation}
        durationInFrames={DURATION_IN_FRAMES}
        fps={FPS}
        width={1080}
        height={1920}
      />
      <Composition
        id="TappyMenuRitual15"
        component={MenuRitualVariation}
        durationInFrames={DURATION_IN_FRAMES}
        fps={FPS}
        width={1080}
        height={1920}
      />
    </>
  );
};
