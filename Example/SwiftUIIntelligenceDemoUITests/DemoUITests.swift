import UIKit
import XCTest

@MainActor final class DemoUITests: XCTestCase {
  func testPublicWrapperRetainsOriginalAndDetailsAcrossFailureRetryReset() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["--public-wrapper-fixture"]
    app.launch()
    let input = app.textFields["generated-prompt"]
    XCTAssertTrue(input.waitForExistence(timeout: 5))
    input.tap(); input.typeText("First original passage")
    app.buttons["generated-send"].tap()
    XCTAssertTrue(app.staticTexts["Synthetic public wrapper result"].waitForExistence(timeout: 10))
    if UIDevice.current.userInterfaceIdiom == .pad {
      let chat = app.buttons["generated-chat-tab"]
      XCTAssertTrue(chat.waitForExistence(timeout: 5))
      chat.tap()
      XCTAssertTrue(app.staticTexts["generated-chat-message-0"].label.contains("First original passage"))
      app.buttons["generated-original-tab"].tap()
    }
    let original = app.buttons["generated-original-button"]
    XCTAssertTrue(original.waitForExistence(timeout: 5))
    original.tap()
    let sourcePanel = app.otherElements["generated-original-panel"]
    XCTAssertTrue(sourcePanel.waitForExistence(timeout: 5))
    XCTAssertEqual(sourcePanel.staticTexts["generated-source-text-0"].label, "First original passage")
    app.buttons["Done"].tap()
    app.buttons["generated-details-button"].tap()
    let json = app.staticTexts["generated-details-json"]
    XCTAssertTrue(json.waitForExistence(timeout: 5))
    let completeJSON = json.label
    XCTAssertTrue(completeJSON.contains("wrapper-result"))
    app.buttons["generated-copy-json"].tap()
    app.buttons["Done"].tap()
    input.tap()
    input.press(forDuration: 1.2)
    XCTAssertTrue(app.menuItems["Paste"].waitForExistence(timeout: 3))
    app.menuItems["Paste"].tap()
    XCTAssertEqual(input.value as? String, completeJSON)
    input.tap(); input.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: (input.value as? String ?? "").count))
    input.tap(); input.typeText("Second original passage")
    app.buttons["generated-send"].tap()
    XCTAssertTrue(app.staticTexts["Synthetic wrapper failure"].waitForExistence(timeout: 10))
    original.tap()
    XCTAssertEqual(app.otherElements["generated-original-panel"].staticTexts["generated-source-text-1"].label, "Second original passage")
    app.buttons["Done"].tap()
    app.buttons["Retry"].tap()
    XCTAssertTrue(app.buttons["Retry"].waitForNonExistence(timeout: 10))
    app.buttons["generated-details-button"].tap()
    XCTAssertTrue(app.staticTexts["generated-details-revision"].label.contains("2"))
    app.buttons["Done"].tap()
    app.buttons["generated-reset"].tap()
    XCTAssertFalse(app.buttons["generated-original-button"].isEnabled)
    XCTAssertFalse(app.staticTexts["Synthetic public wrapper result"].exists)
  }

  func testNativeSyntheticEquipmentInteractions() {
    verifyNativeEquipment(appearance: "light")
  }

  func testNativeSyntheticBillInteractions() {
    verifyNativeBill(appearance: "light")
  }

  func testNativeSyntheticEquipmentInteractionsInDarkAppearance() {
    verifyNativeEquipment(appearance: "dark")
  }

  func testNativeSyntheticBillInteractionsInDarkAppearance() {
    verifyNativeBill(appearance: "dark")
  }

  func testCaptureLiveEquipment() {
    let app = launchNativeFixture("live-equipment", example: "Equipment comparison", appearance: "light")
    attach("live-equipment-light", app: app)
  }

  func testCaptureLiveMeal() {
    let app = launchNativeFixture("live-meal", example: "Meal plan", appearance: "light")
    attach("live-meal-light", app: app)
  }

  func testCaptureLiveBill() {
    let app = launchNativeFixture("live-bill", example: "Split bill", appearance: "light")
    attach("live-bill-light", app: app)
  }

  func testCaptureModernHotelsParis() {
    continueAfterFailure = false
    prepareOrientation()
    let app = XCUIApplication()
    app.launchArguments = ["--chat-document-file", "Documents/paris-hotels.json", "--chat-fixture", "none"]
    app.launch()
    send("Paris offers a wide selection of modern-design hotels that blend contemporary architecture, thoughtful interiors, and premium hospitality.", app: app)
    XCTAssertTrue(app.staticTexts["Modern Hotels in Paris"].waitForExistence(timeout: 10))
    if app.buttons["document-panel"].exists { app.buttons["document-panel"].tap() }
    // Allow async image loading from network to complete before taking the screenshot
    Thread.sleep(forTimeInterval: 2.5)
    attach("openui-modern-hotels-paris", app: app)
  }

  private func launchNativeFixture(_ fixture: String, example: String, appearance: String) -> XCUIApplication {
    continueAfterFailure = false
    prepareOrientation()
    let app = XCUIApplication()
    app.launchArguments = ["--chat-document-file", "Documents/\(fixture).json",
      "--interactive-examples", "--appearance", appearance]
    app.launch()
    // Given an exported synthetic document, select acceptance explicitly before Send.
    let selection = app.buttons[example]
    XCTAssertTrue(selection.waitForExistence(timeout: 5))
    selection.tap()
    XCTAssertEqual(app.staticTexts["example-acceptance"].label,
      "Selected example acceptance: \(example)")
    app.buttons["chat-send"].tap()
    XCTAssertTrue(app.buttons["original-source"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.staticTexts["chat-error"].exists)
    if app.buttons["document-panel"].exists { app.buttons["document-panel"].tap() }
    return app
  }

  private func verifyNativeEquipment(appearance: String) {
    let app = launchNativeFixture("equipment", example: "Equipment comparison", appearance: appearance)
    assertNativeCell("matches:mapped-tree:selected:1", text: "True", app: app)
    assertNativeCell("matches:mapped-ground:selected:1", text: "False", app: app)
    assertEquipmentChart([("Cedar", "price", 120), ("Cedar", "weight", 900),
      ("Moss", "price", 85), ("Moss", "weight", 1200)], app: app)
    attachNative("equipment-\(appearance)-initial", app: app)

    // When selection changes, derived selection changes, but chart points do not filter.
    toggleNative("selector:mapped-ground:selected:1", app: app)
    assertNativeCell("matches:mapped-ground:selected:1", text: "True", app: app)
    toggleNative("selector:mapped-ground:selected:1", app: app)
    assertNativeCell("matches:mapped-ground:selected:1", text: "False", app: app)
    assertEquipmentChart([("Cedar", "price", 120), ("Cedar", "weight", 900),
      ("Moss", "price", 85), ("Moss", "weight", 1200)], app: app)

    // Then cumulative bounds remove Cedar, remove Moss, and restore both candidates.
    replaceNativeNumber("bounds:mapped-money:maximum:2", with: "100", app: app)
    XCTAssertFalse(app.staticTexts["matches:mapped-tree:name:0"].exists)
    assertNativeCell("matches:mapped-ground:name:0", text: "Moss", app: app)
    assertEquipmentChart([("Moss", "price", 85), ("Moss", "weight", 1200)], app: app)
    replaceNativeNumber("bounds:mapped-mass:maximum:2", with: "1000", app: app)
    XCTAssertFalse(app.staticTexts["matches:mapped-ground:name:0"].exists)
    assertEquipmentChart([], app: app)
    XCTAssertTrue(app.staticTexts["No matching items."].firstMatch.exists)
    replaceNativeNumber("bounds:mapped-money:maximum:2", with: "130", app: app)
    replaceNativeNumber("bounds:mapped-mass:maximum:2", with: "1300", app: app)
    assertNativeCell("matches:mapped-tree:name:0", text: "Cedar", app: app)
    assertNativeCell("matches:mapped-ground:name:0", text: "Moss", app: app)
    assertEquipmentChart([("Cedar", "price", 120), ("Cedar", "weight", 900),
      ("Moss", "price", 85), ("Moss", "weight", 1200)], app: app)
    attachNative("equipment-\(appearance)-edited-restored", app: app)
  }

  private func verifyNativeBill(appearance: String) {
    let app = launchNativeFixture("bill", example: "Split bill", appearance: appearance)
    // Worked integer expectations, independent of the app calculation registry:
    // Soup 1001 / 2 -> 501,500; Tea 502 / 2 -> 251,251.
    // Fees use proportional largest remainders, with person-ID tie breaking.
    assertNativeBill(payable: 1654, food: [501, 751, 251], fees: [50, 76, 25],
      totals: [551, 827, 276], soup: [501, 500, nil], app: app)
    attachNative("bill-\(appearance)-initial", app: app)

    // When item, fee, and participation edits accumulate, every output must update.
    replaceNativeNumber("items-editor:mapped-soup:amountMinor:1", with: "1003", app: app)
    assertNativeBill(payable: 1656, food: [502, 752, 251], fees: [50, 76, 25],
      totals: [552, 828, 276], soup: [502, 501, nil], app: app)
    let increment = app.buttons["fee-editor-Increment"]
    revealNative(increment, app: app)
    increment.tap()
    increment.tap()
    assertNativeBill(payable: 1658, food: [502, 752, 251], fees: [51, 76, 26],
      totals: [553, 828, 277], soup: [502, 501, nil], app: app)
    toggleNative("matrix-editor:mapped-pair-0-2:included:2", app: app)
    // Soup 1003 / 3 -> 335,334,334; food -> 335,585,585.
    assertNativeBill(payable: 1658, food: [335, 585, 585], fees: [34, 60, 59],
      totals: [369, 645, 644], soup: [335, 334, 334], app: app)
    attachNative("bill-\(appearance)-edited", app: app)
  }

  private func assertNativeBill(payable: Int, food: [Int], fees: [Int], totals: [Int],
    soup: [Int?], app: XCUIApplication) {
    for person in 0..<3 {
      let prefix = "people-output:mapped-person-\(person)"
      assertNativeCell(prefix + ":name:0", text: ["Ada", "Bo", "Cy"][person], app: app)
      assertNativeNumber(prefix + ":foodMinor:1", expected: food[person], app: app)
      assertNativeNumber(prefix + ":feeMinor:2", expected: fees[person], app: app)
      assertNativeNumber(prefix + ":totalMinor:3", expected: totals[person], app: app)
      let share = "shares-output:mapped-pair-0-\(person):amountMinor:2"
      if let amount = soup[person] { assertNativeNumber(share, expected: amount, app: app) }
      else { XCTAssertFalse(app.staticTexts[share].exists) }
    }
    XCTAssertFalse(app.staticTexts["shares-output:mapped-pair-1-0:amountMinor:2"].exists)
    for person in 1...2 {
      assertNativeNumber("shares-output:mapped-pair-1-\(person):amountMinor:2", expected: 251, app: app)
    }
    let metric = app.staticTexts.matching(identifier: "payable-output").matching(NSPredicate(format: "label == %@", String(payable))).firstMatch
    let scroll = app.scrollViews["chat-document-scroll"]
    for _ in 0..<8 {
      if metric.exists && metric.frame.intersects(scroll.frame) { break }
      scroll.swipeUp()
    }
    XCTAssertTrue(metric.exists, "Expected payable \(payable) in the rendered metric")
    XCTAssertEqual(metric.label, String(payable))
    XCTAssertFalse(app.staticTexts["calculation-error"].exists)
  }

  private func assertNativeCell(_ identifier: String, text: String, app: XCUIApplication) {
    let cell = app.staticTexts[identifier]
    let exists = cell.waitForExistence(timeout: 5)
    if !exists { attachNativeAccessibility(app, reason: identifier) }
    XCTAssertTrue(exists, identifier)
    XCTAssertEqual(cell.label, text, identifier)
  }

  private func assertNativeNumber(_ identifier: String, expected: Int, app: XCUIApplication) {
    let cell = app.staticTexts[identifier]
    XCTAssertTrue(cell.waitForExistence(timeout: 5), identifier)
    XCTAssertEqual(Double(cell.label.replacingOccurrences(of: ",", with: "")), Double(expected), identifier)
  }

  private func assertEquipmentChart(_ points: [(String, String, Int)], app: XCUIApplication) {
    // Inspect only actual Swift Charts accessibility descendants, never table cells.
    let chart = app.otherElements.matching(identifier: "plot").firstMatch
    if points.isEmpty {
      let title = app.staticTexts["Price (USD) and weight (g)"].firstMatch
      revealNative(title, app: app)
      XCTAssertTrue(title.exists)
      XCTAssertFalse(app.staticTexts["Cedar, price"].exists)
      XCTAssertFalse(app.staticTexts["Moss, price"].exists)
      XCTAssertFalse(app.staticTexts["Cedar, weight"].exists)
      XCTAssertFalse(app.staticTexts["Moss, weight"].exists)
      return
    }
    revealNative(chart, app: app)
    let marks = chart.descendants(matching: .any).allElementsBoundByIndex.filter {
      !$0.label.isEmpty && $0.label != "Price (USD) and weight (g)"
        && ($0.value as? String)?.isEmpty == false
    }
    XCTAssertEqual(marks.count, points.count,
      "Expected individual accessible chart measurements, got: \(marks.map { "\($0.label): \(String(describing: $0.value))" })")
    for (name, series, value) in points {
      let matches = marks.filter { mark in
        let label = mark.label
        let output = (mark.value as? String ?? "").replacingOccurrences(of: ",", with: "")
        return label.contains(name) && (label.contains(series) || output.contains(series))
          && output.split(whereSeparator: { !$0.isNumber && $0 != "." }).contains(Substring(String(value)))
      }
      XCTAssertEqual(matches.count, 1, "Missing actual chart point: \(name), \(series), \(value)")
    }
  }

  private func replaceNativeNumber(_ identifier: String, with value: String, app: XCUIApplication) {
    let field = app.textFields[identifier]
    revealNative(field, app: app)
    field.tap()
    field.press(forDuration: 1.2)
    if app.menuItems["Select All"].waitForExistence(timeout: 2) {
      app.menuItems["Select All"].tap()
    } else {
      field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20))
    }
    field.typeText(value + "\n")
    XCTAssertEqual(Double((field.value as? String ?? "").replacingOccurrences(of: ",", with: "")), Double(value))
  }

  private func toggleNative(_ identifier: String, app: XCUIApplication) {
    let control = app.switches[identifier]
    revealNative(control, app: app)
    let before = control.value as? String
    if control.switches.firstMatch.exists { control.switches.firstMatch.tap() } else { control.tap() }
    XCTAssertNotEqual(control.value as? String, before)
  }

  private func revealNative(_ element: XCUIElement, app: XCUIApplication) {
    let scroll = app.scrollViews["chat-document-scroll"]
    for _ in 0..<12 {
      if element.isHittable { return }
      if element.exists && element.frame.midY < scroll.frame.midY { scroll.swipeDown() }
      else { scroll.swipeUp() }
    }
    XCTAssertTrue(element.isHittable, element.identifier)
  }

  private func attachNativeAccessibility(_ app: XCUIApplication, reason: String) {
    let tree = app.debugDescription
    print("Native accessibility at \(reason):\n\(tree)")
    for label in ["Cedar", "Moss"] {
      for element in app.otherElements.matching(NSPredicate(format: "label == %@", label)).allElementsBoundByIndex {
        print("Actual chart accessibility label=\(element.label), value=\(String(describing: element.value))")
      }
    }
    let attachment = XCTAttachment(string: tree)
    attachment.name = "synthetic-native-accessibility-\(reason)"
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  private func attachNative(_ name: String, app: XCUIApplication) {
    let device = UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "phone"
    if name.hasPrefix("bill-") {
      let label = app.staticTexts.matching(identifier: "payable-output").matching(NSPredicate(format: "label == %@", "Payable (MINOR UNITS)")).firstMatch
      let scroll = app.scrollViews["chat-document-scroll"]
      for _ in 0..<8 {
        if label.exists && label.frame.intersects(scroll.frame) { break }
        scroll.swipeUp()
      }
      XCTAssertTrue(label.exists)
    }
    attach("synthetic-native-\(device)-\(name)", app: app)
  }

  func testDebugSimulatorLoadsStagedSyntheticDocumentThroughSession() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["--chat-document-file", "Documents/native-smoke.json", "--chat-fixture", "none"]
    app.launch()
    send("Render staged synthetic document", app: app)
    XCTAssertTrue(app.staticTexts["Staged synthetic interaction fixture"].waitForExistence(timeout: 10))
    waitForRevision(1, app: app)
  }

  func testDebugSimulatorFixtureRejectsMissingAndEscapingPaths() {
    continueAfterFailure = false
    for arguments in [[], ["/etc/hosts"], ["Documents/../native-smoke.json"]] {
      let app = XCUIApplication()
      app.launchArguments = ["--chat-fixture", "none", "--chat-document-file"] + arguments
      app.launch()
      send("Reject an invalid synthetic fixture path", app: app)
      XCTAssertTrue(app.staticTexts["chat-error"].waitForExistence(timeout: 10))
      XCTAssertFalse(app.staticTexts["Library volunteer plan"].exists)
      XCTAssertFalse(app.staticTexts["Document 1 ready."].exists)
      app.terminate()
    }
  }

  func testDebugSimulatorFixtureRejectsMalformedOversizeAndSymlinkFiles() {
    continueAfterFailure = false
    for name in ["native-malformed.json", "native-oversize.json", "native-symlink.json"] {
      let app = XCUIApplication()
      app.launchArguments = ["--chat-document-file", "Documents/\(name)", "--chat-fixture", "none"]
      app.launch()
      send("Reject invalid staged synthetic data", app: app)
      let error = app.staticTexts["chat-error"]
      XCTAssertTrue(error.waitForExistence(timeout: 10), name)
      if name == "native-oversize.json" { XCTAssertEqual(error.label, "Synthetic fixture exceeds 65536 bytes.") }
      if name == "native-symlink.json" { XCTAssertEqual(error.label, "Synthetic fixture path is invalid.") }
      if name == "native-malformed.json" { XCTAssertNotEqual(error.label, "Synthetic fixture could not be read.") }
      XCTAssertFalse(app.staticTexts["Document 1 ready."].exists)
      XCTAssertFalse(app.staticTexts["Library volunteer plan"].exists)
      app.terminate()
    }
  }

  func testDebugSimulatorFixtureAcceptsExactByteLimit() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["--chat-document-file", "Documents/native-limit.json", "--chat-fixture", "none"]
    app.launch()
    send("Render exact-limit synthetic data", app: app)
    XCTAssertTrue(app.staticTexts["Staged synthetic interaction fixture"].waitForExistence(timeout: 10))
    waitForRevision(1, app: app)
  }

  func testSelectedMealRejectsChangedSourceAndRetainsAcceptedDocument() {
    verifySelectedMealRejection(fixture: "meal-source")
  }

  func testSelectedMealRejectsMissingProjectionAndRetainsAcceptedDocument() {
    verifySelectedMealRejection(fixture: "meal-projection")
  }

  func testInteractiveMenuDoesNotRouteFreeformTextByKeywords() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["--interactive-examples", "--chat-fixture", "meal-source"]
    app.launch()
    // Given no explicit selection, even example keywords retain generic chat validation.
    send("meal plan split bill equipment comparison", app: app)
    XCTAssertTrue(app.staticTexts["Synthetic meal acceptance fixture"].waitForExistence(timeout: 10))
    send("meal plan", app: app)
    waitForRevision(2, app: app)
    XCTAssertFalse(app.staticTexts["chat-error"].exists)
    XCTAssertEqual(app.staticTexts["example-acceptance"].label,
      "Choose an example to apply its acceptance checks.")
  }

  func testSelectedMealRejectionInDarkAppearance() {
    verifySelectedMealRejection(fixture: "meal-source", dark: true)
  }

  private func verifySelectedMealRejection(fixture: String, dark: Bool = false) {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["--interactive-examples", "--chat-fixture", fixture]
    if dark { app.launchArguments += ["--appearance", "dark"] }
    app.launch()
    // Given an explicitly selected example, accept the first synthetic response.
    app.buttons["Meal plan"].tap()
    XCTAssertEqual(app.staticTexts["example-acceptance"].label, "Selected example acceptance: Meal plan")
    app.buttons["chat-send"].tap()
    XCTAssertTrue(app.staticTexts["Synthetic meal acceptance fixture"].waitForExistence(timeout: 10))
    let increment = app.buttons["fixture-people-Increment"]
    XCTAssertTrue(increment.waitForExistence(timeout: 5))
    increment.tap()
    XCTAssertTrue(app.staticTexts["People: 4"].waitForExistence(timeout: 5))
    // When a typed follow-up returns invalid source facts or a missing projection,
    // the explicit selection must still apply without keyword routing.
    send("Keep these edits", app: app)
    XCTAssertTrue(app.staticTexts["chat-error"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["The previous document is still available."].exists)
    XCTAssertTrue(app.staticTexts["People: 4"].exists)
    waitForRevision(1, app: app)
    app.buttons["original-source"].tap()
    XCTAssertTrue(app.staticTexts["source-text-1"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.staticTexts["source-text-1"].label, "Keep these edits")
    if app.buttons["Done"].exists {
      app.buttons["Done"].tap()
    } else {
      app.buttons["comparison-chat"].tap()
    }
    attach("synthetic-selected-\(fixture)-rejected\(dark ? "-dark" : "")", app: app)
    if fixture == "meal-source" {
      // Then choosing a different example keeps the previous accepted session intact.
      app.buttons["Split bill"].tap()
      XCTAssertEqual(app.staticTexts["example-acceptance"].label, "Selected example acceptance: Split bill")
      app.buttons["chat-send"].tap()
      XCTAssertTrue(app.staticTexts["chat-error"].waitForExistence(timeout: 10))
      XCTAssertTrue(app.staticTexts["People: 4"].exists)
      waitForRevision(1, app: app)
      app.buttons["chat-reset"].tap()
      XCTAssertEqual(app.staticTexts["example-acceptance"].label,
        "Choose an example to apply its acceptance checks.")
      XCTAssertFalse(app.buttons["original-source"].exists)
    }
  }

  func testChatShowsValidatedProgressiveComponentsBeforeFinalDocument() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["--chat-progressive-fixture"]
    app.launch()
    send("Show the synthetic preview", app: app)
    XCTAssertTrue(app.staticTexts["Chat provisional component"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["document-preview-status"].exists)
    XCTAssertTrue(app.buttons["original-source"].exists)
    attach("chat-progressive-component", app: app)
  }

  func testChatSelectionSurvivesProgressiveLayoutRetry() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["--chat-progressive-fixture"]
    app.launch()
    send("Keep my panel selection", app: app)
    XCTAssertTrue(app.staticTexts["Chat provisional component"].waitForExistence(timeout: 10))
    app.buttons["chat-panel"].tap()
    app.buttons["Advance synthetic preview"].tap()
    XCTAssertTrue(app.staticTexts["Synthetic preview attempt advanced"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.buttons["chat-panel"].value as? String, "Selected")
    app.buttons["document-panel"].tap()
    XCTAssertTrue(app.staticTexts["Retried provisional component"].waitForExistence(timeout: 5))
  }

  func testReadOnlyProgressivePreviewCannotMutateOrDispatch() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["--progressive-preview"]
    app.launch()

    // Given an accepted document and a host edit, its state must survive a preview.
    XCTAssertTrue(app.staticTexts["Prior accepted"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["Host state: 2"].exists)
    app.buttons["Edit accepted"].tap()
    XCTAssertTrue(app.staticTexts["Host state: 3"].waitForExistence(timeout: 5))

    // When a complete synthetic component arrives, it is visible but read-only.
    app.buttons["Begin preview"].tap()
    XCTAssertTrue(app.staticTexts["Preview visible"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["document-preview-status"].firstMatch.exists)
    XCTAssertTrue(app.staticTexts["Second complete component"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Prior accepted"].exists)
    let increment = app.buttons["preview-input-Increment"]
    let submit = app.buttons["Preview submit"]
    XCTAssertTrue(increment.exists)
    XCTAssertTrue(submit.exists)
    XCTAssertFalse(increment.isEnabled)
    XCTAssertFalse(submit.isEnabled)
    XCTAssertTrue(increment.isHittable)
    XCTAssertTrue(submit.isHittable)
    XCTAssertTrue(app.staticTexts["Preview input: 2"].exists)
    increment.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    submit.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    XCTAssertTrue(app.staticTexts["Host actions: 0"].exists)
    XCTAssertTrue(app.staticTexts["Host state: 3"].exists)
    XCTAssertTrue(app.staticTexts["Preview input: 2"].exists)
    let previews = app.scrollViews["generated-preview-components"]
    for _ in 0..<3 {
      if app.staticTexts["Second complete component"].isHittable { break }
      previews.swipeUp()
    }
    XCTAssertTrue(app.staticTexts["Second complete component"].isHittable)
    attach("synthetic-read-only-progressive-preview", app: app)

    // Then cancellation removes only the preview and retains accepted state.
    app.buttons["Cancel"].tap()
    let ready = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "enabled == true"), object: app.buttons["Begin preview"])
    XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
    XCTAssertFalse(app.staticTexts["Preview visible"].exists)
    XCTAssertFalse(app.staticTexts["Second complete component"].exists)
    XCTAssertFalse(app.staticTexts["document-preview-status"].exists)
    XCTAssertTrue(app.staticTexts["Prior accepted"].exists)
    XCTAssertTrue(app.staticTexts["Host state: 3"].exists)
    XCTAssertTrue(app.staticTexts["Host actions: 0"].exists)
    attach("synthetic-progressive-preview-cancelled", app: app)
  }

  func testFailedProgressivePreviewPreservesAcceptedDocument() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["--progressive-preview-failure"]
    app.launch()
    XCTAssertTrue(app.staticTexts["Prior accepted"].waitForExistence(timeout: 10))
    app.buttons["Edit accepted"].tap()
    XCTAssertTrue(app.staticTexts["Host state: 3"].waitForExistence(timeout: 5))
    app.buttons["Begin preview"].tap()
    XCTAssertTrue(app.staticTexts["Preview visible"].waitForExistence(timeout: 10))
    app.buttons["Complete generation"].tap()
    XCTAssertTrue(app.staticTexts["Synthetic generation failed."].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["Retry"].exists)
    XCTAssertFalse(app.staticTexts["Preview visible"].exists)
    XCTAssertFalse(app.staticTexts["Second complete component"].exists)
    XCTAssertTrue(app.staticTexts["Prior accepted"].exists)
    XCTAssertTrue(app.staticTexts["Host state: 3"].exists)
    XCTAssertTrue(app.staticTexts["Host actions: 0"].exists)
    attach("synthetic-progressive-preview-failed", app: app)
  }

  func testProgressivePreviewEnablesOnlyAcceptedFinalDocument() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["--progressive-preview-final"]
    app.launch()

    // Given an accepted document with a host edit, preview controls remain read-only.
    XCTAssertTrue(app.staticTexts["Prior accepted"].waitForExistence(timeout: 10))
    app.buttons["Edit accepted"].tap()
    XCTAssertTrue(app.staticTexts["Host state: 3"].waitForExistence(timeout: 5))
    app.buttons["Begin preview"].tap()
    XCTAssertTrue(app.staticTexts["Preview visible"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["Second complete component"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["preview-input-Increment"].isEnabled)
    XCTAssertFalse(app.buttons["Preview submit"].isEnabled)
    XCTAssertFalse(app.staticTexts["Final accepted"].exists)
    XCTAssertTrue(app.staticTexts["Host actions: 0"].exists)

    // When the provider completes, only the accepted final document becomes interactive.
    let complete = app.buttons["Complete generation"]
    XCTAssertTrue(complete.waitForExistence(timeout: 5))
    XCTAssertTrue(complete.isEnabled)
    complete.tap()
    XCTAssertTrue(app.staticTexts["Final accepted"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.staticTexts["Preview visible"].exists)
    XCTAssertFalse(app.staticTexts["Second complete component"].exists)
    XCTAssertFalse(app.staticTexts["document-preview-status"].exists)
    XCTAssertFalse(app.buttons["Preview submit"].exists)
    XCTAssertFalse(app.staticTexts["Prior accepted"].exists)
    XCTAssertTrue(app.staticTexts["Host state: 3"].exists)
    XCTAssertTrue(app.staticTexts["Final input: 3"].exists)
    XCTAssertTrue(app.staticTexts["Host actions: 0"].exists)

    // Then final controls retain the host edit and dispatch only a user action.
    let increment = app.buttons["final-input-Increment"]
    XCTAssertTrue(increment.isEnabled)
    increment.tap()
    XCTAssertTrue(app.staticTexts["Host state: 4"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Final input: 4"].exists)
    let submit = app.buttons["Submit final"]
    XCTAssertTrue(submit.isEnabled)
    submit.tap()
    XCTAssertTrue(app.staticTexts["Host actions: 1"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Host state: 4"].exists)
    attach("synthetic-progressive-preview-final-accepted", app: app)
  }

  func testCancelledCompletionGateCanImmediatelyRestartAndAcceptFinal() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["--progressive-preview-final"]
    app.launch()

    // Given a host edit and a preview waiting at the completion gate (not a sleep).
    XCTAssertTrue(app.staticTexts["Prior accepted"].waitForExistence(timeout: 10))
    app.buttons["Edit accepted"].tap()
    XCTAssertTrue(app.staticTexts["Host state: 3"].waitForExistence(timeout: 5))
    app.buttons["Begin preview"].tap()
    XCTAssertTrue(app.buttons["Complete generation"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Second complete component"].waitForExistence(timeout: 5))

    // When cancellation is followed immediately by another generation.
    app.buttons["Cancel"].tap()
    let ready = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "enabled == true"), object: app.buttons["Begin preview"])
    XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
    app.buttons["Begin preview"].tap()
    XCTAssertTrue(app.buttons["Complete generation"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Preview visible"].exists)
    XCTAssertFalse(app.buttons["Preview submit"].isEnabled)
    XCTAssertTrue(app.staticTexts["Host state: 3"].exists)
    app.buttons["Complete generation"].tap()

    // Then the new gate completes, clears previews, and preserves host-owned state.
    XCTAssertTrue(app.staticTexts["Final accepted"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.staticTexts["Preview visible"].exists)
    XCTAssertFalse(app.staticTexts["Second complete component"].exists)
    XCTAssertFalse(app.staticTexts["document-preview-status"].exists)
    XCTAssertTrue(app.staticTexts["Host state: 3"].exists)
    XCTAssertTrue(app.staticTexts["Final input: 3"].exists)
    XCTAssertTrue(app.buttons["final-input-Increment"].isEnabled)
    XCTAssertTrue(app.buttons["Submit final"].isEnabled)
    XCTAssertTrue(app.staticTexts["Host actions: 0"].exists)
    app.buttons["Submit final"].tap()
    XCTAssertTrue(app.staticTexts["Host actions: 1"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Host state: 3"].exists)
    attach("synthetic-progressive-preview-cancel-restart", app: app)
  }

  func testProgressivePreviewFinalAcceptanceInDarkAppearance() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["--progressive-preview-final", "--appearance", "dark"]
    app.launch()
    XCTAssertTrue(app.staticTexts["Prior accepted"].waitForExistence(timeout: 10))
    app.buttons["Begin preview"].tap()
    XCTAssertTrue(app.staticTexts["Preview visible"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.buttons["Preview submit"].isEnabled)
    XCTAssertTrue(app.staticTexts["Host actions: 0"].exists)
    attach("progressive-preview-dark", app: app)
    app.buttons["Complete generation"].tap()
    XCTAssertTrue(app.staticTexts["Final accepted"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.staticTexts["Preview visible"].exists)
    XCTAssertTrue(app.buttons["Submit final"].isEnabled)
    app.buttons["Submit final"].tap()
    XCTAssertTrue(app.staticTexts["Host actions: 1"].waitForExistence(timeout: 5))
    attach("progressive-final-dark", app: app)
  }

  func testPublicWrapperRetainsSessionRegistryAfterParentReplacement() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["--wrapper-registry"]
    app.launch()
    let prompt = app.textFields["generated-prompt"]
    prompt.tap()
    prompt.typeText("Synthetic calculation")
    app.buttons["generated-send"].tap()
    XCTAssertTrue(app.staticTexts["Session result: 4"].waitForExistence(timeout: 10))
    app.buttons["Replace parent registry"].tap()
    app.buttons["input-control-Increment"].tap()
    XCTAssertTrue(app.staticTexts["Session result: 6"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.staticTexts["Session result: 9"].exists)
    attach("public-wrapper-registry-identity", app: app)
  }

  func testRecordCellsRecalculateGenericDocument() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["--record-editing"]
    app.launch()
    XCTAssertTrue(app.staticTexts["Total: 125"].waitForExistence(timeout: 10))
    let included = app.switches["items-table:tea:included:2"]
    if included.switches.firstMatch.exists { included.switches.firstMatch.tap() } else { included.tap() }
    XCTAssertTrue(app.staticTexts["Total: 0"].waitForExistence(timeout: 5))
    if included.switches.firstMatch.exists { included.switches.firstMatch.tap() } else { included.tap() }
    XCTAssertTrue(app.staticTexts["Total: 125"].waitForExistence(timeout: 5))
    let amount = app.textFields["items-table:tea:amount:1"]
    amount.tap()
    amount.press(forDuration: 1.2)
    if app.menuItems["Select All"].waitForExistence(timeout: 2) { app.menuItems["Select All"].tap() }
    amount.typeText("150\n")
    XCTAssertTrue(app.staticTexts["Total: 150"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["150"].exists)
    XCTAssertTrue(app.staticTexts["Total minor units"].exists)
    attach("native-record-edits", app: app)
    amount.tap()
    amount.press(forDuration: 1.2)
    if app.menuItems["Select All"].waitForExistence(timeout: 2) { app.menuItems["Select All"].tap() }
    amount.typeText("-1\n")
    XCTAssertTrue(app.staticTexts["items-table-edit-error"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Total: 150"].exists)
    attach("native-record-invalid-edit", app: app)
  }

  func testCalculationRegistryAndStateReplacementReloadUnchangedDocument() {
    let app = XCUIApplication()
    app.launchArguments = ["--calculation-lifecycle"]
    app.launch()
    XCTAssertTrue(app.staticTexts["Derived value: 4"].waitForExistence(timeout: 10))
    app.buttons["Replace registry"].tap()
    XCTAssertTrue(app.staticTexts["Derived value: 6"].waitForExistence(timeout: 5))
    app.buttons["Replace state"].tap()
    XCTAssertTrue(app.staticTexts["Derived value: 6"].waitForExistence(timeout: 5))
    app.buttons["input-Increment"].tap()
    XCTAssertTrue(app.staticTexts["Derived value: 9"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["9"].exists)
    let scroll = app.scrollViews["generic-document-scroll"]
    for _ in 0..<3 {
      if app.staticTexts["Prepare portions"].isHittable { break }
      scroll.swipeUp()
    }
    XCTAssertTrue(app.staticTexts["Prepare portions"].exists)
    XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", "Derived value: 9")).count, 2)
    let itemLabels = app.staticTexts.matching(NSPredicate(format: "label == %@", "Synthetic item"))
    for _ in 0..<4 {
      let labels = itemLabels.allElementsBoundByIndex
      if labels.count == 2 && labels.allSatisfy(\.isHittable) { break }
      app.swipeUp()
    }
    XCTAssertEqual(itemLabels.count, 2)
    XCTAssertTrue(itemLabels.allElementsBoundByIndex.allSatisfy(\.isHittable))
    XCTAssertTrue(app.staticTexts["9"].exists)
    attach("reactive-text-chart-timeline-table-list", app: app)
    app.buttons["Empty chart"].tap()
    for _ in 0..<4 {
      if app.staticTexts["Filtered comparison"].isHittable { break }
      app.swipeUp()
    }
    XCTAssertTrue(app.staticTexts["Filtered comparison"].isHittable)
    app.buttons["Invalid replacement"].tap()
    XCTAssertTrue(app.staticTexts["calculation-error"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.staticTexts["Derived value: 180"].exists)
    XCTAssertFalse(app.staticTexts["Calculated amount"].exists)
  }

  func testReferenceNarrativeAndDatedCards() {
    prepareOrientation()
    continueAfterFailure = false
    let app = XCUIApplication()
    for appearance in ["light", "dark", "reduced"] {
      for scenario in ["narrative", "events"] {
        app.launchArguments = ["--chat-reference", scenario, "--appearance", appearance == "reduced" ? "light" : appearance]
        if appearance == "reduced" { app.launchArguments.append("--test-reduce-transparency") }
        app.launch()
        send("Reference source for \(scenario).", app: app)
        waitForRevision(1, app: app)
        if scenario == "narrative" {
          let answer = app.staticTexts["reference-answer"]
          XCTAssertTrue(answer.waitForExistence(timeout: 5))
          XCTAssertTrue(answer.isHittable)
          XCTAssertTrue(answer.label.contains("1842"))
          XCTAssertTrue(answer.label.contains("Sir John Herschel"))
          XCTAssertTrue(answer.label.contains("Prussian blue"))
        } else {
          XCTAssertTrue(app.staticTexts["reference-intro"].waitForExistence(timeout: 5))
          XCTAssertTrue(app.staticTexts["Maiko’s birthday"].exists)
          XCTAssertTrue(app.staticTexts["Wednesday, April 1"].exists)
          XCTAssertTrue(app.staticTexts["Apr 17, 3:00–4:00 PM"].exists)
          let scroll = app.scrollViews["chat-document-scroll"]
          for _ in 0..<4 {
            if app.staticTexts["Hunter’s birthday"].isHittable { break }
            scroll.swipeUp()
          }
          XCTAssertTrue(app.staticTexts["Hunter’s birthday"].isHittable)
        }
        attach("reference-\(scenario)-\(appearance)", app: app)
        app.buttons["original-source"].tap()
        XCTAssertEqual(app.staticTexts["source-text-0"].label, "Reference source for \(scenario).")
        app.terminate()
      }
    }
  }

  func testReadingHierarchyHasOneTitleAndSelectedPanel() {
    prepareOrientation()
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["--chat-rich-output"]
    app.launch()
    send("Show the workshop document.", app: app)
    waitForRevision(1, app: app)
    XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", "Workshop readiness")).count, 1)
    if UIDevice.current.userInterfaceIdiom != .pad {
      XCTAssertEqual(app.buttons["document-panel"].value as? String, "Selected")
    }
    attach("polished-reading-hierarchy", app: app)
  }

  func testWideLayoutRetainsConversationAfterSubmission() {
    guard UIDevice.current.userInterfaceIdiom == .pad else { return }
    prepareOrientation()
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["--chat-rich-output"]
    app.launch()
    send("Keep the conversation beside the document.", app: app)
    waitForRevision(1, app: app)
    XCTAssertTrue(app.scrollViews["chat-transcript"].exists)
    XCTAssertTrue(app.staticTexts["Document 1 ready."].isHittable)
    XCTAssertFalse(app.staticTexts["source-text-0"].exists)
    app.buttons["original-source"].tap()
    XCTAssertTrue(app.staticTexts["source-text-0"].exists)
    app.buttons["comparison-chat"].tap()
    XCTAssertTrue(app.staticTexts["Document 1 ready."].isHittable)
    attach("wide-conversation-and-document", app: app)
  }

  func testDetailsKeepsMetadataOutOfTheReadingPage() {
    let app = XCUIApplication()
    app.launchArguments = ["--chat-rich-output", "--appearance", "light"]
    app.launch()
    XCTAssertFalse(app.staticTexts["chat-provider-label"].exists)
    XCTAssertFalse(app.staticTexts["chat-revision"].exists)
    XCTAssertFalse(app.buttons["chat-show-json"].exists)
    let details = app.buttons["chat-details"]
    XCTAssertTrue(details.waitForExistence(timeout: 5))
    details.tap()
    XCTAssertTrue(app.staticTexts["chat-provider-label"].label.contains("generated on Mac"))
    app.buttons["Done"].tap()
    send("Display the recorded workshop document", app: app)
    waitForRevision(1, app: app)
    details.tap()
    XCTAssertEqual(app.staticTexts["chat-revision"].label, "DOCUMENT · 1")
    app.buttons["chat-show-json"].tap()
    XCTAssertTrue(app.staticTexts["chat-json-source"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["chat-json-source"].label.contains("chart"))
    attach("document-details", app: app)
    app.buttons["Done"].tap()
    attach("reading-page", app: app)
  }

  func testLongOriginalTextRemainsWithGeneratedCharts() {
    prepareOrientation()
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["--chat-rich-output", "--appearance", "light"]
    app.launch()
    let passage = String(repeating: "The workshop has 12 volunteers. Safety checks are 60 percent complete. Keep this original wording unchanged. ", count: 12) + "Original ending: preserve this sentence."
    send(passage, app: app)
    waitForRevision(1, app: app)
    XCTAssertFalse(app.staticTexts["source-text-0"].exists)
    XCTAssertTrue(app.staticTexts["Workshop readiness"].firstMatch.isHittable)
    attach("result-first-long-passage", app: app)
    app.buttons["original-source"].tap()
    XCTAssertEqual(app.staticTexts["source-text-0"].label, passage)
    attach("complete-original-source", app: app)
    if UIDevice.current.userInterfaceIdiom == .pad {
      app.buttons["comparison-chat"].tap()
    } else {
      app.buttons["Done"].tap()
    }
    send("Keep the same source and show its chart.", app: app)
    waitForRevision(2, app: app)
    app.buttons["original-source"].tap()
    XCTAssertEqual(app.staticTexts["source-text-0"].label, passage)
    XCTAssertEqual(app.staticTexts["source-text-1"].label, "Keep the same source and show its chart.")
    if UIDevice.current.userInterfaceIdiom == .pad {
      app.buttons["comparison-chat"].tap()
    } else {
      app.buttons["Done"].tap()
    }
    app.buttons["chat-reset"].tap()
    XCTAssertFalse(app.staticTexts["source-text-0"].exists)
    XCTAssertFalse(app.buttons["original-source"].exists)
  }

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
    app.buttons["chat-details"].tap()
    XCTAssertTrue(app.staticTexts["chat-provider-label"].label.contains("not AI generation"))
    app.buttons["Done"].tap()
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
    app.buttons["chat-details"].tap()
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
      app.buttons["chat-details"].tap()
      XCTAssertTrue(app.staticTexts["chat-provider-label"].waitForExistence(timeout: 10))
      XCTAssertTrue(app.staticTexts["chat-provider-label"].label.contains("generated on Mac"))
      app.buttons["Done"].tap()
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
        app.buttons["chat-details"].tap()
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
      app.buttons["chat-details"].tap()
      XCTAssertTrue(app.staticTexts["chat-provider-label"].waitForExistence(timeout: 10))
      XCTAssertTrue(app.staticTexts["chat-provider-label"].label.contains("generated on Mac"))
      app.buttons["Done"].tap()
      send("Display the synthetic workshop dashboard generated on Mac", app: app)
      waitForRevision(1, app: app)
      attach("rich-apple-\(appearance)-top", app: app)
      let scroll = app.scrollViews["chat-document-scroll"]
      for _ in 0..<2 { scroll.swipeUp() }
      attach("rich-apple-\(appearance)-details", app: app)
      app.buttons["chat-details"].tap()
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
    app.buttons["chat-details"].tap()
    let status = app.staticTexts["chat-revision"]
    let expected = NSPredicate(format: "label == %@", "DOCUMENT · \(revision)")
    expectation(for: expected, evaluatedWith: status)
    waitForExpectations(timeout: 15)
    app.buttons["Done"].tap()
  }

  private func attach(_ name: String, app: XCUIApplication) {
    // App-only captures crop incorrectly after rotation on this runtime.
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
