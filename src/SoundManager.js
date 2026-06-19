// Real-time Procedural Audio Generator using Web Audio API
// No external assets required. Works 100% offline.

class SoundManager {
  constructor() {
    this.ctx = null;
    this.masterGain = null;
    this.humOsc = null;
    this.humBuzz = null;
    this.humGain = null;
    
    // Proximity Static
    this.staticNode = null;
    this.staticGain = null;

    // Dripping water interval
    this.dripInterval = null;
    
    this.isInitialized = false;
  }

  init() {
    if (this.isInitialized) return;
    
    try {
      const AudioContextClass = window.AudioContext || window.webkitAudioContext;
      this.ctx = new AudioContextClass();
      
      this.masterGain = this.ctx.createGain();
      this.masterGain.gain.setValueAtTime(0.3, this.ctx.currentTime); // Master volume limit
      this.masterGain.connect(this.ctx.destination);
      
      // Initialize Static for monster proximity
      this.initStatic();
      
      this.isInitialized = true;
      console.log("Web Audio API SoundManager initialized successfully.");
    } catch (e) {
      console.error("Failed to initialize Web Audio API:", e);
    }
  }

  resume() {
    if (this.ctx && this.ctx.state === 'suspended') {
      this.ctx.resume();
    }
  }

  // --- FLASHHLIGHT CLICK ---
  playClick() {
    this.init();
    this.resume();
    if (!this.ctx) return;

    // A very short click impulse using an oscillator
    const osc = this.ctx.createOscillator();
    const gainNode = this.ctx.createGain();
    
    osc.type = 'sine';
    osc.frequency.setValueAtTime(1200, this.ctx.currentTime);
    osc.frequency.exponentialRampToValueAtTime(100, this.ctx.currentTime + 0.05);

    gainNode.gain.setValueAtTime(0.08, this.ctx.currentTime);
    gainNode.gain.exponentialRampToValueAtTime(0.001, this.ctx.currentTime + 0.05);

    osc.connect(gainNode);
    gainNode.connect(this.masterGain);

    osc.start();
    osc.stop(this.ctx.currentTime + 0.05);
  }

  // --- FLUORESCENT LIGHT HUM ---
  startHum(intensity = 1.0) {
    this.init();
    this.resume();
    if (!this.ctx || this.humOsc) return;

    // 60Hz hum (Ground loop style)
    this.humOsc = this.ctx.createOscillator();
    this.humOsc.type = 'sine';
    this.humOsc.frequency.setValueAtTime(60, this.ctx.currentTime);

    // High frequency buzz (Harmonics)
    this.humBuzz = this.ctx.createOscillator();
    this.humBuzz.type = 'sawtooth';
    this.humBuzz.frequency.setValueAtTime(120, this.ctx.currentTime);

    // Filter to keep only high buzz and make it tinny
    const buzzFilter = this.ctx.createBiquadFilter();
    buzzFilter.type = 'bandpass';
    buzzFilter.frequency.setValueAtTime(4000, this.ctx.currentTime);
    buzzFilter.Q.setValueAtTime(10, this.ctx.currentTime);

    // Hum gain
    this.humGain = this.ctx.createGain();
    this.humGain.gain.setValueAtTime(0.02 * intensity, this.ctx.currentTime);

    // Connect hum
    this.humOsc.connect(this.humGain);
    
    // Connect buzz through filter
    const buzzGain = this.ctx.createGain();
    buzzGain.gain.setValueAtTime(0.003 * intensity, this.ctx.currentTime);
    this.humBuzz.connect(buzzFilter);
    buzzFilter.connect(buzzGain);
    buzzGain.connect(this.humGain);

    this.humGain.connect(this.masterGain);

    this.humOsc.start();
    this.humBuzz.start();
  }

  setHumVolume(intensity) {
    if (this.humGain && this.ctx) {
      this.humGain.gain.setTargetAtTime(0.02 * intensity, this.ctx.currentTime, 0.1);
    }
  }

  stopHum() {
    if (this.humOsc) {
      try {
        this.humOsc.stop();
        this.humBuzz.stop();
      } catch (e) {}
      this.humOsc = null;
      this.humBuzz = null;
      this.humGain = null;
    }
  }

