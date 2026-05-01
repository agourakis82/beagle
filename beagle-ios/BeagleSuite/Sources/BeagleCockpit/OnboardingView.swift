//
//  OnboardingView.swift
//  BeagleCockpit
//
//  First-launch experience — warm, explanatory, local-first.
//  3 screens: what the exocortex is, pick a model, capture first thought.
//  No Tailnet required — everything works on-device from step 1.
//

import SwiftUI
import BeagleCore

struct OnboardingView: View {
    @Binding var isComplete: Bool
    @State private var page = 0
    @State private var firstThought = ""
    @State private var selectedModel: OnDeviceModel = .recommended
    @State private var hasAppeared = false

    var body: some View {
        TabView(selection: $page) {
            welcomePage.tag(0)
            modelPage.tag(1)
            capturePage.tag(2)
        }
        .modifier(OnboardingPagingStyle())
        .background(onboardingGradient)
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) { hasAppeared = true }
        }
    }

    // MARK: - Page 1: Welcome

    private var welcomePage: some View {
        VStack(spacing: BeagleSpacing.xl) {
            Spacer()

            PresencePill(label: BuildInfo.previewLabel, systemImage: "bolt.badge.clock.fill", tint: BeagleTheme.postureWarm)

            Image(systemName: "brain.head.profile")
                .font(.system(size: 56))
                .foregroundStyle(
                    LinearGradient(
                        colors: [BeagleTheme.truthObserved, BeagleTheme.truthRemembered],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .opacity(hasAppeared ? 1 : 0)
                .scaleEffect(hasAppeared ? 1 : 0.8)
                .animation(.spring(duration: 0.8, bounce: 0.3), value: hasAppeared)

            VStack(spacing: BeagleSpacing.md) {
                Text("Beagle")
                    .font(BeagleFont.title1.font)
                    .foregroundStyle(BeagleTheme.textPrimary)

                Text("A private mind in your hand that can interface with a larger living intelligence when you want more reach.")
                    .font(BeagleFont.body.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, BeagleSpacing.xxl)

                Text("This preview makes the bridge obvious from the first screen.")
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.postureWarm)
            }
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 20)
            .animation(.easeOut(duration: 0.6).delay(0.3), value: hasAppeared)

            VStack(spacing: BeagleSpacing.sm) {
                featureRow(icon: "lock.shield.fill", text: "Start privately on-device. Your thoughts are yours first.", color: BeagleTheme.truthObserved)
                featureRow(icon: "scope", text: "Explore an idea deeply when the thread deserves it.", color: BeagleTheme.truthRemembered)
                featureRow(icon: "server.rack", text: "When you're ready, the cluster mind can carry the work further.", color: BeagleTheme.postureWarm)
            }
            .padding(.horizontal, BeagleSpacing.lg)
            .opacity(hasAppeared ? 1 : 0)
            .animation(.easeOut(duration: 0.6).delay(0.5), value: hasAppeared)

            Spacer()

            VStack(spacing: BeagleSpacing.md) {
                pageIndicator
                nextButton("Get Started") { page = 1 }
            }
        }
        .padding(BeagleSpacing.lg)
    }

    // MARK: - Page 2: Choose Model

    private var modelPage: some View {
        VStack(spacing: BeagleSpacing.xl) {
            Spacer(minLength: BeagleSpacing.xxl)

            Image(systemName: "cpu")
                .font(.system(size: 40))
                .foregroundStyle(BeagleTheme.postureWarm)

            VStack(spacing: BeagleSpacing.sm) {
                Text("On-Device Intelligence")
                    .font(BeagleFont.title2.font)
                    .foregroundStyle(BeagleTheme.textPrimary)

                Text("Choose a model that runs entirely on your \(deviceName). No cloud required.")
                    .font(BeagleFont.subheadline.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BeagleSpacing.lg)
            }

            // Recommended model card
            VStack(spacing: BeagleSpacing.sm) {
                let model = OnDeviceModel.recommended
                GlassPanel(elevation: .raised, truth: .observed) {
                    VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
                        HStack {
                            Image(systemName: "star.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(BeagleTheme.postureWarm)
                            Text("Recommended for your device")
                                .font(BeagleFont.caption.font)
                                .foregroundStyle(BeagleTheme.postureWarm)
                        }
                        Text(model.displayName)
                            .font(BeagleFont.headline.font)
                            .foregroundStyle(BeagleTheme.textPrimary)
                        Text(model.bestFor)
                            .font(BeagleFont.caption.font)
                            .foregroundStyle(BeagleTheme.textSecondary)
                            .lineLimit(2)
                        Text("\(model.parameterCount) · \(model.sizeDescription)")
                            .font(BeagleFont.dataSmall.font)
                            .foregroundStyle(BeagleTheme.textTertiary)
                    }
                }
                .padding(.horizontal, BeagleSpacing.lg)

                Text("You can change this anytime in settings.")
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textTertiary)
            }

            Spacer()

            VStack(spacing: BeagleSpacing.md) {
                pageIndicator
                nextButton("Continue") { page = 2 }
            }
        }
        .padding(BeagleSpacing.lg)
    }

    // MARK: - Page 3: First Thought

    private var capturePage: some View {
        VStack(spacing: BeagleSpacing.xl) {
            Spacer(minLength: BeagleSpacing.xxl)

            Image(systemName: "thought.bubble")
                .font(.system(size: 40))
                .foregroundStyle(BeagleTheme.truthRemembered)

            VStack(spacing: BeagleSpacing.sm) {
                Text("Your First Thought")
                    .font(BeagleFont.title2.font)
                    .foregroundStyle(BeagleTheme.textPrimary)

                Text("What's on your mind right now? Anything at all. This is the beginning of your first thread with Beagle.")
                    .font(BeagleFont.subheadline.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BeagleSpacing.md)
                    .lineSpacing(2)
            }

            TextField("Write your first thought...", text: $firstThought, axis: .vertical)
                .font(BeagleFont.body.font)
                .foregroundStyle(BeagleTheme.textPrimary)
                .lineLimit(3...6)
                .padding(BeagleSpacing.md)
                .background(
                    RoundedRectangle(cornerRadius: BeagleRadius.lg)
                        .fill(BeagleTheme.surface1.opacity(0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: BeagleRadius.lg)
                        .strokeBorder(BeagleTheme.truthRemembered.opacity(0.12), lineWidth: 1)
                )
                .padding(.horizontal, BeagleSpacing.md)

            Spacer()

            VStack(spacing: BeagleSpacing.md) {
                pageIndicator

                Button {
                    completeOnboarding()
                } label: {
                    Text(firstThought.isEmpty ? "Skip for now" : "Begin")
                        .font(BeagleFont.body.font)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, BeagleSpacing.md)
                        .background(
                            Capsule()
                                .fill(
                                    firstThought.isEmpty
                                    ? BeagleTheme.textTertiary
                                    : BeagleTheme.truthObserved
                                )
                        )
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.success, trigger: isComplete)
            }
        }
        .padding(BeagleSpacing.lg)
    }

    // MARK: - Helpers

    private func featureRow(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: BeagleSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
                .frame(width: 24)
            Text(text)
                .font(BeagleFont.footnote.font)
                .foregroundStyle(BeagleTheme.textSecondary)
                .lineSpacing(1)
        }
    }

    private func nextButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(BeagleMotion.snappy) { action() }
        } label: {
            Text(label)
                .font(BeagleFont.body.font)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, BeagleSpacing.md)
                .background(
                    Capsule().fill(BeagleTheme.truthObserved)
                        .shadow(color: BeagleTheme.truthObserved.opacity(0.3), radius: 12, y: 6)
                )
        }
        .buttonStyle(.plain)
    }

    private var pageIndicator: some View {
        HStack(spacing: BeagleSpacing.xs) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(index == page ? BeagleTheme.textPrimary : BeagleTheme.textTertiary.opacity(0.45))
                    .frame(width: index == page ? 20 : 8, height: 8)
                    .animation(BeagleMotion.snappy, value: page)
            }
        }
        .padding(.horizontal, BeagleSpacing.md)
        .padding(.vertical, BeagleSpacing.xs)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func completeOnboarding() {
        if !firstThought.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Task {
                _ = await BeagleClient.shared.captureThought(
                    text: firstThought, source: "onboarding"
                )
            }
        }
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        withAnimation(BeagleMotion.slow) { isComplete = true }
    }

    private var deviceName: String {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #else
        return "Mac"
        #endif
    }

    private var onboardingGradient: some View {
        LinearGradient(
            colors: [
                Color(hue: 230/360, saturation: 0.4, brightness: 0.08),
                BeagleTheme.surface0,
                Color(red: 0.02, green: 0.03, blue: 0.06)
            ],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

private struct OnboardingPagingStyle: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .tabViewStyle(.page(indexDisplayMode: .never))
        #else
        content
        #endif
    }
}
