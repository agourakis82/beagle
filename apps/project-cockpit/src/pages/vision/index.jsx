/**
 * Vision Surfaces — 9 public endpoints as SolidJS pages.
 *
 * Each page is a thin wrapper around VisionSurface with its endpoint URL.
 */
import VisionSurface from "./VisionSurface";

export const ControlRoom       = () => <VisionSurface endpoint="/api/public/vision/control-room" fallbackTitle="Control Room" />;
export const AppleBrief        = () => <VisionSurface endpoint="/api/public/vision/apple-brief" fallbackTitle="Apple Brief" />;
export const AppleLaunchpad    = () => <VisionSurface endpoint="/api/public/vision/apple-launchpad" fallbackTitle="Apple Launchpad" />;
export const OperatorBoard     = () => <VisionSurface endpoint="/api/public/vision/operator-board" fallbackTitle="Operator Board" />;
export const RuntimeMatrix     = () => <VisionSurface endpoint="/api/public/vision/runtime-matrix" fallbackTitle="Runtime Matrix" />;
export const RouteAtlas        = () => <VisionSurface endpoint="/api/public/vision/route-atlas" fallbackTitle="Route Atlas" />;
export const MissionTimeline   = () => <VisionSurface endpoint="/api/public/vision/mission-timeline" fallbackTitle="Mission Timeline" />;
export const SovereignBridge   = () => <VisionSurface endpoint="/api/public/vision/sovereign-bridge" fallbackTitle="Sovereign Bridge" />;
export const Handoff           = () => <VisionSurface endpoint="/api/public/vision/handoff" fallbackTitle="Handoff" />;
