// Level Configurations for the Liminal Space Game
// Legend:
// '1': Wall (rendered according to theme)
// '0': Empty corridor
// 'P': Player Spawn Point
// 'E': Exit Door (requires all keys on levels that have keys)
// 'K': Keycard/Key (needed to unlock the exit)
// 'B': Battery (refills flashlight)
// 'M': Monster Spawn Point
// 'L': Ceiling Light source (flickering)
// 'W': Deep Water (for pool rooms, slows player)
// 'V': Valve (for turning off steam hazards)
// 'H': Steam Hazard (damages player unless valve is off)

export const LEVELS = [
  // Level 1: The Yellow Lobby (Classic Backrooms)
  {
    name: "Level 1: The Yellow Lobby",
    description: "Find the exit door. The hum of fluorescent lights fills the empty spaces.",
    theme: "backrooms",
    wallColor: "#d2b48c", // Yellowish tan
    floorColor: "#8b7355", // Damp brown carpet
    ceilingColor: "#e6e1c5", // Acoustic tile
    lightColor: "#ffffd0",
    ambientColor: "#222218",
    fogColor: "#22221b",
    fogDensity: 0.05,
    hasMonster: false,
    monsterSpeed: 0,
    keysRequired: 0,
    grid: [
      "111111111111111",
      "1P0001000000011",
      "101101011111001",
      "101000010001101",
      "101011010101101",
      "100001000100001",
      "101111110111101",
      "10100000001B101",
      "101011111010101",
      "100010001000101",
      "111010101011101",
      "100000100010001",
      "101111111010111",
      "1000000000000E1",
      "111111111111111"
    ]
  },
  // Level 2: Habitable Zone
  {
    name: "Level 2: Habitable Zone",
    description: "Search for the security keycard (K) to unlock the exit elevator.",
    theme: "office",
    wallColor: "#e3e3e3", // Off-white office panels
    floorColor: "#555f6b", // Grey industrial carpet
    ceilingColor: "#d3d3d3",
    lightColor: "#e8f4f8",
    ambientColor: "#181a20",
    fogColor: "#15181d",
    fogDensity: 0.07,
    hasMonster: false,
    monsterSpeed: 0,
    keysRequired: 1,
    grid: [
      "11111111111111111",
      "1P000010000000B01",
      "10111010111111101",
      "101K1000100000101",
      "10101110101110101",
      "10001000100010001",
      "11101011111011101",
      "10000010001010001",
      "10111010101010111",
      "101B1000101000101",
      "10101111101111101",
      "100000000000000E1",
      "11111111111111111"
    ]
  },
  // Level 3: Pipe Dreams
  {
    name: "Level 3: Pipe Dreams",
    description: "Turn the steam valve (V) to clear the pipe leak (H) and unlock the exit.",
    theme: "industrial",
    wallColor: "#5c5c5c", // Dark concrete
    floorColor: "#3a3a3a", // Metal floor grating
    ceilingColor: "#2e2e2e",
    lightColor: "#ffaa44", // Amber sodium lamps
    ambientColor: "#15100a",
    fogColor: "#1a120b",
    fogDensity: 0.09,
    hasMonster: false,
    monsterSpeed: 0,
    keysRequired: 0, // Requires turning off steam (which acts as a key block)
    grid: [
      "1111111111111111111",
      "1P00010000000010011",
      "1110110111111010101",
      "1000000100001000101",
      "1011110101101110101",
      "101B010101V00010101",
      "1011010111111010101",
      "1000000000001010001",
      "111111111H111011101", // Steam hazard H blocks path
      "1000000010100000101",
      "1011111010101110101",
      "101B001000001010001",
      "1011101111111011101",
      "1000000000000000E11",
      "1111111111111111111"
    ]
  },
  // Level 4: The Poolrooms
  {
    name: "Level 4: The Poolrooms",
    description: "Deep tiled pools (W) will slow down your movement. Find 2 keycards.",
    theme: "pools",
    wallColor: "#ffffff", // Pure white tiles
    floorColor: "#70d6ff", // Aqua blue water
    ceilingColor: "#f0f8ff",
    lightColor: "#80ffd0", // Blueish cyan light
    ambientColor: "#051c24",
    fogColor: "#082630",
    fogDensity: 0.04,
    hasMonster: false,
    monsterSpeed: 0,
    keysRequired: 2,
    grid: [
      "1111111111111111111",
      "1P0000WWWWWW00000K1",
      "101110W0000W0111101",
      "101010W0110W0100101",
      "101B10WWWWWW010B101",
      "1010000000000001101",
      "1011111101111111001",
      "1000000101000000001",
      "1111110101011111101",
      "1K0001010101B000101",
      "1010000100010100001",
      "1011111111110111101",
      "1000000000000000E01",
      "1111111111111111111"
    ]
  },
  // Level 5: Sub-Level 0
  {
    name: "Level 5: Sub-Level 0",
    description: "The flashlight battery drains much faster here. Beware: you are no longer alone.",
    theme: "sublevel",
    wallColor: "#404040", // Rough dark concrete
    floorColor: "#222222",
    ceilingColor: "#1a1a1a",
    lightColor: "#ffd699",
    ambientColor: "#050505",
    fogColor: "#050505",
    fogDensity: 0.12,
    hasMonster: true,
    monsterSpeed: 2.2,
    keysRequired: 1,
    grid: [
      "11111111111111111",
      "1P00001000000M0B1",
      "10110110111110101",
      "10100000000010101",
      "10101111111010101",
      "10001K0000101B001",
      "10101110101011101",
      "10100010101000101",
      "11111010101110101",
      "10000010000010001",
      "10111111111011101",
      "100000000000000E1",
      "11111111111111111"
    ]
  },
  // Level 6: The Office Cubicles
  {
    name: "Level 6: The Office Cubicles",
    description: "A confusing grid of partitions. Find the blue-glowing server room to get the key.",
    theme: "cubicles",
    wallColor: "#e6dfd3", // Cloth partitions
    floorColor: "#4a3c31",
    ceilingColor: "#cccccc",
    lightColor: "#80c0ff", // Spooky blue computer glow
    ambientColor: "#080b10",
    fogColor: "#05070a",
    fogDensity: 0.08,
    hasMonster: true,
    monsterSpeed: 2.5,
    keysRequired: 1,
    grid: [
      "1111111111111111111",
      "1P001001001001000B1",
      "1010101010101010101",
      "1010000000000000101",
      "1010101111111010101",
      "1010101K00001010101",
      "1000101010101010001",
      "1110101010101010111",
      "1000100010100010001",
      "1011111010101111101",
      "100B1M0010100000001",
      "1110111110111110111",
      "10000000000000000E1",
      "1111111111111111111"
    ]
  },
  // Level 7: Lights Out
  {
    name: "Level 7: Lights Out",
    description: "Total darkness. Ambient light is zero. Rely entirely on your flashlight.",
    theme: "pitchblack",
    wallColor: "#111111",
    floorColor: "#080808",
    ceilingColor: "#050505",
    lightColor: "#000000", // NO environmental light!
    ambientColor: "#000000",
    fogColor: "#000000",
    fogDensity: 0.2, // Extremely dense black fog
    hasMonster: true,
    monsterSpeed: 2.8,
    keysRequired: 2,
    grid: [
      "1111111111111111111",
      "1P000001000000000B1",
      "1011110101111111011",
      "10100K0101000001011",
      "1010111101011101011",
      "100000000101B101001",
      "1111101111010101101",
      "1M00101000010100101",
      "1110101011110110101",
      "1K00100000000010001",
      "1011111111111111101",
      "10000000000000000E1",
      "1111111111111111111"
    ]
  },
  // Level 8: The Boiler Room
  {
    name: "Level 8: The Boiler Room",
    description: "The sirens are blaring. Extreme steam hazards (H). Find the master valve (V) to escape.",
    theme: "boiler",
    wallColor: "#802000", // Rusty red metal panels
    floorColor: "#301000",
    ceilingColor: "#200800",
    lightColor: "#ff3300", // Pulsing emergency red
    ambientColor: "#200500",
    fogColor: "#1d0800",
    fogDensity: 0.1,
    hasMonster: true,
    monsterSpeed: 3.0,
    keysRequired: 0, // Regulated by steam barrier blocking exit
    grid: [
      "1111111111111111111",
      "1P000M000100000B0K1",
      "11111H1011101111011", // Steam hazard H blocking the way
      "100010101V101001011", // Valve V turns it off
      "1010001000101001011",
      "1011111101101011011",
      "1000000000001000011",
      "1111111111011111011",
      "1B00000010000001011",
      "1011110110111101011",
      "1010000000000100001",
      "1010111111110111111",
      "10000000000000000E1",
      "1111111111111111111"
    ]
  },
  // Level 9: Suburban Abyss
  {
    name: "Level 9: Suburban Abyss",
    description: "A mock outdoor street trapped underground. The monster is faster and relentless.",
    theme: "suburbia",
    wallColor: "#ffffff", // Siding houses / white fences
    floorColor: "#224422", // Artificial grass carpet
    ceilingColor: "#0a0d14", // Pitch black sky
    lightColor: "#bbd0ff", // Moon-like blue light
    ambientColor: "#080c15",
    fogColor: "#080c15",
    fogDensity: 0.06,
    hasMonster: true,
    monsterSpeed: 3.2,
    keysRequired: 3,
    grid: [
      "1111111111111111111",
      "1P00000100K000000K1",
      "1011101111111110101",
      "1010100001000010101",
      "1010111011101010101",
      "10000B100M001B10001",
      "1110111011101110111",
      "1000100000000010001",
      "1010101111111010101",
      "1010101000001010101",
      "1K10101011101010101",
      "10000000000000000E1",
      "1111111111111111111"
    ]
  },
  // Level 10: The Threshold
  {
    name: "Level 10: The Threshold",
    description: "The final stretch. A long straight bridge over the white abyss. The Entity starts behind you. RUN!",
    theme: "threshold",
    wallColor: "#050505", // Infinite dark walls
    floorColor: "#333333", // Metal bridge floor
    ceilingColor: "#050505",
    lightColor: "#ffffff", // Bright glowing portal ahead
    ambientColor: "#111111",
    fogColor: "#eeeeee", // White glowing fog in the pit
    fogDensity: 0.03,
    hasMonster: true,
    monsterSpeed: 3.5, // Extremely fast
    keysRequired: 0,
    grid: [
      "111111111111111111111111111111111111111111111111111111111111111",
      "1M0 P00000000000000000000000000000000000000000000000000000000E1",
      "111111111111111111111111111111111111111111111111111111111111111"
    ]
  }
];
