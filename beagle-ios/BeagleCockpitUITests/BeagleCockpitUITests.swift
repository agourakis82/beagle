//
//  BeagleCockpitUITests.swift
//  BeagleCockpitUITests
//
//  End-to-end UI automation tests (XCUIAutomation) covering BeagleCockpit's
//  critical companion flows: Onboarding -> ChatScreen, ChatComposer state morphing
//  & demo thread reset, ConversationDrawer navigation -> ModelSettingsView
//  (Apple Intelligence tier + DiagnosticsView), DreamInsightsView, and WorkView.
//

import XCTest
import XCUIAutomation

@MainActor
final class BeagleCockpitUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Helpers

    private func makeApp(
        onboardingCompleted: Bool = true,
        extraArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        var args = [
            "--beagle-skip-physio-auth",
            "--ui-testing",
        ]
        if onboardingCompleted {
            args += ["-hasCompletedOnboarding", "YES"]
        } else {
            args.append("--reset-onboarding")
        }
        app.launchArguments = args + extraArguments
        return app
    }

    private func scrollUntilHittable(
        _ element: XCUIElement,
        in container: XCUIElement,
        maxSwipes: Int = 5
    ) {
        var attempts = 0
        while (!element.exists || !element.isHittable) && attempts < maxSwipes {
            container.swipeUp()
            attempts += 1
        }
    }

    // MARK: - 1. First-Launch Onboarding -> Companion Chat

    func testOnboardingFlowTransitionsIntoCompanionChat() throws {
        let app = makeApp(onboardingCompleted: false)
        app.launch()

        // Page 1: Welcome
        XCTAssertTrue(
            app.staticTexts["onboarding.welcomeTitle"].waitForExistence(timeout: 10),
            "Welcome title 'Beagle' should be visible on onboarding page 1"
        )
        let getStartedButton = app.buttons["onboarding.getStartedButton"]
        XCTAssertTrue(getStartedButton.waitForExistence(timeout: 5))
        getStartedButton.tap()

        // Page 2: On-Device Intelligence
        XCTAssertTrue(
            app.staticTexts["onboarding.modelTitle"].waitForExistence(timeout: 5),
            "Model selection page should appear after tapping Get Started"
        )
        let continueButton = app.buttons["onboarding.continueButton"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 5))
        continueButton.tap()

        // Page 3: First Thought capture / Skip
        XCTAssertTrue(
            app.staticTexts["onboarding.captureTitle"].waitForExistence(timeout: 5),
            "First thought capture page should appear after tapping Continue"
        )
        XCTAssertTrue(app.textFields["onboarding.thoughtField"].exists)

        let completeButton = app.buttons["onboarding.completeButton"]
        XCTAssertTrue(completeButton.waitForExistence(timeout: 5))
        completeButton.tap()

        // Transition into Companion ChatScreen
        let composerField = app.textFields["chat.composer.inputField"]
        XCTAssertTrue(
            composerField.waitForExistence(timeout: 10),
            "Completing onboarding should transition into ChatScreen composer"
        )
        XCTAssertTrue(app.buttons["chat.topBar.drawerButton"].exists)
        XCTAssertTrue(app.buttons["chat.topBar.newChatButton"].exists)
    }

    // MARK: - 2. ChatScreen Composer Morphing & Demo Conversation Reset

    func testChatComposerMorphingAndDemoConversationReset() throws {
        let app = makeApp(onboardingCompleted: true, extraArguments: ["--demo-chat"])
        app.launch()

        let composerField = app.textFields["chat.composer.inputField"]
        XCTAssertTrue(composerField.waitForExistence(timeout: 10))

        // Verify seeded `--demo-chat` messages render in the transcript
        let seededUserTurn = app.staticTexts["Acordei meio pra baixo hoje, não sei bem por quê."]
        XCTAssertTrue(
            seededUserTurn.waitForExistence(timeout: 8),
            "Seeded --demo-chat user message should appear on ChatScreen"
        )

        // Verify composer controls in idle state (empty draft -> mic mode "Voz")
        let actionButton = app.buttons["chat.composer.actionButton"]
        XCTAssertTrue(actionButton.exists)
        XCTAssertEqual(actionButton.label, "Voz")
        XCTAssertTrue(app.buttons["chat.composer.depthMenu"].exists)
        XCTAssertTrue(app.buttons["chat.composer.attachMenu"].exists)

        // Tapping top-right "Nova conversa" resets the seeded thread cleanly
        let newChatButton = app.buttons["chat.topBar.newChatButton"]
        XCTAssertTrue(newChatButton.waitForExistence(timeout: 5))
        newChatButton.tap()

        let disappeared = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: disappeared, object: seededUserTurn)
        let waitResult = XCTWaiter.wait(for: [expectation], timeout: 6)
        XCTAssertEqual(waitResult, .completed, "Starting a new chat should clear the demo transcript")

        let titleLabel = app.staticTexts["chat.topBar.title"]
        XCTAssertTrue(titleLabel.waitForExistence(timeout: 5))
        XCTAssertEqual(titleLabel.label, "Nova conversa")

        // Typing into composer morphs actionButton into Send ("Enviar") without destroying identity
        composerField.tap()
        composerField.typeText("Oi")
        XCTAssertEqual(actionButton.label, "Enviar")
        XCTAssertTrue(actionButton.isEnabled)
    }

    // MARK: - 3. ConversationDrawer -> ModelSettingsView (Apple Intelligence + Diagnostics)

    func testDrawerNavigationToModelSettingsAndDiagnostics() throws {
        let app = makeApp(onboardingCompleted: true)
        app.launch()

        let drawerButton = app.buttons["chat.topBar.drawerButton"]
        XCTAssertTrue(drawerButton.waitForExistence(timeout: 10))
        drawerButton.tap()

        // Verify ConversationDrawer opens
        XCTAssertTrue(
            app.navigationBars["Conversas"].waitForExistence(timeout: 6),
            "Tapping top-left drawer button should present Conversas sheet"
        )

        let settingsButton = app.buttons["chat.drawer.settingsButton"]
        let listContainer = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app
        scrollUntilHittable(settingsButton, in: listContainer)
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["chat.drawer.dreamInsightsButton"].exists)
        XCTAssertTrue(app.buttons["chat.drawer.workButton"].exists)

        // Open ModelSettingsView from drawer footer (tests deferred onDismiss coordination)
        settingsButton.tap()

        XCTAssertTrue(
            app.navigationBars["Cérebro · MoE · Voz"].waitForExistence(timeout: 8),
            "ModelSettingsView should present cleanly after ConversationDrawer dismisses"
        )
        XCTAssertTrue(app.buttons["surface.settings.doneButton"].exists)
        XCTAssertTrue(
            app.staticTexts["Apple Intelligence"].waitForExistence(timeout: 5),
            "Device card in ModelSettingsView should display Apple Intelligence tier row"
        )

        // Navigate into DiagnosticsView
        let settingsScroll = app.scrollViews["settings.scrollView"]
        XCTAssertTrue(settingsScroll.waitForExistence(timeout: 5))
        let diagnosticsLink = app.buttons["settings.diagnosticsLink"]
        scrollUntilHittable(diagnosticsLink, in: settingsScroll)
        XCTAssertTrue(diagnosticsLink.waitForExistence(timeout: 5))
        diagnosticsLink.tap()

        XCTAssertTrue(
            app.buttons["diagnostics.runButton"].waitForExistence(timeout: 6),
            "Tapping Diagnostics row should push DiagnosticsView"
        )
    }

    // MARK: - 4. ConversationDrawer -> DreamInsightsView

    func testDrawerNavigationToDreamInsights() throws {
        let app = makeApp(onboardingCompleted: true)
        app.launch()

        let drawerButton = app.buttons["chat.topBar.drawerButton"]
        XCTAssertTrue(drawerButton.waitForExistence(timeout: 10))
        drawerButton.tap()
        XCTAssertTrue(app.navigationBars["Conversas"].waitForExistence(timeout: 6))

        let dreamButton = app.buttons["chat.drawer.dreamInsightsButton"]
        let listContainer = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app
        scrollUntilHittable(dreamButton, in: listContainer)
        XCTAssertTrue(dreamButton.waitForExistence(timeout: 5))
        dreamButton.tap()

        XCTAssertTrue(
            app.navigationBars["Insights da noite"].waitForExistence(timeout: 8),
            "DreamInsightsView should present cleanly after drawer dismissal"
        )

        let dreamDoneButton = app.buttons["surface.dreamInsights.doneButton"]
        XCTAssertTrue(dreamDoneButton.waitForExistence(timeout: 5))
        dreamDoneButton.tap()

        XCTAssertTrue(
            app.textFields["chat.composer.inputField"].waitForExistence(timeout: 6),
            "Closing DreamInsightsView should return to ChatScreen"
        )
    }

    // MARK: - 5. ConversationDrawer -> WorkView

    func testDrawerNavigationToWorkDeck() throws {
        let app = makeApp(onboardingCompleted: true)
        app.launch()

        let drawerButton = app.buttons["chat.topBar.drawerButton"]
        XCTAssertTrue(drawerButton.waitForExistence(timeout: 10))
        drawerButton.tap()
        XCTAssertTrue(app.navigationBars["Conversas"].waitForExistence(timeout: 6))

        let workButton = app.buttons["chat.drawer.workButton"]
        let listContainer = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app
        scrollUntilHittable(workButton, in: listContainer)
        XCTAssertTrue(workButton.waitForExistence(timeout: 5))
        workButton.tap()

        let closeWorkButton = app.buttons["surface.work.closeButton"]
        XCTAssertTrue(
            closeWorkButton.waitForExistence(timeout: 8),
            "WorkView sheet should present cleanly after drawer dismissal"
        )
        closeWorkButton.tap()

        XCTAssertTrue(
            app.textFields["chat.composer.inputField"].waitForExistence(timeout: 6),
            "Closing WorkView should return to ChatScreen"
        )
    }

    // MARK: - 6. DiagnosticsRunner Live Execution & Reset

    func testDiagnosticsRunnerExecutesAndResets() throws {
        let app = makeApp(onboardingCompleted: true)
        app.launch()

        let drawerButton = app.buttons["chat.topBar.drawerButton"]
        XCTAssertTrue(drawerButton.waitForExistence(timeout: 10))
        drawerButton.tap()
        XCTAssertTrue(app.navigationBars["Conversas"].waitForExistence(timeout: 6))

        let settingsButton = app.buttons["chat.drawer.settingsButton"]
        let listContainer = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app
        scrollUntilHittable(settingsButton, in: listContainer)
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()

        XCTAssertTrue(app.navigationBars["Cérebro · MoE · Voz"].waitForExistence(timeout: 8))

        let settingsScroll = app.scrollViews["settings.scrollView"].exists
            ? app.scrollViews["settings.scrollView"]
            : app.scrollViews.firstMatch
        let diagnosticsLink = app.buttons["settings.diagnosticsLink"]
        scrollUntilHittable(diagnosticsLink, in: settingsScroll)
        XCTAssertTrue(diagnosticsLink.waitForExistence(timeout: 5))
        diagnosticsLink.tap()

        XCTAssertTrue(
            app.buttons["diagnostics.runButton"].waitForExistence(timeout: 6),
            "Tapping Diagnostics row should push DiagnosticsView"
        )
        let runAllButton = app.buttons["diagnostics.runAllButton"]
        XCTAssertTrue(
            runAllButton.waitForExistence(timeout: 6),
            "DiagnosticsView should show Run All Tests button in initial pending state"
        )
        runAllButton.tap()

        // Wait for DiagnosticsRunner to finish all probes and transition to Reset state
        let resetButton = app.buttons["diagnostics.resetButton"]
        XCTAssertTrue(
            resetButton.waitForExistence(timeout: 40),
            "DiagnosticsRunner should complete and reveal the Reset button"
        )
        resetButton.tap()

        XCTAssertTrue(
            runAllButton.waitForExistence(timeout: 5),
            "Tapping Reset should restore DiagnosticsView to pending state"
        )
    }

    // MARK: - 7. ConversationDrawer -> DeepExplorationView -> GoDeepView Sheet

    func testDrawerNavigationToDeepExplorationAndGoDeepLaunch() throws {
        let app = makeApp(onboardingCompleted: true)
        app.launch()

        let drawerButton = app.buttons["chat.topBar.drawerButton"]
        XCTAssertTrue(drawerButton.waitForExistence(timeout: 10))
        drawerButton.tap()
        XCTAssertTrue(app.navigationBars["Conversas"].waitForExistence(timeout: 6))

        let deepButton = app.buttons["chat.drawer.deepExplorationButton"]
        let listContainer = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app
        scrollUntilHittable(deepButton, in: listContainer)
        XCTAssertTrue(deepButton.waitForExistence(timeout: 5))
        deepButton.tap()

        let closeDeepButton = app.buttons["surface.deepExploration.closeButton"]
        XCTAssertTrue(
            closeDeepButton.waitForExistence(timeout: 8),
            "DeepExplorationView should present cleanly after drawer dismissal"
        )
        XCTAssertTrue(app.navigationBars["Modo Fundo"].exists)

        // Submit a prompt via BeagleInputBar to launch GoDeepView
        let editor = app.textViews["beagle.inputBar.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText("KEC entropia cortical")

        let sendButton = app.buttons["beagle.inputBar.sendButton"]
        XCTAssertTrue(sendButton.waitForExistence(timeout: 5))
        XCTAssertTrue(sendButton.isEnabled)
        sendButton.tap()

        // GoDeepView modal presents with its toolbar close/cancel control
        let goDeepClose = app.buttons["godeep.toolbar.closeButton"]
        XCTAssertTrue(
            goDeepClose.waitForExistence(timeout: 8),
            "Submitting a deep exploration prompt should present GoDeepView"
        )
        goDeepClose.tap()

        // Dismiss DeepExplorationView back to ChatScreen
        XCTAssertTrue(closeDeepButton.waitForExistence(timeout: 6))
        closeDeepButton.tap()

        XCTAssertTrue(
            app.textFields["chat.composer.inputField"].waitForExistence(timeout: 6),
            "Closing DeepExplorationView should return to ChatScreen"
        )
    }

    // MARK: - 8. Conversation Switching + DailySynthesisView

    func testDrawerConversationSwitchingAndDailySynthesis() throws {
        let app = makeApp(onboardingCompleted: true, extraArguments: ["--demo-history"])
        app.launch()

        let seededUserTurn = app.staticTexts["Acordei meio pra baixo hoje, não sei bem por quê."]
        XCTAssertTrue(seededUserTurn.waitForExistence(timeout: 10))

        // Start a brand-new conversation (clears active screen, keeps demo thread in history)
        let newChatButton = app.buttons["chat.topBar.newChatButton"]
        XCTAssertTrue(newChatButton.waitForExistence(timeout: 5))
        newChatButton.tap()

        let disappeared = NSPredicate(format: "exists == false")
        let waitResult = XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: disappeared, object: seededUserTurn)],
            timeout: 6
        )
        XCTAssertEqual(waitResult, .completed)

        // Open ConversationDrawer and switch back to the seeded demo conversation
        let drawerButton = app.buttons["chat.topBar.drawerButton"]
        XCTAssertTrue(drawerButton.waitForExistence(timeout: 5))
        drawerButton.tap()
        XCTAssertTrue(app.navigationBars["Conversas"].waitForExistence(timeout: 6))

        let drawerList = app.collectionViews.firstMatch
        XCTAssertTrue(drawerList.waitForExistence(timeout: 5))
        let demoRow = drawerList.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Acordei meio pra baixo")
        ).firstMatch
        XCTAssertTrue(
            demoRow.waitForExistence(timeout: 5),
            "Previous demo conversation should remain selectable in ConversationDrawer"
        )
        demoRow.tap()

        XCTAssertTrue(
            seededUserTurn.waitForExistence(timeout: 8),
            "Selecting the demo thread in ConversationDrawer should restore its messages"
        )

        // Open DailySynthesisView from ConversationDrawer and dismiss cleanly
        drawerButton.tap()
        XCTAssertTrue(app.navigationBars["Conversas"].waitForExistence(timeout: 6))

        let dailyButton = app.buttons["chat.drawer.dailySynthesisButton"]
        let listContainer = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app
        scrollUntilHittable(dailyButton, in: listContainer)
        XCTAssertTrue(dailyButton.waitForExistence(timeout: 5))
        dailyButton.tap()

        XCTAssertTrue(
            app.navigationBars["Síntese Matinal"].waitForExistence(timeout: 8),
            "DailySynthesisView should present cleanly after drawer dismissal"
        )
        let closeDailyButton = app.buttons["dailySynthesis.closeButton"]
        XCTAssertTrue(closeDailyButton.waitForExistence(timeout: 5))
        closeDailyButton.tap()

        XCTAssertTrue(
            app.textFields["chat.composer.inputField"].waitForExistence(timeout: 6),
            "Closing DailySynthesisView should return to ChatScreen"
        )
    }
}
