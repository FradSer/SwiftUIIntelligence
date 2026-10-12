import UIKit
import XCTest

@MainActor final class DemoUITests: XCTestCase {
  func testWeatherMetricDetailsWrapAtDefaultAndAccessibilityType() {
    XCUIDevice.shared.orientation = UIDevice.current.userInterfaceIdiom == .pad ? .landscapeLeft : .portrait
    let app = XCUIApplication()
    for category in ["UICTContentSizeCategoryL", "UICTContentSizeCategoryAccessibilityXXXL"] {
      for appearance in ["light", "dark"] {
        app.launchArguments = ["--show-complete", "--appearance", appearance, "-UIPreferredContentSizeCategoryName", category]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["weather-heading"].firstMatch.waitForExistence(timeout: 10))
        let current = app.staticTexts["current-temp-detail"]
        let wind = app.staticTexts["wind-speed-detail"]
        let scroll = app.descendants(matching: .any)["sdk-native-glass-weather"]
        func reveal(_ detail: XCUIElement) {
          for _ in 0..<20 {
            let viewport = scroll.frame.insetBy(dx: 0, dy: 8)
            if detail.exists {
              let rect = detail.frame
              if detail.isHittable && viewport.contains(rect) { break }
              print("Detail reveal: \(detail.identifier) \(rect), viewport \(viewport)")
              if rect.midY < viewport.midY {
                scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).press(forDuration: 0.05, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)))
                continue
              }
            }
            scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)).press(forDuration: 0.05, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)))
          }
        }
        reveal(current)
        XCTAssertTrue(current.isHittable)
        XCTAssertEqual(current.label, "Partly Cloudy")
        XCTAssertTrue(scroll.frame.insetBy(dx: 0, dy: 8).contains(current.frame))
        attach("weather-detail-\(category)-\(appearance)-current", app: app)
        reveal(wind)
        XCTAssertTrue(wind.isHittable)
        XCTAssertEqual(wind.label, "SW Direction")
        XCTAssertTrue(scroll.frame.insetBy(dx: 0, dy: 8).contains(wind.frame))
        attach("weather-detail-\(category)-\(appearance)-wind", app: app)
        app.buttons["expand-preview"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        attach("weather-detail-\(category)-\(appearance)-expanded", app: app)
        app.buttons["Done"].tap()
        app.terminate()
      }
    }
  }

  func testExpandedRealRecordingsAndTypedInteractions() {
    XCUIDevice.shared.orientation = UIDevice.current.userInterfaceIdiom == .pad ? .landscapeLeft : .portrait
    let app = XCUIApplication()
    let cases = [("settings", "Workshop preferences"), ("navigation", "Reading room"), ("schedule", "Workshop schedule"), ("comparison", "Desk lamp comparison"), ("analysis", "Studio attendance"), ("study", "Study session")]
    for appearance in ["light", "dark"] {
      for (name, title) in cases {
        app.launchArguments = ["--expanded-case", name, "--appearance", appearance]
        app.launch()
        XCTAssertTrue(app.staticTexts["expanded-mode"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts[title].firstMatch.waitForExistence(timeout: 10), name)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "sdk-native-glass-document").firstMatch.exists, name)
        attach("expanded-\(name)-\(appearance)", app: app)
        if name == "settings" {
          let field = app.textFields.matching(NSPredicate(format: "label CONTAINS %@", "Display name")).firstMatch
          XCTAssertTrue(field.exists)
          XCTAssertEqual(field.value as? String, "Guest")
          field.tap(); field.doubleTap(); field.typeText("Edited\n")
          XCTAssertEqual(field.value as? String, "Edited")
          let toggle = app.switches.firstMatch
          if !toggle.isHittable { app.swipeUp() }
          toggle.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5)).withOffset(CGVector(dx: -24, dy: 0)).tap()
          XCTAssertEqual(toggle.value as? String, "1")
          let save = app.buttons["Save preferences"].firstMatch
          if !save.isHittable { app.swipeUp() }
          save.tap()
          XCTAssertTrue(app.staticTexts["Host received edited=true, reminders=true."].waitForExistence(timeout: 5))
          attach("expanded-settings-host-\(appearance)", app: app)
        }
        if name == "navigation" {
          app.buttons["Open research notes"].firstMatch.tap()
          XCTAssertTrue(app.staticTexts["Check offline access"].waitForExistence(timeout: 5))
          let toggle = app.switches.firstMatch
          XCTAssertTrue(toggle.exists); toggle.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5)).withOffset(CGVector(dx: -24, dy: 0)).tap()
          XCTAssertEqual(toggle.value as? String, "1")
          attach("expanded-navigation-destination-\(appearance)", app: app)
          app.navigationBars.buttons.element(boundBy: 0).tap()
          XCTAssertTrue(app.buttons["Open research notes"].waitForExistence(timeout: 5))
          app.buttons["Open research notes"].tap()
          XCTAssertEqual(toggle.value as? String, "1")
          attach("expanded-navigation-restored-\(appearance)", app: app)
        }
        if name == "comparison" {
          XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Aurora")).firstMatch.exists)
          XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Ember")).firstMatch.exists)
          XCTAssertTrue(app.staticTexts["Synthetic prices; no purchase action."].exists)
        }
        app.terminate()
      }
    }
  }

  func testNativeGlassServiceAndOrdinaryDocumentsInBothAppearances() {
    prepareOrientation()
    let app = XCUIApplication()
    for appearance in ["light", "dark"] {
      app.launchArguments = ["--model-dashboard", "--model-service", "--show-complete", "--appearance", appearance]
      app.launch()
      XCTAssertTrue(app.staticTexts["512 people"].waitForExistence(timeout: 10))
      XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "sdk-native-glass-document").firstMatch.exists)
      attach("native-glass-service-\(appearance)", app: app)
      app.buttons["expand-preview"].tap()
      XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
      attach("native-glass-service-expanded-\(appearance)", app: app)
      app.terminate()
      app.launchArguments = ["--chat-real-outputs", "--appearance", appearance]
      app.launch()
      send("Create the recorded volunteer plan", app: app)
      waitForRevision(1, app: app)
      if app.buttons["document-panel"].exists { app.buttons["document-panel"].tap() }
      XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "sdk-native-glass-document").firstMatch.waitForExistence(timeout: 10))
      attach("native-glass-ordinary-document-\(appearance)", app: app)
      app.terminate()
    }
  }

  func testNativeGlassReducedTransparencyFallback() {
    let app = XCUIApplication()
    app.launchArguments = ["--sdk-demo", "--appearance", "light", "--test-reduce-transparency"]
    app.launch()
    XCTAssertTrue(app.buttons["greet-button"].waitForExistence(timeout: 10))
    app.buttons["greet-button"].tap()
    XCTAssertTrue(app.staticTexts["Hello from the host app."].exists)
    app.buttons["count-button"].tap()
    XCTAssertTrue(app.staticTexts["Host count: 1"].exists)
    attach("native-glass-system-fallback", app: app)
  }

  func testExpandedTimelineAtAccessibilityType() {
    let app = XCUIApplication()
    app.launchArguments = ["--expanded-case", "schedule", "--appearance", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
    app.launch()
    XCTAssertTrue(app.staticTexts["Workshop schedule"].firstMatch.waitForExistence(timeout: 10))
    attach("expanded-schedule-accessibility-top", app: app)
    let finalDetail = app.staticTexts["Collect feedback"].firstMatch
    for _ in 0..<6 {
      if finalDetail.exists && app.windows.firstMatch.frame.contains(finalDetail.frame) { break }
      app.swipeUp()
    }
    XCTAssertTrue(finalDetail.exists)
    XCTAssertTrue(app.windows.firstMatch.frame.contains(finalDetail.frame))
    attach("expanded-schedule-accessibility-end", app: app)
  }

  func testWeatherLayoutScrollingAndHostControls() {
    XCUIDevice.shared.orientation =
      UIDevice.current.userInterfaceIdiom == .pad ? .landscapeLeft : .portrait
    let app = XCUIApplication()
    app.launchArguments = ["--show-complete"]
    app.launch()
    XCTAssertTrue(app.staticTexts["Weather Dashboard"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["72°F"].exists)
    attach("weather-top", app: app)
    let scroll = app.descendants(matching: .any)["sdk-native-glass-weather"]
    scroll.swipeUp()
    XCTAssertTrue(app.staticTexts["Wind Distribution"].waitForExistence(timeout: 5))
    attach("weather-details", app: app)
    if app.buttons["panel-json"].exists {
      app.buttons["panel-json"].tap()
    }
    app.buttons["copy-json"].tap()
    XCTAssertEqual(app.staticTexts["action-result"].label, "JSON copied to clipboard.")
    if app.buttons["json-tab"].exists {
      app.buttons["json-tab"].tap()
      XCTAssertTrue(app.staticTexts["json-source"].label.contains("weatherDashboard"))
      let completeJSON = app.staticTexts["json-source"].label
      app.buttons["raw-tab"].tap()
      XCTAssertEqual(app.staticTexts["json-source"].label, completeJSON)
    }
    if app.buttons["panel-json"].exists {
      app.buttons["panel-preview"].tap()
    }
    app.buttons["expand-preview"].tap()
    XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
    app.buttons["Done"].tap()
    app.buttons["complete-button"].tap()
    XCTAssertEqual(app.staticTexts["action-result"].label, "All weather components rendered.")
  }

  func testFixedReplayTransitionsAndPause() {
    XCUIDevice.shared.orientation =
      UIDevice.current.userInterfaceIdiom == .pad ? .landscapeLeft : .portrait
    let app = XCUIApplication()
    app.launchArguments = ["--weather-demo"]
    app.launch()
    XCTAssertTrue(app.staticTexts["Rendered UI will appear here"].waitForExistence(timeout: 5))
    attach("replay-empty", app: app)
    XCTAssertTrue(app.staticTexts["Weather Dashboard"].waitForExistence(timeout: 5))
    attach("replay-heading", app: app)
    XCTAssertTrue(app.staticTexts["72°F"].waitForExistence(timeout: 5))
    app.buttons["pause-button"].tap()
    XCTAssertEqual(app.staticTexts["action-result"].label, "Replay paused.")
    XCTAssertFalse(app.activityIndicators["replay-progress"].exists)
    attach("replay-metrics", app: app)
    app.buttons["complete-button"].tap()
    XCTAssertTrue(app.staticTexts["7-Day Temperature Forecast"].waitForExistence(timeout: 5))
    app.buttons["replay-button"].tap()
    XCTAssertTrue(app.staticTexts["Rendered UI will appear here"].waitForExistence(timeout: 5))
    XCTAssertEqual(
      app.staticTexts["action-result"].label, "Replaying fixed JSON (no model request).")
    app.buttons["pause-button"].tap()
  }

  func testMalformedAndUnknownInputShowsFriendlyError() {
    let app = XCUIApplication()
    for fixture in ["bad-json", "unknown-component", "unknown-action"] {
      app.launchArguments = ["--fixture", fixture]
      app.launch()
      XCTAssertTrue(app.staticTexts["Cannot render UI"].waitForExistence(timeout: 10), fixture)
      XCTAssertFalse(app.buttons["replay-button"].exists)
      app.terminate()
    }
  }

  func testFullReplayAutomaticallyShowsDetails() {
    XCUIDevice.shared.orientation =
      UIDevice.current.userInterfaceIdiom == .pad ? .landscapeLeft : .portrait
    let app = XCUIApplication()
    app.launchArguments = ["--weather-demo"]
    app.launch()
    XCTAssertTrue(app.staticTexts["Fixed JSON replay complete."].waitForExistence(timeout: 25))
    let details = app.staticTexts["Conditions Breakdown"]
    XCTAssertTrue(details.waitForExistence(timeout: 3))
    XCTAssertTrue(details.isHittable)
    XCTAssertFalse(app.staticTexts["72°F"].isHittable)
    attach("replay-finale", app: app)
    app.buttons["replay-button"].tap()
    XCTAssertTrue(app.staticTexts["Rendered UI will appear here"].waitForExistence(timeout: 5))
    app.buttons["pause-button"].tap()
  }

  func testGlassReadabilityInLightAndDarkAppearances() {
    XCUIDevice.shared.orientation =
      UIDevice.current.userInterfaceIdiom == .pad ? .landscapeLeft : .portrait
    let app = XCUIApplication()
    for appearance in ["light", "dark"] {
      app.launchArguments = ["--show-complete", "--appearance", appearance]
      app.launch()
      XCTAssertTrue(app.staticTexts["72°F"].waitForExistence(timeout: 10))
      XCTAssertTrue(app.buttons["replay-button"].isHittable)
      attach("glass-\(appearance)-top", app: app)
      if app.buttons["panel-json"].exists { app.buttons["panel-json"].tap() }
      app.buttons["json-tab"].tap()
      XCTAssertTrue(app.staticTexts["json-source"].label.contains("weatherDashboard"))
      attach("glass-\(appearance)-json", app: app)
      if app.buttons["panel-preview"].exists { app.buttons["panel-preview"].tap() }
      app.buttons["expand-preview"].tap()
      XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
      attach("glass-\(appearance)-expanded", app: app)
      app.buttons["Done"].tap()
      let scroll = app.descendants(matching: .any)["sdk-native-glass-weather"]
      scroll.swipeUp()
      if UIDevice.current.userInterfaceIdiom != .pad { scroll.swipeUp() }
      XCTAssertTrue(app.staticTexts["Wind Distribution"].waitForExistence(timeout: 5))
      attach("glass-\(appearance)-details", app: app)
      app.terminate()
    }
  }

  func testGenericSDKGlassAndHostCallbacks() {
    XCUIDevice.shared.orientation =
      UIDevice.current.userInterfaceIdiom == .pad ? .landscapeLeft : .portrait
    let app = XCUIApplication()
    for appearance in ["light", "dark"] {
      app.launchArguments = ["--sdk-demo", "--appearance", appearance]
      app.launch()
      XCTAssertTrue(app.buttons["greet-button"].waitForExistence(timeout: 10))
      app.buttons["greet-button"].tap()
      XCTAssertTrue(app.staticTexts["Hello from the host app."].exists)
      app.buttons["count-button"].tap()
      XCTAssertTrue(app.staticTexts["Host count: 1"].exists)
      attach("glass-\(appearance)-sdk", app: app)
      app.terminate()
    }
  }

  func testSyntheticChatUpdatesCallbacksAndJSON() {
    prepareOrientation()
    let app = XCUIApplication()
    app.launchArguments = ["--chat-fixture", "slow", "--appearance", "light"]
    app.launch()
    XCTAssertTrue(app.staticTexts["Start with an idea"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["chat-provider-label"].label.contains("not AI generation"))
    attach("chat-synthetic-empty", app: app)
    send("Make a volunteer plan", app: app)
    XCTAssertTrue(app.activityIndicators["chat-loading-indicator"].waitForExistence(timeout: 3))
    attach("chat-synthetic-loading", app: app)
    waitForRevision(1, app: app)
    XCTAssertTrue(app.staticTexts["Library volunteer plan"].exists)
    let scroll = app.scrollViews["chat-document-scroll"]
    for _ in 0..<3 { if !app.buttons["ack"].isHittable { scroll.swipeUp() } }
    let composer =
      app.textFields["chat-input"].exists
      ? app.textFields["chat-input"] : app.textViews["chat-input"]
    XCTAssertLessThan(app.buttons["ack"].frame.maxY, composer.frame.minY)
    app.buttons["ack"].tap()
    XCTAssertTrue(app.staticTexts["chat-action-result"].label.contains("Host acknowledged"))
    XCTAssertTrue(app.staticTexts["chat-action-result"].isHittable)
    XCTAssertLessThan(app.staticTexts["chat-action-result"].frame.maxY, composer.frame.minY)
    attach("chat-synthetic-plan", app: app)
    app.buttons["chat-show-json"].tap()
    XCTAssertTrue(app.staticTexts["chat-json-source"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["chat-json-source"].label.contains("\"table\""))
    app.buttons["Done"].tap()
    send("Now make a release handover", app: app)
    waitForRevision(2, app: app)
    XCTAssertTrue(app.staticTexts["Offline notes release handover"].exists)
    attach("chat-synthetic-release", app: app)
    app.buttons["chat-reset"].tap()
    XCTAssertTrue(app.staticTexts["Start with an idea"].waitForExistence(timeout: 5))
  }

  func testChatProviderMalformedAndUnknownResponsesCanRetry() {
    prepareOrientation()
    let app = XCUIApplication()
    for failure in ["provider", "malformed", "unknown"] {
      app.launchArguments = ["--chat-fixture", failure, "--appearance", "dark"]
      app.launch()
      send("Synthetic error test", app: app)
      XCTAssertTrue(app.staticTexts["chat-error"].waitForExistence(timeout: 10))
      XCTAssertTrue(app.buttons["chat-retry"].isHittable)
      attach("chat-error-\(failure)", app: app)
      app.buttons["chat-retry"].tap()
      waitForRevision(1, app: app)
      XCTAssertTrue(app.staticTexts["Library volunteer plan"].exists)
      app.terminate()
    }
  }

  func testRecordedAppleDocumentsInLightAndDark() {
    prepareOrientation()
    let app = XCUIApplication()
    for appearance in ["light", "dark"] {
      app.launchArguments = ["--chat-real-outputs", "--appearance", appearance]
      app.launch()
      XCTAssertTrue(app.staticTexts["chat-provider-label"].waitForExistence(timeout: 10))
      XCTAssertTrue(app.staticTexts["chat-provider-label"].label.contains("generated on Mac"))
      for turn in 1...3 {
        send("Display recorded Mac generation \(turn)", app: app)
        waitForRevision(turn, app: app)
        attach("chat-apple-\(appearance)-turn-\(turn)", app: app)
        if turn == 2 {
          app.scrollViews["chat-document-scroll"].swipeUp()
          let note = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "10 minutes early")
          ).firstMatch
          XCTAssertTrue(note.waitForExistence(timeout: 5))
          XCTAssertTrue(note.isHittable)
          attach("chat-apple-\(appearance)-updated-details", app: app)
        }
        app.buttons["chat-show-json"].tap()
        XCTAssertTrue(app.staticTexts["chat-json-source"].waitForExistence(timeout: 5))
        let json = app.staticTexts["chat-json-source"].label
        XCTAssertTrue(json.contains("\"version\""))
        XCTAssertFalse(json.contains("weatherDashboard"))
        if turn == 2 {
          XCTAssertTrue(json.lowercased().contains("3pm"))
          XCTAssertFalse(json.lowercased().contains("2pm"))
        }
        if turn == 3 {
          XCTAssertTrue(json.lowercased().contains("export"))
          XCTAssertTrue(json.lowercased().contains("pending"))
        }
        if turn == 2 { attach("chat-apple-\(appearance)-json", app: app) }
        app.buttons["Done"].tap()
      }
      app.terminate()
    }
  }

  func testRichAppleOutputInLightAndDark() {
    prepareOrientation()
    let app = XCUIApplication()
    for appearance in ["light", "dark"] {
      app.launchArguments = ["--chat-rich-output", "--appearance", appearance]
      app.launch()
      XCTAssertTrue(app.staticTexts["chat-provider-label"].waitForExistence(timeout: 10))
      XCTAssertTrue(app.staticTexts["chat-provider-label"].label.contains("generated on Mac"))
      send("Display the synthetic workshop dashboard generated on Mac", app: app)
      waitForRevision(1, app: app)
      attach("rich-apple-\(appearance)-top", app: app)
      let scroll = app.scrollViews["chat-document-scroll"]
      for _ in 0..<2 { scroll.swipeUp() }
      attach("rich-apple-\(appearance)-details", app: app)
      app.buttons["chat-show-json"].tap()
      XCTAssertTrue(app.staticTexts["chat-json-source"].waitForExistence(timeout: 5))
      let json = app.staticTexts["chat-json-source"].label
      for kind in ["metric", "badge", "progress", "iconList", "chart"] { XCTAssertTrue(json.contains(kind), kind) }
      XCTAssertFalse(json.contains("weatherDashboard"))
      app.buttons["Done"].tap()
      app.terminate()
    }
  }

  func testGenericCompleteWeatherAndReplayControls() {
    prepareOrientation()
    let app = XCUIApplication()
    for appearance in ["light", "dark"] {
      app.launchArguments = ["--generic-weather", "--show-complete", "--appearance", appearance]
      app.launch()
      XCTAssertTrue(app.staticTexts["Weather Dashboard"].waitForExistence(timeout: 10))
      XCTAssertTrue(app.staticTexts["72°F"].exists)
      attach("generic-weather-\(appearance)-top", app: app)
      let scroll = app.descendants(matching: .any)["sdk-native-glass-document"]
      for _ in 0..<4 { if !app.staticTexts["Forecast Summary"].isHittable { scroll.swipeUp() } }
      XCTAssertTrue(app.staticTexts["Wind Distribution"].exists)
      XCTAssertTrue(app.staticTexts["Forecast Summary"].exists)
      attach("generic-weather-\(appearance)-details", app: app)
      app.buttons["expand-preview"].tap()
      XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
      attach("generic-weather-\(appearance)-expanded", app: app)
      app.buttons["Done"].tap()
      if app.buttons["panel-json"].exists { app.buttons["panel-json"].tap() }
      app.buttons["copy-json"].tap()
      XCTAssertEqual(app.staticTexts["action-result"].label, "JSON copied to clipboard.")
      if app.buttons["panel-preview"].exists { app.buttons["panel-preview"].tap() }
      app.buttons["replay-button"].tap()
      XCTAssertTrue(app.staticTexts["Rendered UI will appear here"].waitForExistence(timeout: 5))
      XCTAssertTrue(app.staticTexts["Weather Dashboard"].waitForExistence(timeout: 5))
      app.buttons["pause-button"].tap()
      XCTAssertEqual(app.staticTexts["action-result"].label, "Replay paused.")
      app.buttons["complete-button"].tap()
      XCTAssertEqual(app.staticTexts["action-result"].label, "All weather components rendered.")
      app.terminate()
    }
  }

  func testGenericWeatherAutomaticallyScrollsToDetails() {
    prepareOrientation()
    let app = XCUIApplication()
    app.launchArguments = ["--generic-weather"]
    app.launch()
    XCTAssertTrue(app.staticTexts["Fixed JSON replay complete."].waitForExistence(timeout: 25))
    let details = app.staticTexts["Hourly Forecast"]
    XCTAssertTrue(details.waitForExistence(timeout: 5))
    XCTAssertTrue(details.isHittable)
    XCTAssertFalse(app.staticTexts["72°F"].isHittable)
    attach("generic-weather-auto-scroll", app: app)
    app.buttons["pause-button"].tap()
  }

  func testZRecordedModelDashboardAndControls() {
    prepareOrientation()
    let app = XCUIApplication()
    for appearance in ["light", "dark"] {
      app.launchArguments = ["--model-dashboard", "--show-complete", "--appearance", appearance]
      app.launch()
      XCTAssertTrue(app.staticTexts["72°F"].waitForExistence(timeout: 10))
      XCTAssertTrue(app.staticTexts["Recorded Apple model output · generated on Mac"].exists)
      attach("model-weather-\(appearance)-top", app: app)
      let scroll = app.descendants(matching: .any)["sdk-native-glass-document"]
      for _ in 0..<12 {
        if app.staticTexts.matching(NSPredicate(format: "label == %@", "Wind Distribution")).allElementsBoundByIndex.contains(where: { $0.isHittable }) { break }
        scroll.swipeUp(velocity: .slow)
      }
      XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", "Wind Distribution")).allElementsBoundByIndex.contains(where: { $0.isHittable }))
      attach("model-weather-\(appearance)-details", app: app)
      app.buttons["expand-preview"].tap()
      XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
      attach("model-weather-\(appearance)-expanded", app: app)
      let expandedScroll = app.descendants(matching: .any)["sdk-native-glass-document"].firstMatch
      for (prefix, module) in [("7-Day", "temperature"), ("Precipitation", "precipitation"), ("Hourly Forecast", "hourly"), ("Conditions Breakdown", "radar"), ("Wind Distribution", "wind")] {
        captureModelModule(prefix, name: "model-weather-\(appearance)-module-\(module)", app: app, scroll: expandedScroll)
      }
      app.buttons["Done"].tap()
      if app.buttons["panel-json"].exists { app.buttons["panel-json"].tap() }
      app.buttons["json-tab"].tap()
      let json = app.staticTexts["json-source"].label
      for kind in ["metric", "grid", "iconList", "line", "area", "radar", "donut", "badge"] { XCTAssertTrue(json.contains(kind), kind) }
      XCTAssertFalse(json.contains("weatherDashboard"))
      app.buttons["copy-json"].tap()
      XCTAssertEqual(app.staticTexts["action-result"].label, "JSON copied to clipboard.")
      if app.buttons["panel-preview"].exists { app.buttons["panel-preview"].tap() }
      app.buttons["replay-button"].tap()
      XCTAssertTrue(app.staticTexts["72°F"].waitForExistence(timeout: 10))
      app.buttons["pause-button"].tap()
      XCTAssertEqual(app.staticTexts["action-result"].label, "Replay paused.")
      XCTAssertFalse(app.activityIndicators["replay-progress"].exists)
      app.buttons["complete-button"].tap()
      XCTAssertEqual(app.staticTexts["action-result"].label, "All model components rendered.")
      app.terminate()
    }
  }

  func testRecordedModelReplayAutoScroll() {
    prepareOrientation()
    let app = XCUIApplication()
    app.launchArguments = ["--model-dashboard", "--appearance", "dark"]
    app.launch()
    XCTAssertTrue(app.staticTexts["Recorded Apple JSON replay complete."].waitForExistence(timeout: 25))
    XCTAssertFalse(app.staticTexts["72°F"].isHittable)
    attach("model-weather-auto-scroll", app: app)
  }

  func testRecordedModelServiceDashboard() {
    prepareOrientation()
    let app = XCUIApplication()
    app.launchArguments = ["--model-dashboard", "--model-service", "--show-complete", "--appearance", "light"]
    app.launch()
    XCTAssertTrue(app.staticTexts["512 people"].waitForExistence(timeout: 10))
    attach("model-service-light-top", app: app)
    app.buttons["expand-preview"].tap()
    XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
    let expandedScroll = app.descendants(matching: .any)["sdk-native-glass-document"].firstMatch
    for (prefix, module) in [("Latency trend", "line"), ("Completed tasks", "bar"), ("Tickets", "donut")] {
      captureModelModule(prefix, name: "model-service-light-module-\(module)", app: app, scroll: expandedScroll)
    }
    app.buttons["Done"].tap()
    let scroll = app.descendants(matching: .any)["sdk-native-glass-document"]
    for _ in 0..<6 { scroll.swipeUp() }
    attach("model-service-light-details", app: app)
    if app.buttons["panel-json"].exists { app.buttons["panel-json"].tap() }
    app.buttons["json-tab"].tap()
    let json = app.staticTexts["json-source"].label
    for kind in ["metric", "grid", "progress", "line", "bar", "donut", "iconList", "badge"] { XCTAssertTrue(json.contains(kind), kind) }
    XCTAssertFalse(json.contains("Weather"))
  }

  private func captureModelModule(_ prefix: String, name: String, app: XCUIApplication, scroll: XCUIElement) {
    let titles = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", prefix))
    var foundVisibleModule = false
    for _ in 0..<12 {
      if let title = titles.allElementsBoundByIndex.first(where: { $0.isHittable }) {
        foundVisibleModule = true
        let window = app.windows.firstMatch.frame
        let distance = title.frame.minY - app.buttons["Done"].frame.maxY - 32
        if distance > 30 && window.height > 0 {
          let fraction = min(0.55, distance / window.height)
          let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.85))
          let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.85 - fraction))
          start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        break
      }
      scroll.swipeUp(velocity: .slow)
    }
    XCTAssertTrue(foundVisibleModule, prefix)
    attach(name, app: app)
  }

  private func prepareOrientation() {
    XCUIDevice.shared.orientation =
      UIDevice.current.userInterfaceIdiom == .pad ? .landscapeLeft : .portrait
  }
  private func send(_ text: String, app: XCUIApplication) {
    let input =
      app.textFields["chat-input"].exists
      ? app.textFields["chat-input"] : app.textViews["chat-input"]
    XCTAssertTrue(input.waitForExistence(timeout: 5))
    input.tap()
    input.typeText(text)
    app.buttons["chat-send"].tap()
  }
  private func waitForRevision(_ revision: Int, app: XCUIApplication) {
    let status = app.staticTexts["chat-revision"]
    let expected = NSPredicate(format: "label == %@", "DOCUMENT · \(revision)")
    expectation(for: expected, evaluatedWith: status)
    waitForExpectations(timeout: 15)
  }

  private func attach(_ name: String, app: XCUIApplication) {
    // App-only captures crop incorrectly after rotation on this runtime.
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
