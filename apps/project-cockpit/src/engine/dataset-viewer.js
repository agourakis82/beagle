/**
 * Dataset Viewer Engine — dedicated Three.js scene for scientific visualization.
 *
 * Separate from the topology background. This scene is used for:
 * - OME-Zarr multiscale volume rendering (future)
 * - Dataset provenance graph overlay
 * - Spatial scientific data exploration
 *
 * TOOLCHAIN NOTE (April 2026): Using Three.js standard materials,
 * not custom WGSL shaders. Three.js 0.183 WebGPURenderer handles
 * internal WGSL generation safely. Custom truth-glow shaders will
 * be added as enhancement after verifying WebGPU compat.
 */
import * as THREE from "three";

let renderer = null;
let scene = null;
let camera = null;
let controls = null;
let animationId = null;
let gridHelper = null;
let volumePlaceholder = null;
let axisHelpers = [];

const VIEWER_BG = new THREE.Color(0x030810);

/**
 * Initialize the dataset viewer scene.
 * @param {HTMLCanvasElement} canvas
 */
export async function initViewerScene(canvas) {
  scene = new THREE.Scene();
  scene.background = VIEWER_BG;
  scene.fog = new THREE.Fog(0x030810, 15, 40);

  camera = new THREE.PerspectiveCamera(50, canvas.width / canvas.height, 0.1, 100);
  camera.position.set(4, 3, 6);
  camera.lookAt(0, 0, 0);

  // Try WebGPU, fallback to WebGL2
  try {
    const { WebGPURenderer } = await import("three/webgpu");
    renderer = new WebGPURenderer({ canvas, antialias: true, alpha: false });
    await renderer.init();
    console.log("[viewer] WebGPU renderer initialized");
  } catch (e) {
    console.log("[viewer] WebGPU unavailable, using WebGL2:", e.message);
    renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: false });
  }

  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
  renderer.setSize(canvas.width, canvas.height);
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.0;

  // OrbitControls (dynamic import to avoid bundling on non-viewer pages)
  try {
    const { OrbitControls } = await import("three/addons/controls/OrbitControls.js");
    controls = new OrbitControls(camera, canvas);
    controls.enableDamping = true;
    controls.dampingFactor = 0.05;
    controls.minDistance = 2;
    controls.maxDistance = 30;
    controls.target.set(0, 0.5, 0);
    controls.update();
  } catch (e) {
    console.warn("[viewer] OrbitControls not available:", e.message);
  }

  // Lighting
  const ambientLight = new THREE.AmbientLight(0x0a1628, 1.2);
  scene.add(ambientLight);

  const keyLight = new THREE.DirectionalLight(0x77b8ff, 0.6);
  keyLight.position.set(5, 8, 4);
  scene.add(keyLight);

  const fillLight = new THREE.DirectionalLight(0x51d6bd, 0.2);
  fillLight.position.set(-3, 2, -4);
  scene.add(fillLight);

  // Grid plane — reference surface
  gridHelper = new THREE.GridHelper(10, 20, 0x162a4a, 0x0a1628);
  gridHelper.material.transparent = true;
  gridHelper.material.opacity = 0.4;
  scene.add(gridHelper);

  // Axis lines — subtle RGB (X=red, Y=green, Z=blue)
  buildAxisHelpers();

  // Volume placeholder — wireframe cube representing future OME-Zarr data
  buildVolumePlaceholder();

  // Start render loop
  animateViewer();

  return { scene, camera, renderer };
}

function buildAxisHelpers() {
  const axisLength = 2;
  const axes = [
    { dir: new THREE.Vector3(1, 0, 0), color: 0xef4444 },  // X — red
    { dir: new THREE.Vector3(0, 1, 0), color: 0x51d6bd },  // Y — teal
    { dir: new THREE.Vector3(0, 0, 1), color: 0x77b8ff },  // Z — blue
  ];

  for (const { dir, color } of axes) {
    const points = [new THREE.Vector3(0, 0, 0), dir.clone().multiplyScalar(axisLength)];
    const geometry = new THREE.BufferGeometry().setFromPoints(points);
    const material = new THREE.LineBasicMaterial({ color, transparent: true, opacity: 0.5 });
    const line = new THREE.Line(geometry, material);
    scene.add(line);
    axisHelpers.push(line);
  }
}

