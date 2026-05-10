window.SLIME_CONFIG = {
  game: {
    width: 1280,
    height: 720,
    fixedScale: true
  },
  art: {
    baseWidth: 1600,
    baseHeight: 900,
    fonts: [
      // 例:
      // { family: "MyGameFont", path: "./assets/fonts/MyGameFont-Regular.ttf", weight: "normal", style: "normal" }
    ],
    backgrounds: {
      title: "./assets/screens/title/background.png",
      options: "./assets/screens/options/background.png",
      select: "./assets/screens/select/background.png",
      game: "./assets/screens/game/background.png",
      result: "./assets/screens/result/background.png"
    },
    images: {
      title: [],
      options: [],
      select: [],
      game: [],
      result: []
    }
  },
  slimePresets: [
    {
      id: "mint",
      name: "ミントスライム",
      color: "#74ffcc",
      gain: 11,
      firmness: 0.7,
      assets: {
        slimeImage: "./assets/slimes/mint/slime.svg",
        thumbImage: "./assets/slimes/mint/thumb.svg",
        voiceStart: "./assets/slimes/mint/start.wav",
        voiceFinish: "./assets/slimes/mint/finish.wav",
        sfxPolishLoop: "./assets/slimes/mint/polish_loop.wav"
      }
    },
    {
      id: "peach",
      name: "ピーチスライム",
      color: "#ff9eb4",
      gain: 26,
      firmness: 1.0,
      assets: {
        slimeImage: "./assets/slimes/peach/slime.svg",
        thumbImage: "./assets/slimes/peach/thumb.svg",
        voiceStart: "./assets/slimes/peach/start.wav",
        voiceFinish: "./assets/slimes/peach/finish.wav",
        sfxPolishLoop: "./assets/slimes/peach/polish_loop.wav"
      }
    },
    {
      id: "azure",
      name: "アズールスライム",
      color: "#70b9ff",
      gain: 22,
      firmness: 1.2,
      assets: {
        slimeImage: "./assets/slimes/azure/slime.svg",
        thumbImage: "./assets/slimes/azure/thumb.svg",
        voiceStart: "./assets/slimes/azure/start.wav",
        voiceFinish: "./assets/slimes/azure/finish.wav",
        sfxPolishLoop: "./assets/slimes/azure/polish_loop.wav"
      }
    }
  ],
  pairLayout: [
    { side: "left", xRatio: 0.33, yRatio: 0.48, radius: 14 },
    { side: "right", xRatio: 0.67, yRatio: 0.48, radius: 14 }
  ],
  brush: {
    radius: 34,
    hitRadius: 20,
    polishGainPerSec: 20,
    painGainPerSec: 8,
    startPositions: [
      { xRatio: 0.82, yRatio: 0.14 },
      { xRatio: 0.92, yRatio: 0.24 },
      { xRatio: 0.82, yRatio: 0.34 },
      { xRatio: 0.92, yRatio: 0.44 },
      { xRatio: 0.82, yRatio: 0.54 }
    ],
    followSpeed: 16,
    spinSpeed: 9,
    items: [
      { image: "./assets/brushes/brush1.png", hitRadius: 20, polishGainPerSec: 20, painGainPerSec: 8 },
      { image: "./assets/brushes/brush2.png", hitRadius: 18, polishGainPerSec: 24, painGainPerSec: 11 },
      { image: "./assets/brushes/brush3.png", hitRadius: 16, polishGainPerSec: 18, painGainPerSec: 6 },
      { image: "./assets/brushes/brush4.png", hitRadius: 22, polishGainPerSec: 28, painGainPerSec: 14 },
      { image: "./assets/brushes/brush5.png", hitRadius: 15, polishGainPerSec: 14, painGainPerSec: 4 }
    ]
  },
  zoom: {
    insetWidth: 220,
    insetHeight: 220,
    margin: 16,
    sourceWidth: 50,
    sourceHeight: 50
  }
};
