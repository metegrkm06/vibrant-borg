import React, { useEffect, useRef, useState } from 'react';
import * as THREE from 'three';
import { LEVELS } from './LevelConfigs';
import soundManager from './SoundManager';

const CELL_SIZE = 4.0;
const WALL_HEIGHT = 4.5;
const EYE_HEIGHT = 1.6;

export default function GameEngine({
  levelIndex,
  isPaused,
  flashlightOn,
  setFlashlightOn,
  flashlightBattery,
  setFlashlightBattery,
  sprintStamina,
  setSprintStamina,
  keysCollected,
  setKeysCollected,
  health,
  setHealth,
  onLevelWin,
  onLevelLose,
  onInteractPrompt,
  onClosePrompt
}) {
  const containerRef = useRef(null);
  const canvasRef = useRef(null);
  
  // Internal game references for the loop
  const stateRef = useRef({
    levelIndex,
    isPaused,
    flashlightOn,
    flashlightBattery,
    sprintStamina,
    keysCollected,
    health,
    
    // Player movement
    playerPos: new THREE.Vector3(),
    yaw: 0,
    pitch: 0,
    velocity: new THREE.Vector3(),
    keys: {},
    isSprinting: false,
    inWater: false,
    
    // Level items
    items: [], // keycards, batteries, valves
    walls: [], // array of AABBs for collision
    steamHazards: [], // steam positions
    valves: [], // valves
    exitDoor: null,
    exitPos: new THREE.Vector3(),
    
    // Entities
    monster: null,
    monsterPos: new THREE.Vector3(),
    monsterPath: [],
    monsterLastPathTime: 0,
    
    // Valve status
    steamActive: true,
    
    // Pointer Lock
    isLocked: false
  });

  // State to reflect lock screen inside React
  const [isLockedState, setIsLockedState] = useState(false);

  // Synchronize React state changes with the ref for the render loop
  useEffect(() => {
    stateRef.current.levelIndex = levelIndex;
    stateRef.current.isPaused = isPaused;
    stateRef.current.flashlightOn = flashlightOn;
  }, [levelIndex, isPaused, flashlightOn]);

  useEffect(() => {
    stateRef.current.flashlightBattery = flashlightBattery;
  }, [flashlightBattery]);

  useEffect(() => {
    stateRef.current.sprintStamina = sprintStamina;
  }, [sprintStamina]);

  useEffect(() => {
    stateRef.current.keysCollected = keysCollected;
  }, [keysCollected]);

  useEffect(() => {
    stateRef.current.health = health;
  }, [health]);

  // Procedural canvas textures
  const createCanvasTexture = (theme, type, colorHex) => {
    const canvas = document.createElement('canvas');
    canvas.width = 512;
    canvas.height = 512;
    const ctx = canvas.getContext('2d');
    ctx.fillStyle = colorHex;
    ctx.fillRect(0, 0, 512, 512);

    if (theme === 'backrooms') {
      if (type === 'wall') {
        // Yellow wallpaper pattern (vertical stripes and subtle grunge)
        ctx.fillStyle = 'rgba(0,0,0,0.04)';
        for (let i = 0; i < 512; i += 32) {
          ctx.fillRect(i, 0, 4, 512);
        }
        // Micro dots
        ctx.fillStyle = 'rgba(0,0,0,0.06)';
        for (let i = 0; i < 2000; i++) {
          ctx.fillRect(Math.random() * 512, Math.random() * 512, 2, 2);
        }
      } else if (type === 'floor') {
        // Dirty damp carpet texture
        ctx.fillStyle = 'rgba(0,0,0,0.1)';
        for (let i = 0; i < 8000; i++) {
          ctx.fillRect(Math.random() * 512, Math.random() * 512, 3, 3);
        }
        // Subtle water/damp patches
        ctx.fillStyle = 'rgba(60,40,20,0.15)';
        for (let i = 0; i < 8; i++) {
          ctx.beginPath();
          ctx.arc(Math.random() * 512, Math.random() * 512, 40 + Math.random() * 60, 0, Math.PI * 2);
          ctx.fill();
        }
      } else if (type === 'ceiling') {
        // Ceiling tiles grid
        ctx.strokeStyle = '#aaaaaa';
        ctx.lineWidth = 4;
        ctx.strokeRect(0, 0, 512, 512);
        ctx.strokeRect(256, 0, 256, 512);
        ctx.strokeRect(0, 256, 512, 256);
        // Acoustic dots
        ctx.fillStyle = 'rgba(0,0,0,0.15)';
        for (let i = 0; i < 3000; i++) {
          ctx.fillRect(Math.random() * 512, Math.random() * 512, 2, 2);
        }
      }
    } else if (theme === 'pools') {
      if (type === 'wall' || type === 'floor') {
        // White tiles grid
        ctx.strokeStyle = '#b0d5e8';
        ctx.lineWidth = 2;
        ctx.strokeRect(0, 0, 512, 512);
        // Draw smaller grid tiles
        for (let i = 0; i < 512; i += 64) {
          ctx.beginPath();
          ctx.moveTo(i, 0); ctx.lineTo(i, 512);
          ctx.moveTo(0, i); ctx.lineTo(512, i);
          ctx.stroke();
        }
        // Add subtle water reflections
        ctx.fillStyle = 'rgba(255,255,255,0.1)';
        ctx.fillRect(0, 0, 512, 512);
      }
    } else if (theme === 'office' || theme === 'cubicles') {
      if (type === 'wall') {
        // Office partition fabric pattern
        ctx.strokeStyle = 'rgba(0,0,0,0.05)';
        for (let i = 0; i < 512; i += 8) {
          ctx.beginPath();
          ctx.moveTo(i, 0); ctx.lineTo(i, 512);
          ctx.moveTo(0, i); ctx.lineTo(512, i);
          ctx.stroke();
        }
      } else if (type === 'floor') {
        // Grey carpet tiles
        ctx.strokeStyle = 'rgba(255,255,255,0.05)';
        ctx.strokeRect(0, 0, 256, 256);
        ctx.strokeRect(256, 256, 256, 256);
        // Noise
        ctx.fillStyle = 'rgba(0,0,0,0.15)';
        for (let i = 0; i < 4000; i++) {
          ctx.fillRect(Math.random() * 512, Math.random() * 512, 2, 2);
        }
      }
    } else if (theme === 'industrial' || theme === 'boiler' || theme === 'sublevel') {
      if (type === 'wall') {
        // Rough dark concrete blocks
        ctx.fillStyle = 'rgba(0,0,0,0.2)';
        for (let i = 0; i < 512; i += 128) {
          ctx.beginPath();
          ctx.moveTo(i, 0); ctx.lineTo(i, 512);
          ctx.moveTo(0, i); ctx.lineTo(512, i);
          ctx.stroke();
        }
        // Grunge and rust
        ctx.fillStyle = 'rgba(80,40,20,0.1)';
        for (let i = 0; i < 5; i++) {
          ctx.fillRect(Math.random() * 512, Math.random() * 100, 40 + Math.random() * 100, 300);
        }
        // Concrete grain noise
        ctx.fillStyle = 'rgba(0,0,0,0.15)';
        for (let i = 0; i < 5000; i++) {
          ctx.fillRect(Math.random() * 512, Math.random() * 512, 3, 3);
        }
      } else if (type === 'floor') {
        // Metal grating floor
        ctx.fillStyle = '#111';
        ctx.fillRect(0, 0, 512, 512);
        ctx.strokeStyle = '#444';
        ctx.lineWidth = 4;
        for (let i = 0; i < 512; i += 16) {
          ctx.beginPath();
          ctx.moveTo(i, 0); ctx.lineTo(i, 512);
          ctx.stroke();
        }
      }
    } else if (theme === 'suburbia') {
      if (type === 'wall') {
        // Horizontal wood siding for houses
        ctx.fillStyle = '#eee';
        ctx.fillRect(0, 0, 512, 512);
        ctx.fillStyle = 'rgba(0,0,0,0.1)';
        for (let i = 0; i < 512; i += 24) {
          ctx.fillRect(0, i, 512, 3);
        }
      } else if (type === 'floor') {
        // Green artificial turf grass
        ctx.fillStyle = 'rgba(0,0,0,0.2)';
        for (let i = 0; i < 10000; i++) {
          ctx.fillRect(Math.random() * 512, Math.random() * 512, 2, 4);
        }
      }
    } else {
      // Default plain noise
      ctx.fillStyle = 'rgba(0,0,0,0.1)';
      for (let i = 0; i < 4000; i++) {
        ctx.fillRect(Math.random() * 512, Math.random() * 512, 2, 2);
      }
    }

    const texture = new THREE.CanvasTexture(canvas);
    texture.wrapS = THREE.RepeatWrapping;
    texture.wrapT = THREE.RepeatWrapping;
    texture.repeat.set(1, 1);
    return texture;
  };

  // BFS Pathfinding for the Monster
  const findPathBFS = (grid, startX, startZ, targetX, targetZ) => {
    const queue = [[startX, startZ, []]];
    const visited = new Set();
    visited.add(`${startX},${startZ}`);

    const dir = [[1,0], [-1,0], [0,1], [0,-1]];
    const gridH = grid.length;
    const gridW = grid[0].length;

    while (queue.length > 0) {
      const [currX, currZ, path] = queue.shift();

      if (currX === targetX && currZ === targetZ) {
        return path;
      }

      for (let [dx, dz] of dir) {
        const nextX = currX + dx;
        const nextZ = currZ + dz;
        
        if (nextX >= 0 && nextX < gridW && nextZ >= 0 && nextZ < gridH) {
          const cell = grid[nextZ][nextX];
          // Entity can pass through anything except walls ('1')
          if (cell !== '1' && !visited.has(`${nextX},${nextZ}`)) {
            visited.add(`${nextX},${nextZ}`);
            queue.push([nextX, nextZ, [...path, { x: nextX, z: nextZ }]]);
          }
        }
      }
    }
    return []; // No path found
  };

  // Main game setup and loop
  useEffect(() => {
    const config = LEVELS[levelIndex];
    if (!config) return;

    // Initialize state
    const state = stateRef.current;
    state.levelIndex = levelIndex;
    state.keysCollected = 0;
    setKeysCollected(0);
    state.health = 100;
    setHealth(100);
    state.steamActive = true;
    state.items = [];
    state.walls = [];
    state.steamHazards = [];
    state.valves = [];
    state.inWater = false;
    state.monster = null;
    state.monsterPath = [];
    state.monsterLastPathTime = 0;

    // Sound initialization
    soundManager.stopAll();
    soundManager.startHum(levelIndex === 6 ? 0.0 : 1.0); // No hum in level 7 (Lights out)
    if (config.theme === 'pools') {
      soundManager.startDrips();
    }

    // Three.js scene setup
    const scene = new THREE.Scene();
    scene.background = new THREE.Color(config.fogColor);
    scene.fog = new THREE.FogExp2(config.fogColor, config.fogDensity);

    const aspect = containerRef.current.clientWidth / containerRef.current.clientHeight;
    const camera = new THREE.PerspectiveCamera(70, aspect, 0.1, 100);
    camera.rotation.order = "YXZ";

    const renderer = new THREE.WebGLRenderer({ canvas: canvasRef.current, antialias: true, powerPreference: "high-performance" });
    renderer.setSize(containerRef.current.clientWidth, containerRef.current.clientHeight);
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    renderer.shadowMap.enabled = true;
    renderer.shadowMap.type = THREE.PCFSoftShadowMap;

    // Procedural textures
    const wallTex = createCanvasTexture(config.theme, 'wall', config.wallColor);
    const floorTex = createCanvasTexture(config.theme, 'floor', config.floorColor);
    const ceilingTex = createCanvasTexture(config.theme, 'ceiling', config.ceilingColor);

    // Grid details
    const grid = config.grid;
    const gridH = grid.length;
    const gridW = grid[0].length;

    // Materials
    const wallMat = new THREE.MeshStandardMaterial({ 
      map: wallTex, 
      roughness: 0.8,
      metalness: 0.1
    });
    
    // Add bump/roughness to walls for pool/industrial
    if (config.theme === 'pools') {
      wallMat.roughness = 0.1;
      wallMat.metalness = 0.1;
    } else if (config.theme === 'industrial' || config.theme === 'boiler' || config.theme === 'sublevel') {
      wallMat.roughness = 0.9;
      wallMat.metalness = 0.3;
    }

    const floorMat = new THREE.MeshStandardMaterial({ 
      map: floorTex, 
      roughness: config.theme === 'pools' ? 0.1 : 0.9, 
      metalness: config.theme === 'pools' ? 0.3 : 0.0 
    });
    
    const ceilingMat = new THREE.MeshStandardMaterial({ 
      map: ceilingTex, 
      roughness: 0.9, 
      metalness: 0.1 
    });

    const boxGeo = new THREE.BoxGeometry(CELL_SIZE, WALL_HEIGHT, CELL_SIZE);
    const planeGeo = new THREE.PlaneGeometry(CELL_SIZE, CELL_SIZE);

    // Build the maze
    for (let z = 0; z < gridH; z++) {
      for (let x = 0; x < gridW; x++) {
        const cell = grid[z][x];
        const posX = x * CELL_SIZE;
        const posZ = z * CELL_SIZE;

        // Floor (cell by cell)
        const floorMesh = new THREE.Mesh(planeGeo, floorMat);
        floorMesh.rotation.x = -Math.PI / 2;
        floorMesh.position.set(posX, 0, posZ);
        floorMesh.receiveShadow = true;
        scene.add(floorMesh);

        // Ceiling (cell by cell)
        if (config.theme !== 'suburbia') { // Suburbia has no ceiling (outdoor night)
          const ceilingMesh = new THREE.Mesh(planeGeo, ceilingMat);
          ceilingMesh.rotation.x = Math.PI / 2;
          ceilingMesh.position.set(posX, WALL_HEIGHT, posZ);
          ceilingMesh.receiveShadow = true;
          scene.add(ceilingMesh);
        }

        if (cell === '1') {
          // Wall
          const wallMesh = new THREE.Mesh(boxGeo, wallMat);
          wallMesh.position.set(posX, WALL_HEIGHT / 2, posZ);
          wallMesh.castShadow = true;
          wallMesh.receiveShadow = true;
          scene.add(wallMesh);
          
          // Collision box
          state.walls.push({
            minX: posX - CELL_SIZE / 2,
            maxX: posX + CELL_SIZE / 2,
            minZ: posZ - CELL_SIZE / 2,
            maxZ: posZ + CELL_SIZE / 2
          });
        } 
        else if (cell === 'P') {
          // Player spawn
          state.playerPos.set(posX, EYE_HEIGHT, posZ);
          camera.position.copy(state.playerPos);
          state.yaw = 0;
          state.pitch = 0;
        } 
        else if (cell === 'E') {
          // Exit door
          state.exitPos.set(posX, EYE_HEIGHT, posZ);
          
          // Render exit door mesh (Elevator doors or glass portal)
          const doorGroup = new THREE.Group();
          const doorGeo = new THREE.BoxGeometry(0.2, WALL_HEIGHT * 0.8, CELL_SIZE * 0.8);
          const doorMat = new THREE.MeshStandardMaterial({ 
            color: config.theme === 'threshold' ? 0xffffff : 0x444444, 
            roughness: 0.2, 
            metalness: 0.9,
            emissive: config.theme === 'threshold' ? 0xffffff : 0x000000 
          });
          const door = new THREE.Mesh(doorGeo, doorMat);
          door.position.set(posX, WALL_HEIGHT * 0.4, posZ);
          doorGroup.add(door);
          
          // Glowing EXIT sign above door
          if (config.theme !== 'threshold') {
            const signGeo = new THREE.BoxGeometry(0.1, 0.4, 0.8);
            const signMat = new THREE.MeshBasicMaterial({ color: 0x00ff00 });
            const sign = new THREE.Mesh(signGeo, signMat);
            sign.position.set(posX - 0.15, WALL_HEIGHT * 0.85, posZ);
            doorGroup.add(sign);
          }

          scene.add(doorGroup);
          state.exitDoor = doorGroup;
        } 
        else if (cell === 'K') {
          // Keycard
          const cardGeo = new THREE.BoxGeometry(0.1, 0.5, 0.8);
          const cardMat = new THREE.MeshStandardMaterial({ 
            color: 0x0088ff, 
            roughness: 0.1, 
            metalness: 0.8,
            emissive: 0x0033aa 
          });
          const card = new THREE.Mesh(cardGeo, cardMat);
          card.position.set(posX, 0.8, posZ);
          scene.add(card);
          
          // Soft point light from keycard
          const cardLight = new THREE.PointLight(0x00aaff, 1, 3);
          cardLight.position.set(posX, 0.8, posZ);
          scene.add(cardLight);

          state.items.push({
            type: 'keycard',
            mesh: card,
            light: cardLight,
            pos: new THREE.Vector3(posX, 0.8, posZ)
          });
        } 
        else if (cell === 'B') {
          // Battery
          const batGeo = new THREE.CylinderGeometry(0.15, 0.15, 0.5, 8);
          const batMat = new THREE.MeshStandardMaterial({ 
            color: 0xffcc00, 
            roughness: 0.5, 
            metalness: 0.8 
          });
          const batteryMesh = new THREE.Mesh(batGeo, batMat);
          batteryMesh.rotation.x = Math.PI / 4;
          batteryMesh.position.set(posX, 0.8, posZ);
          scene.add(batteryMesh);

          const batLight = new THREE.PointLight(0xffaa00, 0.8, 3);
          batLight.position.set(posX, 0.8, posZ);
          scene.add(batLight);

          state.items.push({
            type: 'battery',
            mesh: batteryMesh,
            light: batLight,
            pos: new THREE.Vector3(posX, 0.8, posZ)
          });
        } 
        else if (cell === 'L') {
          // Fluorescent light source
          const lightMeshGeo = new THREE.BoxGeometry(1.5, 0.1, 0.3);
          const lightMeshMat = new THREE.MeshBasicMaterial({ color: 0xffffff });
          const fixture = new THREE.Mesh(lightMeshGeo, lightMeshMat);
          fixture.position.set(posX, WALL_HEIGHT - 0.05, posZ);
          scene.add(fixture);

          const roomLight = new THREE.PointLight(
            new THREE.Color(config.lightColor), 
            config.theme === 'pitchblack' ? 0.0 : 1.2, 
            15
          );
          roomLight.position.set(posX, WALL_HEIGHT - 0.3, posZ);
          roomLight.castShadow = (config.theme !== 'pitchblack' && levelIndex < 5); // Disable shadows on big levels for perf
          scene.add(roomLight);
          
          // Light flicker config
          state.items.push({
            type: 'light',
            light: roomLight,
            fixture: fixture,
            baseIntensity: roomLight.intensity,
            flickerTimer: Math.random() * 5
          });
        }
        else if (cell === 'W') {
          // Water (Level 4 Poolrooms)
          const waterGeo = new THREE.BoxGeometry(CELL_SIZE, 0.4, CELL_SIZE);
          const waterMat = new THREE.MeshStandardMaterial({
            color: 0x4dd0e1,
            transparent: true,
            opacity: 0.6,
            roughness: 0.1,
            metalness: 0.8
          });
          const water = new THREE.Mesh(waterGeo, waterMat);
          water.position.set(posX, 0.1, posZ);
          scene.add(water);
          
          // Mark this cell as water in state
          state.items.push({
            type: 'water',
            pos: new THREE.Vector3(posX, 0, posZ)
          });
        }
        else if (cell === 'V') {
          // Valve
          const valveGroup = new THREE.Group();
          
          // Stem
          const stem = new THREE.Mesh(
            new THREE.CylinderGeometry(0.05, 0.05, 0.4, 8),
            new THREE.MeshStandardMaterial({ color: 0x333333, metalness: 0.8 })
          );
          stem.rotation.x = Math.PI / 2;
          stem.position.set(posX, 1.2, posZ - CELL_SIZE/2.2);
          valveGroup.add(stem);

          // Wheel
          const wheel = new THREE.Mesh(
            new THREE.TorusGeometry(0.3, 0.05, 8, 24),
            new THREE.MeshStandardMaterial({ color: 0xaa2222, metalness: 0.9, roughness: 0.4 })
          );
          wheel.position.set(posX, 1.2, posZ - CELL_SIZE/2.2 + 0.2);
          valveGroup.add(wheel);

          scene.add(valveGroup);

          state.valves.push({
            mesh: wheel,
            pos: new THREE.Vector3(posX, 1.2, posZ),
            turned: false
          });
        }
        else if (cell === 'H') {
          // Steam Hazard
          const steamGeo = new THREE.BoxGeometry(1.0, WALL_HEIGHT, 1.0);
          const steamMat = new THREE.MeshBasicMaterial({ 
            color: 0xffffff, 
            transparent: true, 
            opacity: 0.35, 
            wireframe: true 
          });
          const steamMesh = new THREE.Mesh(steamGeo, steamMat);
          steamMesh.position.set(posX, WALL_HEIGHT/2, posZ);
          scene.add(steamMesh);

          // Red light warning for steam leak
          const warningLight = new THREE.PointLight(0xff3300, 1.5, 6);
          warningLight.position.set(posX, 1.5, posZ);
          scene.add(warningLight);

          state.steamHazards.push({
            mesh: steamMesh,
            light: warningLight,
            pos: new THREE.Vector3(posX, 0.5, posZ)
          });
        }
        else if (cell === 'M') {
          // Monster Spawn position
          state.monsterPos.set(posX, 0, posZ);
        }
      }
    }

    // Add ambient lighting
    const ambientLight = new THREE.AmbientLight(
      new THREE.Color(config.ambientColor), 
      config.theme === 'pitchblack' ? 0.0 : 0.25
    );
    scene.add(ambientLight);

    // Initialize Flashlight (SpotLight attached to camera)
    const flashlight = new THREE.SpotLight(0xffffff, 0, 18, Math.PI / 6, 0.5, 1.2);
    flashlight.castShadow = true;
    flashlight.shadow.mapSize.width = 1024;
    flashlight.shadow.mapSize.height = 1024;
    flashlight.shadow.camera.near = 0.5;
    flashlight.shadow.camera.far = 20;
    
    // Add target slightly forward
    const flashlightTarget = new THREE.Object3D();
    flashlightTarget.position.set(0, 0, -1);
    camera.add(flashlightTarget);
    flashlight.target = flashlightTarget;

    camera.add(flashlight);
    scene.add(camera);

    // Build creepy entity (shadow monster)
    if (config.hasMonster) {
      const monsterGroup = new THREE.Group();
      
      // Black body ball
      const bodyGeo = new THREE.SphereGeometry(0.6, 8, 8);
      const bodyMat = new THREE.MeshBasicMaterial({ color: 0x080808 });
      const body = new THREE.Mesh(bodyGeo, bodyMat);
      body.position.y = 1.4;
      monsterGroup.add(body);
      
      // Glowing red eyes
      const eyeGeo = new THREE.SphereGeometry(0.07, 8, 8);
      const eyeMat = new THREE.MeshBasicMaterial({ color: 0xff0000 });
      
      const leftEye = new THREE.Mesh(eyeGeo, eyeMat);
      leftEye.position.set(-0.2, 1.5, -0.5);
      
      const rightEye = new THREE.Mesh(eyeGeo, eyeMat);
      rightEye.position.set(0.2, 1.5, -0.5);
      
      monsterGroup.add(leftEye);
      monsterGroup.add(rightEye);

      // Red spotlight glowing in front of the monster (creepy view cone)
      const monsterEyeLight = new THREE.PointLight(0xff0000, 1.2, 4);
      monsterEyeLight.position.set(0, 1.5, -0.4);
      monsterGroup.add(monsterEyeLight);

      // Procedural stick limbs wiggling
      const limbMat = new THREE.MeshBasicMaterial({ color: 0x050505 });
      const limbGeo = new THREE.CylinderGeometry(0.03, 0.03, 1.8, 4);
      
      const limbs = [];
      for (let i = 0; i < 4; i++) {
        const limb = new THREE.Mesh(limbGeo, limbMat);
        limb.position.y = 0.8;
        // Position offset
        const theta = (i / 4) * Math.PI * 2;
        limb.position.x = Math.cos(theta) * 0.4;
        limb.position.z = Math.sin(theta) * 0.4;
        
        monsterGroup.add(limb);
        limbs.push(limb);
      }

      monsterGroup.position.copy(state.monsterPos);
      scene.add(monsterGroup);
      
      state.monster = monsterGroup;
      state.monster.userData = { limbs, basePos: state.monsterPos.clone() };
    }

    // Input handlers
    const onKeyDown = (e) => {
      const key = e.key.toLowerCase();
      state.keys[key] = true;

      // Sprint toggle
      if (e.key === 'Shift') {
        state.isSprinting = true;
      }

      // Interaction key 'e'
      if (key === 'e') {
        handleInteraction();
      }
    };

    const onKeyUp = (e) => {
      const key = e.key.toLowerCase();
      state.keys[key] = false;
      if (e.key === 'Shift') {
        state.isSprinting = false;
      }
    };

    const onMouseMove = (e) => {
      // If pointer is not locked, allow looking around by holding left click and dragging
      if (!state.isLocked && e.buttons !== 1) return;
      
      state.yaw -= e.movementX * 0.0022;
      state.pitch -= e.movementY * 0.0022;
      
      // Clamp pitch to look vertical limits
      state.pitch = Math.max(-Math.PI / 2.2, Math.min(Math.PI / 2.2, state.pitch));
      
      camera.rotation.y = state.yaw;
      camera.rotation.x = state.pitch;
    };

    // Click canvas to lock pointer
    const requestLock = () => {
      if (state.isPaused) return;
      canvasRef.current.requestPointerLock();
    };

    const onLockChange = () => {
      const locked = document.pointerLockElement === canvasRef.current;
      state.isLocked = locked;
      setIsLockedState(locked);
    };

    // Attach listeners
    window.addEventListener('keydown', onKeyDown);
    window.addEventListener('keyup', onKeyUp);
    document.addEventListener('mousemove', onMouseMove);
    document.addEventListener('pointerlockchange', onLockChange);
    canvasRef.current.addEventListener('click', requestLock);

    // Auto-request pointer lock on level load (since this mounts synchronously in the click handler)
    setTimeout(() => {
      if (canvasRef.current) {
        canvasRef.current.requestPointerLock();
      }
    }, 100);

    // Screen resizing
    const onResize = () => {
      if (!containerRef.current) return;
      camera.aspect = containerRef.current.clientWidth / containerRef.current.clientHeight;
      camera.updateProjectionMatrix();
      renderer.setSize(containerRef.current.clientWidth, containerRef.current.clientHeight);
    };
    window.addEventListener('resize', onResize);

    // Collision check helper
    const checkCollision = (posX, posZ) => {
      const radius = 0.45;
      let cx = posX;
      let cz = posZ;

      for (let wall of state.walls) {
        // AABB-vs-Circle collision check
        const closestX = Math.max(wall.minX, Math.min(cx, wall.maxX));
        const closestZ = Math.max(wall.minZ, Math.min(cz, wall.maxZ));

        const distX = cx - closestX;
        const distZ = cz - closestZ;
        const distSq = distX * distX + distZ * distZ;

        if (distSq < radius * radius && distSq > 0) {
          const dist = Math.sqrt(distSq);
          const overlap = radius - dist;
          cx += (distX / dist) * overlap;
          cz += (distZ / dist) * overlap;
        }
      }
      return { x: cx, z: cz };
    };

    // Interaction handler for valves and elevator buttons
    const handleInteraction = () => {
      const pPos = camera.position;
      
      // 1. Check Valves (Level 3, Level 8)
      for (let v of state.valves) {
        const dist = pPos.distanceTo(v.pos);
        if (dist < 2.0 && !v.turned) {
          v.turned = true;
          soundManager.playClick();
          
          // Animate valve rotation visual
          let rotTicks = 0;
          const rotateValve = () => {
            if (rotTicks < 30) {
              v.mesh.rotation.z += Math.PI / 10;
              rotTicks++;
              requestAnimationFrame(rotateValve);
            } else {
              // Valve fully turned, deactivate steam
              state.steamActive = false;
              onClosePrompt();
              
              // Visual hide of steam meshes
              for (let sh of state.steamHazards) {
                sh.mesh.visible = false;
                sh.light.visible = false;
              }
              
              // Flashlight feedback click
              soundManager.playClick();
            }
          };
          rotateValve();
          return;
        }
      }
    };

    // Animation Loop variables
    let clock = new THREE.Clock();
    let frameId;
    let footstepTimer = 0;

    // Render loop
    const tick = () => {
      frameId = requestAnimationFrame(tick);

      // Skip updates if paused
      if (state.isPaused) {
        clock.getDelta(); // Keep clock running smoothly
        renderer.render(scene, camera);
        return;
      }

      const dt = Math.min(clock.getDelta(), 0.1); // Cap delta to prevent clipping through wall at low fps
      const pPos = camera.position;

      // 1. FLASHLIGHT BATTERY DRAIN AND INTENSITY
      if (state.flashlightOn && state.flashlightBattery > 0) {
        flashlight.intensity = 1.5;
        // Faster drain in sub-level 0 (Level 5) and lights out (Level 7)
        const drainFactor = (levelIndex === 4 || levelIndex === 6) ? 3.0 : 1.5;
        const newBattery = Math.max(0, state.flashlightBattery - dt * drainFactor);
        
        state.flashlightBattery = newBattery;
        setFlashlightBattery(newBattery);
        
        if (newBattery <= 0) {
          setFlashlightOn(false);
          state.flashlightOn = false;
          soundManager.playClick();
        }
      } else {
        flashlight.intensity = 0.0;
      }

      // 2. CHECK INTERACTIVE ELEMENTS PROXIMITY
      let showPromptThisFrame = null;
      for (let v of state.valves) {
        if (!v.turned && pPos.distanceTo(v.pos) < 2.0) {
          showPromptThisFrame = "Press [E] to turn Valve";
        }
      }
      if (showPromptThisFrame) {
        onInteractPrompt(showPromptThisFrame);
      } else {
        onClosePrompt();
      }

      // 3. MOVEMENT CONTROLS
      const moveSpeed = state.isSprinting && state.sprintStamina > 10 ? 6.5 : 3.5;
      const speedModifier = state.inWater ? 0.45 : 1.0;
      const actualSpeed = moveSpeed * speedModifier;

      const keys = state.keys;
      const moveDir = new THREE.Vector3();

      if (keys['w'] || keys['arrowup']) moveDir.z -= 1;
      if (keys['s'] || keys['arrowdown']) moveDir.z += 1;
      if (keys['a'] || keys['arrowleft']) moveDir.x -= 1;
      if (keys['d'] || keys['arrowright']) moveDir.x += 1;

      moveDir.normalize();
      
      // Rotate movement vector to align with camera look yaw
      const forwardVec = new THREE.Vector3(0, 0, -1).applyAxisAngle(new THREE.Vector3(0, 1, 0), state.yaw);
      const rightVec = new THREE.Vector3(1, 0, 0).applyAxisAngle(new THREE.Vector3(0, 1, 0), state.yaw);
      
      const velocity = new THREE.Vector3()
        .addScaledVector(forwardVec, -moveDir.z)
        .addScaledVector(rightVec, moveDir.x)
        .normalize()
        .multiplyScalar(actualSpeed);

      // Calculate candidate positions
      let newX = pPos.x + velocity.x * dt;
      let newZ = pPos.z + velocity.z * dt;

      // Handle collision
      const corrected = checkCollision(newX, newZ);
      pPos.x = corrected.x;
      pPos.z = corrected.z;

      // 4. WATER HEIGHT AND SPEED MODIFIER CHECKS
      let currentInWater = false;
      for (let item of state.items) {
        if (item.type === 'water') {
          const dist = new THREE.Vector2(pPos.x, pPos.z).distanceTo(new THREE.Vector2(item.pos.x, item.pos.z));
          if (dist < CELL_SIZE / 1.8) {
            currentInWater = true;
          }
        }
      }
      state.inWater = currentInWater;

      // 5. STAMINA MANAGEMENT
      const isMoving = velocity.length() > 0.1;
      if (state.isSprinting && isMoving && !state.inWater) {
        const newStamina = Math.max(0, state.sprintStamina - dt * 25);
        state.sprintStamina = newStamina;
        setSprintStamina(newStamina);
        if (newStamina <= 0) {
          state.isSprinting = false;
        }
      } else {
        const newStamina = Math.min(100, state.sprintStamina + dt * 15);
        state.sprintStamina = newStamina;
        setSprintStamina(newStamina);
      }

      // 6. FOOTSTEPS GENERATION
      if (isMoving) {
        footstepTimer += dt;
        const stepRate = state.isSprinting ? 0.32 : 0.5;
        if (footstepTimer >= stepRate) {
          footstepTimer = 0;
          const surface = state.inWater ? "water" : config.theme;
          soundManager.playFootstep(surface);
        }
      }

      // 7. KEYCARD & BATTERY GATHERING
      for (let i = state.items.length - 1; i >= 0; i--) {
        const item = state.items[i];
        if (item.type === 'keycard') {
          // Spin
          item.mesh.rotation.y += dt * 1.5;
          item.mesh.position.y = 0.8 + Math.sin(clock.getElapsedTime() * 3) * 0.1;
          
          if (pPos.distanceTo(item.pos) < 1.3) {
            // Collect keycard
            scene.remove(item.mesh);
            scene.remove(item.light);
            state.items.splice(i, 1);
            setKeysCollected(state.keysCollected + 1);
            state.keysCollected += 1;
            soundManager.playClick();
          }
        } 
        else if (item.type === 'battery') {
          // Spin
          item.mesh.rotation.z += dt * 1.2;
          item.mesh.position.y = 0.8 + Math.cos(clock.getElapsedTime() * 3.5) * 0.08;

          if (pPos.distanceTo(item.pos) < 1.3) {
            // Collect battery
            scene.remove(item.mesh);
            scene.remove(item.light);
            state.items.splice(i, 1);
            
            const batteryGain = Math.min(100, state.flashlightBattery + 35);
            setFlashlightBattery(batteryGain);
            state.flashlightBattery = batteryGain;
            
            soundManager.playClick();
          }
        }
        else if (item.type === 'light') {
          // Flickering ceiling light logic
          item.flickerTimer -= dt;
          if (item.flickerTimer <= 0) {
            // Setup a flicker burst
            const intensityRatio = Math.random() > 0.4 ? 0.05 : 1.0;
            item.light.intensity = item.baseIntensity * intensityRatio;
            
            if (intensityRatio < 0.2) {
              item.fixture.material.color.setHex(0x555555);
            } else {
              item.fixture.material.color.setHex(0xffffff);
            }

            if (Math.random() > 0.8) {
              item.flickerTimer = Math.random() * 4 + 1.0; // Wait longer before next flicker
            } else {
              item.flickerTimer = Math.random() * 0.15; // Quick rapid flicker
            }
          }
        }
      }

      // 8. STEAM HAZARDS DAMAGE
      if (state.steamActive) {
        for (let sh of state.steamHazards) {
          const dist = pPos.distanceTo(sh.pos);
          if (dist < 1.5) {
            const dmg = dt * 30; // 30 health per second
            const newHealth = Math.max(0, state.health - dmg);
            state.health = newHealth;
            setHealth(newHealth);
            
            // Red vignette alarm triggers
            if (newHealth <= 0) {
              onLevelLose();
              soundManager.playScreech();
              cancelAnimationFrame(frameId);
              return;
            }
          }
        }
      }

      // 9. MONSTER AI AND CHASE PATHFINDING
      if (config.hasMonster && state.monster) {
        const monster = state.monster;
        const time = clock.getElapsedTime();

        // Animate monster limbs wiggle
        monster.userData.limbs.forEach((limb, index) => {
          limb.rotation.z = Math.sin(time * 12 + index) * 0.25;
          limb.position.y = 0.8 + Math.cos(time * 10 + index) * 0.05;
        });

        const mPos = monster.position;
        const playerGridX = Math.round(pPos.x / CELL_SIZE);
        const playerGridZ = Math.round(pPos.z / CELL_SIZE);
        const monsterGridX = Math.round(mPos.x / CELL_SIZE);
        const monsterGridZ = Math.round(mPos.z / CELL_SIZE);

        // Recalculate BFS path towards player every 0.35 seconds
        if (time - state.monsterLastPathTime > 0.35) {
          state.monsterLastPathTime = time;
          state.monsterPath = findPathBFS(grid, monsterGridX, monsterGridZ, playerGridX, playerGridZ);
        }

        // Move monster along path
        if (state.monsterPath && state.monsterPath.length > 0) {
          const nextNode = state.monsterPath[0];
          const targetX = nextNode.x * CELL_SIZE;
          const targetZ = nextNode.z * CELL_SIZE;

          const dx = targetX - mPos.x;
          const dz = targetZ - mPos.z;
          const len = Math.sqrt(dx * dx + dz * dz);

          if (len < 0.2) {
            // Arrived at current node, advance to next
            state.monsterPath.shift();
          } else {
            // Speed scaling based on level difficulty
            const speed = config.monsterSpeed;
            mPos.x += (dx / len) * speed * dt;
            mPos.z += (dz / len) * speed * dt;

            // Make monster look at target
            const angle = Math.atan2(dx, dz);
            monster.rotation.y = angle;
          }
        } else {
          // If no path (e.g. wall clipping), default directly to player
          const dx = pPos.x - mPos.x;
          const dz = pPos.z - mPos.z;
          const len = Math.sqrt(dx * dx + dz * dz);
          if (len > 0.1) {
            mPos.x += (dx / len) * config.monsterSpeed * dt;
            mPos.z += (dz / len) * config.monsterSpeed * dt;
          }
        }

        // Distance check for static sound & HUD interference
        const distToPlayer = pPos.distanceTo(mPos);

        // Static intensity increases as monster approaches (within 12 units)
        const staticRange = 12.0;
        if (distToPlayer < staticRange) {
          const ratio = 1.0 - (distToPlayer / staticRange);
          soundManager.setStaticLevel(ratio);
        } else {
          soundManager.setStaticLevel(0.0);
        }

        // Catch check: Game Over!
        if (distToPlayer < 1.3) {
          onLevelLose();
          soundManager.playScreech();
          cancelAnimationFrame(frameId);
          return;
        }
      }

      // 10. CHECK EXIT PORTAL WIN CONDITION
      const distToExit = pPos.distanceTo(state.exitPos);
      if (distToExit < 1.5) {
        if (state.keysCollected >= config.keysRequired) {
          onLevelWin();
          cancelAnimationFrame(frameId);
          return;
        } else {
          onInteractPrompt(`Locked: Need ${config.keysRequired} Keycards`);
        }
      }

      // Draw view
      renderer.render(scene, camera);
    };

    // Begin looping
    tick();

    // Clean up
    return () => {
      cancelAnimationFrame(frameId);
      window.removeEventListener('keydown', onKeyDown);
      window.removeEventListener('keyup', onKeyUp);
      document.removeEventListener('mousemove', onMouseMove);
      document.removeEventListener('pointerlockchange', onLockChange);
      window.removeEventListener('resize', onResize);
      
      soundManager.stopAll();
      renderer.dispose();
      
      // Unlock pointer if locked
      if (document.pointerLockElement === canvasRef.current) {
        document.exitPointerLock();
      }
    };
  }, [levelIndex]);

  return (
    <div 
      ref={containerRef} 
      style={{ width: '100%', height: '100%', position: 'relative', overflow: 'hidden' }}
    >
      <canvas ref={canvasRef} style={{ display: 'block', width: '100%', height: '100%' }} />
      
      {/* Small lock indicator instead of full screen blocker */}
      {!isLockedState && !isPaused && (
        <div className="pause-hint" style={{ bottom: '15px', top: 'auto', left: '15px', transform: 'none', pointerEvents: 'none' }}>
          [CLICK TO LOCK MOUSE CURSOR]
        </div>
      )}
    </div>
  );
}