  // --- PROXIMITY RADIO STATIC (White Noise) ---
  initStatic() {
    if (!this.ctx) return;

    const bufferSize = 2 * this.ctx.sampleRate;
    const noiseBuffer = this.ctx.createBuffer(1, bufferSize, this.ctx.sampleRate);
    const output = noiseBuffer.getChannelData(0);
    
    for (let i = 0; i < bufferSize; i++) {
      output[i] = Math.random() * 2 - 1;
    }

    this.staticNode = this.ctx.createBufferSource();
    this.staticNode.buffer = noiseBuffer;
    this.staticNode.loop = true;

    this.staticGain = this.ctx.createGain();
    this.staticGain.gain.setValueAtTime(0.0, this.ctx.currentTime);

    const staticFilter = this.ctx.createBiquadFilter();
    staticFilter.type = 'bandpass';
    staticFilter.frequency.setValueAtTime(1000, this.ctx.currentTime);
    staticFilter.Q.setValueAtTime(1.5, this.ctx.currentTime);

    this.staticNode.connect(staticFilter);
    staticFilter.connect(this.staticGain);
    this.staticGain.connect(this.masterGain);

    this.staticNode.start();
  }

  setStaticLevel(distanceRatio) {
    // distanceRatio: 0 (far away) to 1 (right on top of the player)
    this.init();
    this.resume();
    if (!this.staticGain || !this.ctx) return;

    const targetGain = Math.pow(distanceRatio, 2) * 0.15; // quadratic scaling for alarm effect
    this.staticGain.gain.setTargetAtTime(targetGain, this.ctx.currentTime, 0.05);

    // Also modulate hum buzz pitch slightly to simulate interference
    if (this.humBuzz) {
      const wobble = (Math.random() - 0.5) * distanceRatio * 15;
      this.humBuzz.frequency.setValueAtTime(120 + wobble, this.ctx.currentTime);
    }
  }

  // --- WATER DRIPS (For Poolrooms) ---
  startDrips() {
    this.init();
    this.resume();
    this.stopDrips();

    this.dripInterval = setInterval(() => {
      if (Math.random() > 0.4) {
        this.playDripSound();
      }
    }, 1500);
  }

  stopDrips() {
    if (this.dripInterval) {
      clearInterval(this.dripInterval);
      this.dripInterval = null;
    }
  }

  playDripSound() {
    if (!this.ctx) return;

    const osc = this.ctx.createOscillator();
    const gainNode = this.ctx.createGain();
    
    osc.type = 'sine';
    // Drip plop sound: sweeps up in frequency rapidly
    const startTime = this.ctx.currentTime;
    const baseFreq = 800 + Math.random() * 400;
    osc.frequency.setValueAtTime(baseFreq, startTime);
    osc.frequency.exponentialRampToValueAtTime(baseFreq + 600, startTime + 0.08);

    gainNode.gain.setValueAtTime(0.015, startTime);
    gainNode.gain.exponentialRampToValueAtTime(0.0001, startTime + 0.15);

    // Echo effect (simple delay)
    const delay = this.ctx.createDelay();
    delay.delayTime.setValueAtTime(0.08, startTime);
    const feedback = this.ctx.createGain();
    feedback.gain.setValueAtTime(0.3, startTime);

    osc.connect(gainNode);
    gainNode.connect(this.masterGain);

    // Connect to echo
    gainNode.connect(delay);
    delay.connect(feedback);
    feedback.connect(delay); // loop
    feedback.connect(this.masterGain);

    osc.start();
    osc.stop(startTime + 0.25);
  }

