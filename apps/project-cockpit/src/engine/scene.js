/**
 * GPU Rendering Engine — Three.js with WebGPU/WebGL2
 *
 * Full-viewport background canvas showing:
 * - Cluster topology as force-directed graph
 * - Data flow particles between nodes
 * - Truth freshness as luminous glow
 *
 * Degrades gracefully: WebGPU → WebGL2
 */
import * as THREE from "three";

let renderer = null;
let scene = null;
let camera = null;
let animationId = null;
let nodes = [];
let edges = [];

const NODE_COLORS = {
  healthy: new THREE.Color(0x51d6bd),   // --truth-observed
  degraded: new THREE.Color(0xf4c15e),  // --posture-warm
  down: new THREE.Color(0xef4444),      // --state-error
  control: new THREE.Color(0x9fb2cd),   // --truth-declared
};

/**
 * Initialize the GPU scene and attach to a canvas element.
 * @param {HTMLCanvasElement} canvas
 */
export async function initScene(canvas) {
  scene = new THREE.Scene();
  scene.background = new THREE.Color(0x050a12); // --surface-0

  // Camera: orthographic-like perspective for topology
  camera = new THREE.PerspectiveCamera(45, canvas.width / canvas.height, 0.1, 1000);
  camera.position.set(0, 0, 12);
  camera.lookAt(0, 0, 0);

  // Try WebGPU first, fall back to WebGL2
  try {
    const { WebGPURenderer } = await import("three/webgpu");
    renderer = new WebGPURenderer({ canvas, antialias: true, alpha: false });
    await renderer.init();
    console.log("[engine] WebGPU renderer initialized");
  } catch (e) {
    console.log("[engine] WebGPU unavailable, falling back to WebGL2:", e.message);
    renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: false });
  }

  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
  renderer.setSize(canvas.width, canvas.height);

  // Ambient light (soft fill)
  scene.add(new THREE.AmbientLight(0x0a1628, 0.8));

  // Point light (subtle directional cue)
  const pointLight = new THREE.PointLight(0x51d6bd, 0.3, 50);
  pointLight.position.set(5, 5, 10);
  scene.add(pointLight);

  // Build initial topology
  buildTopology();

  // Start render loop
  animate();

  return { scene, camera, renderer };
}

/**
 * Build the cluster topology graph.
 * Three nodes: r770-proxmox (GPU), r740-proxmox (GPU), t560-proxmox (control)
 */
function buildTopology() {
  const nodeData = [
    { id: "r770", label: "r770-proxmox", role: "gpu", x: -3, y: 1.5, color: "healthy" },
    { id: "r740", label: "r740-proxmox", role: "gpu", x: 3, y: 1.5, color: "healthy" },
    { id: "t560", label: "t560-proxmox", role: "control", x: 0, y: -2.5, color: "control" },
  ];

  const edgeData = [
    { from: "r770", to: "r740" },  // GPU interconnect
    { from: "r770", to: "t560" },  // GPU → control
    { from: "r740", to: "t560" },  // GPU → control
  ];

  // Create node meshes
  for (const nd of nodeData) {
    const geometry = new THREE.SphereGeometry(0.35, 32, 32);
    const material = new THREE.MeshStandardMaterial({
      color: NODE_COLORS[nd.color],
      emissive: NODE_COLORS[nd.color],
      emissiveIntensity: 0.3,
      roughness: 0.4,
      metalness: 0.6,
    });
    const mesh = new THREE.Mesh(geometry, material);
    mesh.position.set(nd.x, nd.y, 0);
    mesh.userData = { ...nd };
    scene.add(mesh);

    // Glow halo (sprite)
    const spriteMat = new THREE.SpriteMaterial({
      color: NODE_COLORS[nd.color],
      transparent: true,
      opacity: 0.15,
      blending: THREE.AdditiveBlending,
    });
    const sprite = new THREE.Sprite(spriteMat);
    sprite.scale.set(1.8, 1.8, 1);
    sprite.position.copy(mesh.position);
    scene.add(sprite);

    nodes.push({ data: nd, mesh, sprite, material });
  }

  // Create edge lines
  for (const ed of edgeData) {
    const fromNode = nodes.find(n => n.data.id === ed.from);
    const toNode = nodes.find(n => n.data.id === ed.to);
    if (!fromNode || !toNode) continue;

    const points = [fromNode.mesh.position, toNode.mesh.position];
    const geometry = new THREE.BufferGeometry().setFromPoints(points);
    const material = new THREE.LineBasicMaterial({
      color: 0x162a4a,  // --surface-3
      transparent: true,
      opacity: 0.4,
    });
    const line = new THREE.Line(geometry, material);
    scene.add(line);
    edges.push({ data: ed, line });
  }
}

/**
 * Main animation loop.
 * Subtle breathing animation on nodes + slow rotation.
 */
function animate() {
  animationId = requestAnimationFrame(animate);
  const t = performance.now() * 0.001;

  // Subtle node breathing (emissive intensity oscillation)
  for (const node of nodes) {
    const breathe = 0.2 + 0.15 * Math.sin(t * 0.8 + node.data.x);
    node.material.emissiveIntensity = breathe;
    node.sprite.material.opacity = 0.08 + 0.08 * Math.sin(t * 0.6 + node.data.y);
  }

  // Very slow scene drift (not rotation — just gentle parallax)
  camera.position.x = Math.sin(t * 0.1) * 0.3;
  camera.position.y = Math.cos(t * 0.08) * 0.2;
  camera.lookAt(0, 0, 0);

  renderer.render(scene, camera);
}

/**
 * Handle resize events.
 * @param {number} width
 * @param {number} height
 */
export function resizeScene(width, height) {
  if (!renderer || !camera) return;
  camera.aspect = width / height;
  camera.updateProjectionMatrix();
  renderer.setSize(width, height);
}

/**
 * Update node health state.
 * @param {string} nodeId
 * @param {"healthy"|"degraded"|"down"|"control"} state
 */
export function updateNodeState(nodeId, state) {
  const node = nodes.find(n => n.data.id === nodeId);
  if (!node) return;
  const color = NODE_COLORS[state] || NODE_COLORS.control;
  node.material.color.copy(color);
  node.material.emissive.copy(color);
  node.sprite.material.color.copy(color);
}

/**
 * Cleanup the scene.
 */
export function destroyScene() {
  if (animationId) cancelAnimationFrame(animationId);
  if (renderer) renderer.dispose();
  nodes = [];
  edges = [];
  scene = null;
  camera = null;
  renderer = null;
}
