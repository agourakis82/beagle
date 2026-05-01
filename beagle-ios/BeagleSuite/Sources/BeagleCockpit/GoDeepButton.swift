//
//  GoDeepButton.swift
//  BeagleCockpit
//
//  Reusable entry point for Go Deeper — place after any
//  assistant message, thought, or provocation.
//

import SwiftUI
import BeagleCore

struct GoDeepButton: View {
    let prompt: String
    @State private var showGoDeep = false
    @State private var store = GoDeepStore()

    var body: some View {
        Button {
            showGoDeep = true
        } label: {
            HStack(spacing: BeagleSpacing.xxs + 1) {
                Image(systemName: "scope")
                    .font(.system(size: 11, weight: .semibold))
                Text("Go Deeper")
                    .font(BeagleFont.caption.font)
                    .fontWeight(.medium)
            }
            .foregroundStyle(BeagleTheme.truthRemembered)
            .padding(.horizontal, BeagleSpacing.sm + 2)
            .padding(.vertical, BeagleSpacing.xs)
            .background(
                Capsule()
                    .fill(BeagleTheme.truthRemembered.opacity(0.08))
                    .overlay(
                        Capsule()
                            .strokeBorder(BeagleTheme.truthRemembered.opacity(0.15), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .medium), trigger: showGoDeep)
        .sheet(isPresented: $showGoDeep) {
            GoDeepView(store: store, prompt: prompt)
        }
    }
}

// MARK: - Context Menu Action

/// Wraps GoDeepButton for use inside .contextMenu.
/// Uses fullScreenCover to avoid the iOS context-menu-to-sheet presentation issue.
struct GoDeepContextAction: View {
    let prompt: String
    @State private var showSheet = false
    @State private var store = GoDeepStore()

    var body: some View {
        Button {
            showSheet = true
        } label: {
            Label("Go Deeper", systemImage: "scope")
        }
        .sheet(isPresented: $showSheet) {
            GoDeepView(store: store, prompt: prompt)
        }
    }
}