  // --- FOOTSTEPS ---
  playFootstep(surface = "carpet") {
    this.init();
    this.resume();
    if (!this.ctx) return;

    const noiseBuffer = this.ctx.createBuffer(1, 0.1 * this.ctx.sampleRate, this.ctx.sampleRate);
    const output = noiseBuffer.getChannelData(0);
    for (let i = 0; i < noiseBuffer.length; i++) {
      output[i] = Math.random() * 2 - 1;
    }

    const noiseSource = this.ctx.createBufferSource();
    noiseSource.buffer = noiseBuffer;

    const filter = this.ctx.createBiquadFilter();
    const gainNode = this.ctx.createGain();

    if (surface === "water") {
      // Splash: bandpass sweeping downwards with slightly higher gain
      filter.type = 'bandpass';
      filter.frequency.setValueAtTime(600, this.ctx.currentTime);
      filter.frequency.exponentialRampToValueAtTime(150, this.ctx.currentTime + 0.1);
      gainNode.gain.setValueAtTime(0.08, this.ctx.currentTime);
      gainNode.gain.exponentialRampToValueAtTime(0.001, this.ctx.currentTime + 0.12);
    } else if (surface === "concrete" || surface === "boiler" || surface === "industrial") {
      // Concrete clack: low-pass filter but higher cutoff than carpet
      filter.type = 'lowpass';
      filter.frequency.setValueAtTime(400, this.ctx.currentTime);
      gainNode.gain.setValueAtTime(0.05, this.ctx.currentTime);
      gainNode.gain.exponentialRampToValueAtTime(0.001, this.ctx.currentTime + 0.08);
    } else {
      // Default: Damp carpet (very low pass filter, soft thud)
      filter.type = 'lowpass';
      filter.frequency.setValueAtTime(180, this.ctx.currentTime);
      gainNode.gain.setValueAtTime(0.06, this.ctx.currentTime);
      gainNode.gain.exponentialRampToValueAtTime(0.001, this.ctx.currentTime + 0.1);
    }

    noiseSource.connect(filter);
    filter.connect(gainNode);
    gainNode.connect(this.masterGain);

    noiseSource.start();
  }

  // --- ENTITY JUMPSCARE SCREECH ---
  playScreech() {
    this.init();
    this.resume();
    if (!this.ctx) return;

    const osc1 = this.ctx.createOscillator();
    const osc2 = this.ctx.createOscillator();
    const distortion = this.ctx.createWaveShaper();
    const gainNode = this.ctx.createGain();

    // Distort the sound for extra horror
    distortion.curve = makeDistortionCurve(400);
    distortion.oversample = '4x';

    osc1.type = 'sawtooth';
    osc1.frequency.setValueAtTime(100, this.ctx.currentTime);
    osc1.frequency.linearRampToValueAtTime(600, this.ctx.currentTime + 0.1);
    osc1.frequency.exponentialRampToValueAtTime(50, this.ctx.currentTime + 0.8);

    osc2.type = 'sawtooth';
    osc2.frequency.setValueAtTime(120, this.ctx.currentTime);
    osc2.frequency.linearRampToValueAtTime(750, this.ctx.currentTime + 0.15);
    osc2.frequency.exponentialRampToValueAtTime(60, this.ctx.currentTime + 0.8);

    gainNode.gain.setValueAtTime(0.25, this.ctx.currentTime);
    gainNode.gain.exponentialRampToValueAtTime(0.001, this.ctx.currentTime + 0.9);

    osc1.connect(distortion);
    osc2.connect(distortion);
    distortion.connect(gainNode);
    gainNode.connect(this.ctx.destination); // Connect directly to destination to bypass master gain limit!

    osc1.start();
    osc2.start();

    osc1.stop(this.ctx.currentTime + 1.0);
    osc2.stop(this.ctx.currentTime + 1.0);
  }

  stopAll() {
    this.stopHum();
    this.stopDrips();
    if (this.staticGain) {
      this.staticGain.gain.setValueAtTime(0.0, this.ctx ? this.ctx.currentTime : 0);
    }
  }
}

// Distortion helper function
function makeDistortionCurve(amount) {
  const k = typeof amount === 'number' ? amount : 50;
  const n_samples = 44100;
  const curve = new Float32Array(n_samples);
  const deg = Math.PI / 180;
  for (let i = 0; i < n_samples; ++i) {
    const x = (i * 2) / n_samples - 1;
    curve[i] = ((3 + k) * x * 20 * deg) / (Math.PI + k * Math.abs(x));
  }
  return curve;
}

const soundManager = new SoundManager();
export default soundManager;
