//
//  VisualWorkbenchModels.swift
//  BeagleWorkbenchKit
//
//  Re-exports BeagleCore visual workbench models so BeagleWorkbenchKit callers
//  keep source compatibility while non-AGPL targets (such as BeagleVisionOS)
//  consume SpatialAgentDeckSnapshot directly from BeagleCore.
//

import BeagleCore

public typealias VisualWorkArtifactKind = BeagleCore.VisualWorkArtifactKind
public typealias VisualWorkArtifact = BeagleCore.VisualWorkArtifact
public typealias VisualAgentLaneSnapshot = BeagleCore.VisualAgentLaneSnapshot
public typealias VisualWorkCanvasState = BeagleCore.VisualWorkCanvasState
public typealias RuntimeLogPresentationState = BeagleCore.RuntimeLogPresentationState
public typealias SpatialAgentDeckSnapshot = BeagleCore.SpatialAgentDeckSnapshot
