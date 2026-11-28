//
//  ConversationScrollPolicyTests.swift
//  BeagleCoreTests
//
//  Unit tests for R3 (ConversationScrollPolicy):
//  - Smart auto-scroll only when near bottom
//  - Preserves reading position when scrolled up during assistant streaming
//  - Sets/clears `hasUnreadBelow` and resets cleanly on jump-to-bottom or user send
//

import CoreGraphics
import Testing
@testable import BeagleCore

@Suite("R3: Conversation Smart Auto-Scroll")
struct ConversationScrollPolicyTests {

    @Test("Short non-scrollable thread always remains near bottom")
    func shortThreadStaysNearBottom() {
        let m1 = ConversationScrollPolicy.Metrics(
            offsetY: 0, containerHeight: 600, contentHeight: 400, distanceFromBottom: 0, isScrollable: false
        )
        let m2 = ConversationScrollPolicy.Metrics(
            offsetY: 0, containerHeight: 600, contentHeight: 450, distanceFromBottom: 0, isScrollable: false
        )

        let state = ConversationScrollPolicy.updatedFollowState(
            current: .init(isNearBottom: false, hasUnreadBelow: true),
            oldMetrics: m1,
            newMetrics: m2
        )

        #expect(state.isNearBottom == true)
        #expect(state.hasUnreadBelow == false)
    }

    @Test("Scrolling up away from tail pauses auto-scroll and records unread updates on stream")
    func scrollUpPausesAutoScrollAndMarksUnread() {
        let atBottom = ConversationScrollPolicy.Metrics(
            offsetY: 1400, containerHeight: 600, contentHeight: 2000, distanceFromBottom: 0, isScrollable: true
        )
        let scrolledUp = ConversationScrollPolicy.Metrics(
            offsetY: 1000,
            containerHeight: 600,
            contentHeight: 2000,
            distanceFromBottom: ConversationScrollPolicy.distanceFromBottom(
                contentHeight: 2000, contentOffsetY: 1000, containerHeight: 600, bottomInset: 0
            ),
            isScrollable: true
        )

        #expect(scrolledUp.distanceFromBottom == 400)

        let stateAfterScroll = ConversationScrollPolicy.updatedFollowState(
            current: .init(isNearBottom: true, hasUnreadBelow: false),
            oldMetrics: atBottom,
            newMetrics: scrolledUp
        )
        #expect(stateAfterScroll.isNearBottom == false)

        let decision = ConversationScrollPolicy.nextStateOnIncomingUpdate(
            state: stateAfterScroll,
            isUserMessage: false
        )
        #expect(decision.shouldScroll == false)
        #expect(decision.nextState.isNearBottom == false)
        #expect(decision.nextState.hasUnreadBelow == true)
    }

    @Test("Staying near bottom continues following even when a large streaming chunk expands content")
    func nearBottomFollowsLargeStreamingChunk() {
        let beforeChunk = ConversationScrollPolicy.Metrics(
            offsetY: 1400, containerHeight: 600, contentHeight: 2000, distanceFromBottom: 0, isScrollable: true
        )
        // Content grew by 220pt before scrollTo runs; offsetY did not move up.
        let afterLargeChunk = ConversationScrollPolicy.Metrics(
            offsetY: 1400, containerHeight: 600, contentHeight: 2220, distanceFromBottom: 220, isScrollable: true
        )

        let state = ConversationScrollPolicy.updatedFollowState(
            current: .init(isNearBottom: true, hasUnreadBelow: false),
            oldMetrics: beforeChunk,
            newMetrics: afterLargeChunk
        )
        #expect(state.isNearBottom == true)

        let decision = ConversationScrollPolicy.nextStateOnIncomingUpdate(
            state: state,
            isUserMessage: false
        )
        #expect(decision.shouldScroll == true)
    }

    @Test("Keyboard resize does not flip follow state")
    func keyboardResizePreservesFollowState() {
        let preKeyboard = ConversationScrollPolicy.Metrics(
            offsetY: 1000, containerHeight: 700, contentHeight: 2000, distanceFromBottom: 300, isScrollable: true
        )
        let withKeyboard = ConversationScrollPolicy.Metrics(
            offsetY: 1000, containerHeight: 420, contentHeight: 2000, distanceFromBottom: 580, isScrollable: true
        )

        let state = ConversationScrollPolicy.updatedFollowState(
            current: .init(isNearBottom: true, hasUnreadBelow: false),
            oldMetrics: preKeyboard,
            newMetrics: withKeyboard
        )
        #expect(state.isNearBottom == true)
    }

    @Test("User sending a message or scrolling back within threshold clears unread and scrolls to bottom")
    func userMessageOrReturnClearsUnread() {
        let scrolledState = ConversationScrollPolicy.FollowState(isNearBottom: false, hasUnreadBelow: true)
        let onSend = ConversationScrollPolicy.nextStateOnIncomingUpdate(state: scrolledState, isUserMessage: true)
        #expect(onSend.shouldScroll == true)
        #expect(onSend.nextState.isNearBottom == true)
        #expect(onSend.nextState.hasUnreadBelow == false)

        let scrolledUp = ConversationScrollPolicy.Metrics(
            offsetY: 1000, containerHeight: 600, contentHeight: 2000, distanceFromBottom: 400, isScrollable: true
        )
        let backNearBottom = ConversationScrollPolicy.Metrics(
            offsetY: 1350, containerHeight: 600, contentHeight: 2000, distanceFromBottom: 50, isScrollable: true
        )
        let onReturn = ConversationScrollPolicy.updatedFollowState(
            current: scrolledState,
            oldMetrics: scrolledUp,
            newMetrics: backNearBottom
        )
        #expect(onReturn.isNearBottom == true)
        #expect(onReturn.hasUnreadBelow == false)
    }
}