function buildVolumePlaceholder() {
  // Wireframe cube — represents the data volume
  const geometry = new THREE.BoxGeometry(2, 2, 2);
  const edges = new THREE.EdgesGeometry(geometry);
  const material = new THREE.LineBasicMaterial({
    color: 0x51d6bd,
    transparent: true,
    opacity: 0.3,
  });
  volumePlaceholder = new THREE.LineSegments(edges, material);
  volumePlaceholder.position.set(0, 1, 0);
  scene.add(volumePlaceholder);

  // Inner glow sphere (subtle emissive core)
  const glowGeo = new THREE.SphereGeometry(0.6, 16, 16);
  const glowMat = new THREE.MeshStandardMaterial({
    color: 0x51d6bd,
    emissive: 0x51d6bd,
    emissiveIntensity: 0.15,
    transparent: true,
    opacity: 0.1,
    roughness: 1,
    metalness: 0,
  });
  const glowMesh = new THREE.Mesh(glowGeo, glowMat);
  glowMesh.position.copy(volumePlaceholder.position);
  scene.add(glowMesh);
  volumePlaceholder.userData.glow = glowMesh;
}

function animateViewer() {
  animationId = requestAnimationFrame(animateViewer);
  const t = performance.now() * 0.001;

  // Subtle volume breathing
  if (volumePlaceholder) {
    const scale = 1 + 0.02 * Math.sin(t * 0.5);
    volumePlaceholder.scale.setScalar(scale);
    volumePlaceholder.rotation.y = t * 0.05;

    const glow = volumePlaceholder.userData.glow;
    if (glow) {
      glow.material.emissiveIntensity = 0.1 + 0.08 * Math.sin(t * 0.7);
      glow.scale.setScalar(scale);
      glow.rotation.y = -t * 0.03;
    }
  }

  if (controls) controls.update();
  renderer.render(scene, camera);
}

/**
 * Resize the viewer.
 */
export function resizeViewer(width, height) {
  if (!renderer || !camera) return;
  camera.aspect = width / height;
  camera.updateProjectionMatrix();
  renderer.setSize(width, height);
}

/**
 * Update the volume placeholder to reflect dataset metadata.
 * @param {{ axes: string[], datasetLevels: number }} metadata
 */
export function updateVolumeFromMetadata(metadata) {
  if (!volumePlaceholder || !metadata) return;

  // Scale placeholder based on dimensionality
  const dims = metadata.axes?.length || 3;
  const levels = metadata.datasetLevels || 1;

  // Visual hint: more levels = slightly larger + brighter
  const scaleFactor = 1 + (levels - 1) * 0.1;
  volumePlaceholder.scale.setScalar(scaleFactor);

  if (volumePlaceholder.userData.glow) {
    volumePlaceholder.userData.glow.material.emissiveIntensity = 0.1 + levels * 0.05;
  }
}

/**
 * Set camera mode.
 * @param {"overview"|"semantic-overview"|"top"|"front"} mode
 */
export function setCameraMode(mode) {
  if (!camera) return;
  const duration = 0.8;

  switch (mode) {
    case "overview":
      camera.position.set(4, 3, 6);
      break;
    case "semantic-overview":
      camera.position.set(3, 5, 4);
      break;
    case "top":
      camera.position.set(0, 8, 0.1);
      break;
    case "front":
      camera.position.set(0, 1.5, 8);
      break;
  }

  if (controls) {
    controls.target.set(0, 0.5, 0);
    controls.update();
  }
}

/**
 * Cleanup the viewer scene.
 */
export function destroyViewerScene() {
  if (animationId) cancelAnimationFrame(animationId);
  if (controls) controls.dispose();
  if (renderer) renderer.dispose();
  axisHelpers = [];
  volumePlaceholder = null;
  scene = null;
  camera = null;
  renderer = null;
}
