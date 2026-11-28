//
//  ConversationScrollPolicy.swift
//  BeagleCore
//
//  Pure scroll-follow policy for streaming conversations (R3):
//  - Auto-follows streaming tokens only while the reader stays near the bottom.
//  - Pauses auto-scroll when the reader scrolls up to read earlier messages and tracks
//    unseen updates (`hasUnreadBelow`) so the UI can show a non-intrusive return control.
//

import CoreGraphics
import Foundation

public enum ConversationScrollPolicy: Sendable {
    /// Distance (in points) from the bottom edge still considered "at the tail" of the thread.
    public static let nearBottomThreshold: CGFloat = 120

    public struct Metrics: Equatable, Sendable {
        public let offsetY: CGFloat
        public let containerHeight: CGFloat
        public let contentHeight: CGFloat
        public let distanceFromBottom: CGFloat
        public let isScrollable: Bool

        public init(
            offsetY: CGFloat,
            containerHeight: CGFloat,
            contentHeight: CGFloat,
            distanceFromBottom: CGFloat,
            isScrollable: Bool
        ) {
            self.offsetY = offsetY
            self.containerHeight = containerHeight
            self.contentHeight = contentHeight
            self.distanceFromBottom = distanceFromBottom
            self.isScrollable = isScrollable
        }
    }

    public struct FollowState: Equatable, Sendable {
        public var isNearBottom: Bool
        public var hasUnreadBelow: Bool

        public init(isNearBottom: Bool = true, hasUnreadBelow: Bool = false) {
            self.isNearBottom = isNearBottom
            self.hasUnreadBelow = hasUnreadBelow
        }
    }

    public static func distanceFromBottom(
        contentHeight: CGFloat,
        contentOffsetY: CGFloat,
        containerHeight: CGFloat,
        bottomInset: CGFloat
    ) -> CGFloat {
        let totalBottom = contentHeight + bottomInset
        let visibleBottom = contentOffsetY + containerHeight
        return max(0, totalBottom - visibleBottom)
    }

    public static func updatedFollowState(
        current: FollowState,
        oldMetrics: Metrics,
        newMetrics: Metrics
    ) -> FollowState {
        // Short threads fit entirely in the viewport: always pinned and nothing unread below.
        guard newMetrics.isScrollable else {
            return FollowState(isNearBottom: true, hasUnreadBelow: false)
        }

        // Ignore transient geometry shifts caused by keyboard presentation or rotation.
        if abs(newMetrics.containerHeight - oldMetrics.containerHeight) > 1 {
            return current
        }

        if newMetrics.distanceFromBottom <= nearBottomThreshold {
            return FollowState(isNearBottom: true, hasUnreadBelow: false)
        }

        // Keep following if the reader was already pinned at the tail and the content grew
        // faster than the next scrollTo tick (e.g. a large streaming chunk rendered first).
        let contentDelta = newMetrics.contentHeight - oldMetrics.contentHeight
        let userDidNotScrollUp = newMetrics.offsetY >= oldMetrics.offsetY - 2
        if current.isNearBottom && userDidNotScrollUp && contentDelta > 0 {
            return current
        }

        return FollowState(isNearBottom: false, hasUnreadBelow: current.hasUnreadBelow)
    }

    public static func nextStateOnIncomingUpdate(
        state: FollowState,
        isUserMessage: Bool
    ) -> (shouldScroll: Bool, nextState: FollowState) {
        if isUserMessage {
            return (true, FollowState(isNearBottom: true, hasUnreadBelow: false))
        }
        if state.isNearBottom {
            return (true, state)
        }
        return (false, FollowState(isNearBottom: false, hasUnreadBelow: true))
    }

    public static func resetForBottomJump() -> FollowState {
        FollowState(isNearBottom: true, hasUnreadBelow: false)
    }
}
