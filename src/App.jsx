import { useState, useEffect } from 'react';
import { Play, RotateCcw, LogOut, Lock, Unlock, Volume2, VolumeX, Key, Battery, Shield } from 'lucide-react';
import { LEVELS } from './LevelConfigs';
import GameEngine from './GameEngine';
import soundManager from './SoundManager';
import './App.css';

function App() {
  const [gameState, setGameState] = useState('MENU'); // MENU, PLAYING, PAUSED, GAME_OVER, VICTORY
  const [levelIndex, setLevelIndex] = useState(0);
  const [maxUnlockedLevel, setMaxUnlockedLevel] = useState(0);
  
  // Game states managed between React and GameEngine
  const [flashlightOn, setFlashlightOn] = useState(true);
  const [flashlightBattery, setFlashlightBattery] = useState(100);
  const [sprintStamina, setSprintStamina] = useState(100);
  const [keysCollected, setKeysCollected] = useState(0);
  const [health, setHealth] = useState(100);
  
  // Audio volume toggle
  const [muted, setMuted] = useState(false);

  // Interaction prompt
  const [interactPrompt, setInteractPrompt] = useState(null);

  // Timer for the levels
  const [levelTimer, setLevelTimer] = useState(0);
  const [timerActive, setTimerActive] = useState(false);

  // Load unlocked level from local storage on startup
  useEffect(() => {
    const saved = localStorage.getItem('liminal_max_unlocked');
    if (saved) {
      setMaxUnlockedLevel(parseInt(saved, 10));
    }
  }, []);

  // Level Timer Tick
  useEffect(() => {
    let interval = null;
    if (timerActive && gameState === 'PLAYING') {
      interval = setInterval(() => {
        setLevelTimer(t => t + 1);
      }, 1000);
    } else {
      clearInterval(interval);
    }
    return () => clearInterval(interval);
  }, [timerActive, gameState]);

  // Flashlight click sound trigger when user presses 'F' or left clicks
  useEffect(() => {
    const handleFlashlightToggleKey = (e) => {
      if (gameState !== 'PLAYING') return;
      if (e.key.toLowerCase() === 'f') {
        if (flashlightBattery > 0) {
          setFlashlightOn(prev => {
            const next = !prev;
            soundManager.playClick();
            return next;
          });
        }
      }
      
      // Escape key to pause
      if (e.key === 'Escape') {
        setGameState('PAUSED');
      }
    };

    const handleMouseClick = (e) => {
      if (gameState !== 'PLAYING') return;
      // Toggle flashlight on left click
      if (e.button === 0 && document.pointerLockElement) {
        if (flashlightBattery > 0) {
          setFlashlightOn(prev => {
            const next = !prev;
            soundManager.playClick();
            return next;
          });
        }
      }
    };

    window.addEventListener('keydown', handleFlashlightToggleKey);
    window.addEventListener('mousedown', handleMouseClick);
    return () => {
      window.removeEventListener('keydown', handleFlashlightToggleKey);
      window.removeEventListener('mousedown', handleMouseClick);
    };
  }, [gameState, flashlightBattery]);

  // Control Audio Volume muting
  const toggleMuted = () => {
    const newMuted = !muted;
    setMuted(newMuted);
    if (soundManager.masterGain) {
      soundManager.masterGain.gain.setValueAtTime(newMuted ? 0.0 : 0.25, soundManager.ctx.currentTime);
    }
  };

  // Start a Level
  const startLevel = (index) => {
    setLevelIndex(index);
    setFlashlightOn(true);
    setFlashlightBattery(100);
    setSprintStamina(100);
    setKeysCollected(0);
    setHealth(100);
    setInteractPrompt(null);
    setLevelTimer(0);
    setTimerActive(true);
    
    // Play menu select sound
    soundManager.playClick();
    
    setGameState('PLAYING');
  };

  const handleLevelWin = () => {
    setTimerActive(false);
    
    // Unlock next level
    const nextIdx = levelIndex + 1;
    if (nextIdx < LEVELS.length) {
      if (nextIdx > maxUnlockedLevel) {
        setMaxUnlockedLevel(nextIdx);
        localStorage.setItem('liminal_max_unlocked', nextIdx.toString());
      }
    }
    
    setGameState('VICTORY');
  };

  const handleLevelLose = () => {
    setTimerActive(false);
    setGameState('GAME_OVER');
  };

  const formatTime = (secs) => {
    const m = Math.floor(secs / 60);
    const s = secs % 60;
    return `${m}:${s < 10 ? '0' : ''}${s}`;
  };

  const activeLevel = LEVELS[levelIndex];

  return (
    <div className="game-wrapper crt">
      {/* Visual CRT Scanline filter */}
      <div className="vignette"></div>
      <div className="scanlines"></div>
      
      {/* 3D Game Canvas Area */}
      {gameState === 'PLAYING' && (
        <div className="canvas-container">
          <GameEngine
            levelIndex={levelIndex}
            isPaused={false}
            flashlightOn={flashlightOn}
            setFlashlightOn={setFlashlightOn}
            flashlightBattery={flashlightBattery}
            setFlashlightBattery={setFlashlightBattery}
            sprintStamina={sprintStamina}
            setSprintStamina={setSprintStamina}
            keysCollected={keysCollected}
            setKeysCollected={setKeysCollected}
            health={health}
            setHealth={setHealth}
            onLevelWin={handleLevelWin}
            onLevelLose={handleLevelLose}
            onInteractPrompt={setInteractPrompt}
            onClosePrompt={() => setInteractPrompt(null)}
          />

          {/* Gameplay HUD */}
          <div className="hud-container">
            {/* Top Left: Level Indicator */}
            <div className="hud-panel level-info">
              <div className="level-label">STATION:</div>
              <div className="level-val glow-text">{activeLevel.name}</div>
              <div className="timer-val">{formatTime(levelTimer)}</div>
            </div>

            {/* Top Right: Sound Control */}
            <button className="hud-btn mute-btn" onClick={toggleMuted} title="Toggle Audio">
              {muted ? <VolumeX size={18} /> : <Volume2 size={18} />}
            </button>

            {/* Bottom Left: Vitals & Stamina */}
            <div className="hud-panel vitals-panel">
              <div className="hud-row">
                <Shield size={16} className="hud-icon health-icon" />
                <div className="hud-label">VITALS:</div>
                <div className="hud-progress-bg">
                  <div 
                    className="hud-progress-fill health-fill"
                    style={{ width: `${health}%` }}
                  ></div>
                </div>
                <div className="hud-percent">{Math.round(health)}%</div>
              </div>
              <div className="hud-row">
                <span className="stamina-icon-letter">S</span>
                <div className="hud-label">STAMINA:</div>
                <div className="hud-progress-bg">
                  <div 
                    className="hud-progress-fill stamina-fill"
                    style={{ width: `${sprintStamina}%` }}
                  ></div>
                </div>
                <div className="hud-percent">{Math.round(sprintStamina)}%</div>
              </div>
            </div>

            {/* Bottom Right: Keycards & Flashlight */}
            <div className="hud-panel items-panel">
              {activeLevel.keysRequired > 0 && (
                <div className="hud-row keycard-row">
                  <Key size={16} className="hud-icon key-icon" />
                  <div className="hud-label">KEYS:</div>
                  <div className="keycard-dots">
                    {Array.from({ length: activeLevel.keysRequired }).map((_, i) => (
                      <span 
                        key={i} 
                        className={`key-dot ${i < keysCollected ? 'collected' : ''}`}
                      >
                        {i < keysCollected ? "▣" : "▢"}
                      </span>
                    ))}
                  </div>
                </div>
              )}
              <div className="hud-row">
                <Battery size={16} className={`hud-icon battery-icon ${flashlightBattery < 20 ? 'battery-low-flash' : ''}`} />
                <div className="hud-label">POWER:</div>
                <div className="hud-progress-bg">
                  <div 
                    className={`hud-progress-fill battery-fill ${flashlightBattery < 20 ? 'battery-low' : ''}`}
                    style={{ width: `${flashlightBattery}%` }}
                  ></div>
                </div>
                <div className="hud-percent">{Math.round(flashlightBattery)}%</div>
              </div>
            </div>

            {/* Proximity / Ghost Static Alert Overlay */}
            {flashlightBattery < 20 && flashlightOn && (
              <div className="hud-alert battery-alert glitch-text" data-text="WARNING: LOW BATTERY">
                WARNING: LOW BATTERY
              </div>
            )}

            {/* Center Interact Prompt */}
            {interactPrompt && (
              <div className="interact-prompt glow-text animate-pulse">
                {interactPrompt}
              </div>
            )}

            {/* In-game Pause Hint */}
            <div className="pause-hint">Press [ESC] to Pause</div>
          </div>
        </div>
      )}

      {/* Main Menu Overlay */}
      {gameState === 'MENU' && (
        <div className="menu-container">
          <header className="menu-header">
            <h1 className="menu-title glitch-text" data-text="LIMITS OF SPACE">LIMITS OF SPACE</h1>
            <div className="menu-status glow-text">REALITY SLIP DETECTED • ANALOG HORROR DESKTOP</div>
          </header>

          <main className="menu-grid">
            {/* Left Column: Instructions */}
            <section className="menu-panel instructions">
              <h2 className="panel-title">SYSTEM INSTRUCTIONS</h2>
              <ul className="instruction-list">
                <li>Mouse: Look 360 degrees (requires Pointer Lock)</li>
                <li>W, A, S, D: Navigate coordinates</li>
                <li>SHIFT: Sprint (drains stamina)</li>
                <li>LEFT-CLICK / F: Toggle light beam</li>
                <li>Objective: Find exit portal (E). Certain levels require locating yellow/blue keycards (K) to disengage security locks.</li>
                <li>Industrial steam leaks (H) will drain vitals. Find valves (V) to relieve pressure.</li>
              </ul>
              
              <div className="audio-control-row">
                <button className="menu-btn volume-btn" onClick={toggleMuted}>
                  {muted ? <VolumeX size={20} /> : <Volume2 size={20} />}
                  <span>{muted ? "MUTED" : "SOUNDS ENABLED"}</span>
                </button>
              </div>
            </section>

            {/* Right Column: Level Selector */}
            <section className="menu-panel levels-panel">
              <h2 className="panel-title">LEVEL ACCESS</h2>
              <div className="level-buttons-grid">
                {LEVELS.map((lvl, index) => {
                  const isUnlocked = index <= maxUnlockedLevel;
                  return (
                    <button
                      key={index}
                      className={`level-select-btn ${isUnlocked ? 'unlocked' : 'locked'}`}
                      disabled={!isUnlocked}
                      onClick={() => startLevel(index)}
                    >
                      <div className="level-select-num">{index + 1}</div>
                      <div className="level-select-meta">
                        <div className="level-select-name">{lvl.name.split(': ')[1]}</div>
                        <div className="level-select-status">
                          {isUnlocked ? (
                            <span className="unlocked-text"><Unlock size={10} /> AVAILABLE</span>
                          ) : (
                            <span className="locked-text"><Lock size={10} /> RESTRICTED</span>
                          )}
                        </div>
                      </div>
                    </button>
                  );
                })}
              </div>
            </section>
          </main>

          <footer className="menu-footer">
            <div className="version-info">V.3.5-FLASH-ENGINE • GEMINI ADVANCED CODING</div>
          </footer>
        </div>
      )}

      {/* Paused Screen */}
      {gameState === 'PAUSED' && (
        <div className="menu-overlay-screen paused-screen">
          <div className="overlay-box">
            <h2 className="glitch-text" data-text="GAME PAUSED">GAME PAUSED</h2>
            <p>Reality sequence suspended.</p>
            <div className="overlay-btn-group">
              <button className="menu-btn play-btn" onClick={() => setGameState('PLAYING')}>
                <Play size={18} />
                <span>RESUME SEQUENCE</span>
              </button>
              <button className="menu-btn restart-btn" onClick={() => startLevel(levelIndex)}>
                <RotateCcw size={18} />
                <span>RESTART LEVEL</span>
              </button>
              <button className="menu-btn menu-exit-btn" onClick={() => { soundManager.stopAll(); setGameState('MENU'); }}>
                <LogOut size={18} />
                <span>EXIT TO MAIN MENU</span>
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Game Over Screen */}
      {gameState === 'GAME_OVER' && (
        <div className="menu-overlay-screen gameover-screen">
          <div className="overlay-box">
            <h2 className="glitch-text text-danger" data-text="CONNECTION LOST">CONNECTION LOST</h2>
            <p className="text-danger">Subject failed to maintain connection to physical reality.</p>
            <div className="stats-readout">
              <div>STATION: {activeLevel.name}</div>
              <div>ELAPSED TIME: {formatTime(levelTimer)}</div>
              <div>KEYCARDS ACQUIRED: {keysCollected} / {activeLevel.keysRequired}</div>
            </div>
            <div className="overlay-btn-group">
              <button className="menu-btn restart-btn danger" onClick={() => startLevel(levelIndex)}>
                <RotateCcw size={18} />
                <span>RECONNECT (RETRY)</span>
              </button>
              <button className="menu-btn menu-exit-btn" onClick={() => setGameState('MENU')}>
                <LogOut size={18} />
                <span>TERMINATE ENTRANCE</span>
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Victory Screen */}
      {gameState === 'VICTORY' && (
        <div className="menu-overlay-screen victory-screen">
          <div className="overlay-box">
            <h2 className="glitch-text text-success" data-text="LEVEL CLEARED">PORTAL ACCESSED</h2>
            <p className="text-success">Escape sequence initialized. Transitioning to next sector.</p>
            <div className="stats-readout success">
              <div>STATION COMPLETED: {activeLevel.name}</div>
              <div>ELAPSED TIME: {formatTime(levelTimer)}</div>
              <div>BATTERY SURVIVED: {Math.round(flashlightBattery)}%</div>
            </div>
            <div className="overlay-btn-group">
              {levelIndex + 1 < LEVELS.length ? (
                <button className="menu-btn play-btn success" onClick={() => startLevel(levelIndex + 1)}>
                  <Play size={18} />
                  <span>PROCEED TO LEVEL {levelIndex + 2}</span>
                </button>
              ) : (
                <div className="victory-final-message glow-text">
                  CONGRATULATIONS. YOU HAVE ESCAPED THE LIMITS OF SPACE.
                </div>
              )}
              <button className="menu-btn menu-exit-btn" onClick={() => setGameState('MENU')}>
                <LogOut size={18} />
                <span>RETURN TO TERMINAL</span>
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

export default App;
