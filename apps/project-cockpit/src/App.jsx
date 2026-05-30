/**
 * App — Root shell for the Sovereign Supercomputing Control Surface
 *
 * Three rendering layers:
 * 1. GPU canvas (full viewport background, z-index 0) — living cluster topology
 * 2. SolidJS DOM (glass panels, text, controls, z-index 1) — information + interaction
 * 3. Canvas 2D (inline sparklines, managed per-component) — data density
 *
 * The GPU canvas shows the living cluster topology.
 * Glass panels float over it with glassmorphism.
 */
import { onMount, onCleanup, lazy, Suspense } from "solid-js";
import { Router, Route, useLocation } from "@solidjs/router";
import { initScene, resizeScene, destroyScene } from "./engine/scene";
import CommandPalette from "./components/CommandPalette";
import KeyboardOverlay from "./components/KeyboardOverlay";
import AudioControl from "./components/AudioControl";
import ErrorBoundary from "./components/ErrorBoundary";

const CommandBridge = lazy(() => import("./pages/CommandBridge"));
const ProjectOS = lazy(() => import("./pages/ProjectOS"));
const ClusterOps = lazy(() => import("./pages/ClusterOps"));
const ControlRoom = lazy(() => import("./pages/ControlRoom"));
const ControlTower = lazy(() => import("./pages/ControlTower"));
const ScientificViewport = lazy(() => import("./pages/ScientificViewport"));
const PublicPortal = lazy(() => import("./pages/PublicPortal"));
const Cognitive = lazy(() => import("./pages/Cognitive"));
const WorkbenchMirror = lazy(() => import("./pages/WorkbenchMirror"));
const ScratchStudio = lazy(() => import("./pages/ScratchStudio"));

// Vision surfaces — 9 routes, shared VisionSurface template (all in one chunk)
const VisionControlRoom     = lazy(() => import("./pages/vision").then(m => ({ default: m.ControlRoom })));
const VisionAppleBrief      = lazy(() => import("./pages/vision").then(m => ({ default: m.AppleBrief })));
const VisionAppleLaunchpad  = lazy(() => import("./pages/vision").then(m => ({ default: m.AppleLaunchpad })));
const VisionOperatorBoard   = lazy(() => import("./pages/vision").then(m => ({ default: m.OperatorBoard })));
const VisionRuntimeMatrix   = lazy(() => import("./pages/vision").then(m => ({ default: m.RuntimeMatrix })));
const VisionRouteAtlas      = lazy(() => import("./pages/vision").then(m => ({ default: m.RouteAtlas })));
const VisionMissionTimeline = lazy(() => import("./pages/vision").then(m => ({ default: m.MissionTimeline })));
const VisionSovereignBridge = lazy(() => import("./pages/vision").then(m => ({ default: m.SovereignBridge })));
const VisionHandoff         = lazy(() => import("./pages/vision").then(m => ({ default: m.Handoff })));

// Project showcase routes
const ProjectShowcaseIndex     = lazy(() => import("./pages/ProjectShowcase").then(m => ({ default: m.ProjectShowcaseIndex })));
const ProjectSovereignBridge   = lazy(() => import("./pages/ProjectShowcase").then(m => ({ default: m.ProjectSovereignBridge })));
const ProjectCockpitPreview    = lazy(() => import("./pages/ProjectShowcase").then(m => ({ default: m.ProjectCockpitPreview })));
const ProjectPacketGraph       = lazy(() => import("./pages/ProjectShowcase").then(m => ({ default: m.ProjectPacketGraph })));

function Loading() {
  return (
    <div style={{
      display: "flex",
      "align-items": "center",
      "justify-content": "center",
      height: "100%",
    }}>
      <div style={{
        display: "flex",
        "align-items": "center",
        gap: "var(--space-2)",
        color: "var(--text-tertiary)",
        "font-family": "var(--font-data)",
        "font-size": "var(--text-xs)",
        "letter-spacing": "0.1em",
        "text-transform": "uppercase",
        animation: "pulse-fade 1.4s ease-in-out infinite",
      }}>
        <span style={{
          width: "6px",
          height: "6px",
          "border-radius": "50%",
          background: "var(--truth-observed)",
          animation: "pulse-dot 1.4s ease-in-out infinite",
        }} />
        initializing
      </div>
      <style>{`
        @keyframes pulse-fade { 0%, 100% { opacity: 0.5; } 50% { opacity: 1; } }
        @keyframes pulse-dot { 0%, 100% { transform: scale(1); } 50% { transform: scale(1.4); } }
      `}</style>
    </div>
  );
}

function RoutedShell(props) {
  const location = useLocation();
  const isWorkbenchMirror = () => location.pathname.startsWith("/workbench") || location.pathname.startsWith("/workbench-old");

  return (
    <>
      {!isWorkbenchMirror() && <CommandPalette />}
      {!isWorkbenchMirror() && <KeyboardOverlay />}
      {props.children}
      {!isWorkbenchMirror() && <AudioControl />}
    </>
  );
}

export default function App() {
  let canvasRef;

  onMount(() => {
    if (canvasRef) {
      canvasRef.width = window.innerWidth;
      canvasRef.height = window.innerHeight;
      initScene(canvasRef).catch((e) => {
        console.warn("[app] GPU scene init failed:", e.message);
      });
    }

    const handleResize = () => {
      if (canvasRef) {
        canvasRef.width = window.innerWidth;
        canvasRef.height = window.innerHeight;
        resizeScene(window.innerWidth, window.innerHeight);
      }
    };
    window.addEventListener("resize", handleResize);
    onCleanup(() => {
      window.removeEventListener("resize", handleResize);
      destroyScene();
    });
  });

  return (
    <div style={{ position: "relative", width: "100%", height: "100%" }}>
      {/* Layer 0: GPU Canvas — living cluster topology */}
      <canvas
        ref={canvasRef}
        aria-hidden="true"
        role="presentation"
        style={{
          position: "fixed",
          top: 0,
          left: 0,
          width: "100%",
          height: "100%",
          "z-index": 0,
          "pointer-events": "none",
        }}
      />

      {/* Layer 1: SolidJS DOM — glass panels over GPU canvas */}
      <main
        role="main"
        aria-label="Project Cockpit"
        style={{
          position: "relative",
          "z-index": 1,
          width: "100%",
          height: "100%",
        }}>
        <ErrorBoundary>
          <Suspense fallback={<Loading />}>
            <Router root={RoutedShell}>
            <Route path="/" component={CommandBridge} />
            <Route path="/projects" component={CommandBridge} />
            <Route path="/projects/os" component={ProjectOS} />
            <Route path="/projects/cluster" component={ClusterOps} />
            <Route path="/workbench" component={ScratchStudio} />
            <Route path="/workbench/:slug" component={ScratchStudio} />
            <Route path="/workbench-old" component={WorkbenchMirror} />
            <Route path="/workbench-old/:slug" component={WorkbenchMirror} />
            <Route path="/projects/:slug/control" component={ControlTower} />
            <Route path="/projects/:slug" component={ControlRoom} />
            <Route path="/projects/:slug/viewer" component={ScientificViewport} />

            {/* Cognitive substrate dashboard (live SSE + Φ rhythm + deep-think) */}
            <Route path="/cognitive" component={Cognitive} />

            {/* Public portal */}
            <Route path="/public" component={PublicPortal} />

            {/* Vision surfaces — 9 routes */}
            <Route path="/public/vision" component={VisionControlRoom} />
            <Route path="/public/vision/control-room" component={VisionControlRoom} />
            <Route path="/public/vision/apple-brief" component={VisionAppleBrief} />
            <Route path="/public/vision/apple-launchpad" component={VisionAppleLaunchpad} />
            <Route path="/public/vision/operator-board" component={VisionOperatorBoard} />
            <Route path="/public/vision/runtime-matrix" component={VisionRuntimeMatrix} />
            <Route path="/public/vision/route-atlas" component={VisionRouteAtlas} />
            <Route path="/public/vision/mission-timeline" component={VisionMissionTimeline} />
            <Route path="/public/vision/sovereign-bridge" component={VisionSovereignBridge} />
            <Route path="/public/vision/handoff" component={VisionHandoff} />

            {/* Project showcases */}
            <Route path="/public/projects/:slug" component={ProjectShowcaseIndex} />
            <Route path="/public/projects/:slug/sovereign-bridge" component={ProjectSovereignBridge} />
            <Route path="/public/projects/:slug/sovereign-cockpit-preview" component={ProjectCockpitPreview} />
            <Route path="/public/projects/:slug/packet-graph" component={ProjectPacketGraph} />
            </Router>
          </Suspense>
        </ErrorBoundary>
      </main>
    </div>
  );
}
