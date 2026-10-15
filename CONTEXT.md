# Current project state

## Scope

The SDK name is SwiftUIIntelligence. The user approves the complete local rename and requires successful compilation.
The rename covers package products, modules, branded public symbols, source paths, Xcode targets, the shared scheme, scripts, and documentation.
Historical evidence and reference artifacts remain unchanged. The workspace directory is `SwiftUIIntelligence`; no remote repository changes occur.

## Decisions

- Import the SDK with `import SwiftUIIntelligence`.
- Import the optional adapter with `import SwiftUIIntelligenceFoundationModels`.
- Open `Example/SwiftUIIntelligenceDemo.xcodeproj` and select `SwiftUIIntelligenceDemo`.
- The independent host declares an explicit package name and refers to the SDK by its parent path.
- Existing consumers must update their imports and renamed public symbols. No compatibility module is supplied.
- Document JSON fields and component kinds remain unchanged.
- One private remote repository holds the source. The evidence directory stays local and untracked.
- Remote generation uses `URLSession`. HTTPS is required, with one loopback HTTP exception for a local model server.
- `README.md` holds English prose. `README.zh-CN.md` mirrors it in Chinese.
- Both READMEs open with the `A FRAD PRODUCT` badge, the follower badge, and the Swift and platform badges.

## Verification

Verification uses Xcode 27.0 and its Swift toolchain on this Mac.

- The package test suite passes 39 tests through `./scripts/test-package.sh`: 35 from the rename round plus 4 for the OpenAI-compatible provider.
- The independent host builds with `swift build --package-path Example/MinimalHost --scratch-path /tmp/swiftuiintelligence-minimalhost --disable-sandbox`.
- All package products build in Release with `swift build -c release --scratch-path /tmp/swiftuiintelligence-release --disable-sandbox`.
- The iOS simulator app and UI test target compile with `build-for-testing` and signing disabled.
- The iOS simulator app also builds in Release with signing disabled.
- The Xcode project, shared scheme references, and README local links pass validation.
- Two iPhone simulator UI tests pass: generic SDK host callbacks and synthetic chat updates.
- All four shell scripts pass `zsh -n`.
- A case-insensitive search finds no old brand in active source, tests, examples, or scripts.
- README uses `../SwiftUIIntelligence` for the local checkout path; the sibling directory resolves to the SDK root.
- After the directory rename: a throwaway sibling host resolves `path: "../SwiftUIIntelligence"` through `swift package dump-package`, and `Example/MinimalHost` builds with a fresh scratch path.
- The initial commit `63a4c57` imports 86 files and about 16.5 MB. The private repository `FradSer/SwiftUIIntelligence` reports PRIVATE, and `origin/main` matches local `main`.
- Independent review finds one incorrect README package path. The path is corrected and its resolution is verified.
- Xcode reports only the App Intents metadata warning because these targets do not depend on AppIntents.
- Both READMEs pass a local-link check, a table-shape check, and a code-fence parity check.
- Every code snippet in both READMEs compiles in a scratch package that depends on the checkout by relative path.
- A live `--openai-compatible` acceptance run produced three structurally valid documents that also pass the authored semantic assertions, in 9.3 s, 8.7 s and 4.7 s.
- The live endpoint serves plain HTTP on the LAN, so the run used a loopback relay. TLS termination is delegated to URLSession and no live TLS handshake is verified.
- The legal claim in each README derives from the tracked project files and the earlier rename record.

Build logs are in `/tmp/swiftuiintelligence-*.log`.
The UI test result is under `/tmp/swiftuiintelligence-rename-ios/Logs/Test/`.

## Limits

No live HTTPS endpoint was available: the acceptance run verifies request building, transport, envelope decoding and strict validation, and only the URL policy test covers the TLS requirement.
No real-device signing or deployment is tested.
The full historical UI suite is not rerun; two relevant UI tests run after the rename.
All project files were untracked before this work. No reliable Git diff baseline exists.
The evidence directory is about 4 GB with 5022 files; four files exceed the 100 MB push limit. It is not tracked.

## Active work

The rename, the workspace directory rename to `SwiftUIIntelligence`, the independent review, and the private publication are complete.
`OpenAICompatibleDocumentProvider` is added and accepted against a live remote endpoint. The README restructure is complete: English `README.md`, Chinese `README.zh-CN.md`, and the badge block. No known
compilation failures or unresolved review findings remain.

## Demo original source cards

- The document page preserves exact submitted user text in a separate Liquid Glass card.
- Phones show generated results first and open complete original text in a sheet. Wide iPads switch the left column between Chat and Original text.
- Long text has no line limit or expansion control. Phones scroll the source and generated content together.
- Cards retain horizontal insets inside the scroll view. Follow-up messages remain in order. Reset clears the sources.
- The Details test fails before implementation because metadata remains on the reading page.
- After implementation, six UI tests pass on each device: 12 passes, zero failures. Two additional iPhone checks pass for recorded chat and the transparency test seam.
- All 39 package tests pass.
- Current screenshot attachments and logs are in `evidence/ui-polish/`.
- Details contains provenance, revision, and JSON. Reading cards use regular Liquid Glass with no custom shadows.
- Layout containers add no enclosing surface. Scroll wrappers add no duplicate clipping.
- Generation tests use recorded and synthetic providers. New live generation is not verified for this UI change.

## Independent UI review

- The review finds that the wide layout replaces the conversation with the source card.
- The regression test reproduces the missing transcript before the fix.
- The fix restores the left conversation column and places the source card above the document on the right.
- Three iPad regression checks pass: transcript retention, complete source, and synthetic chat.
- Current review-fix logs and screenshots are in `evidence/ui-polish/wide-*`.
- `git diff --check` passes. The reported whitespace is already corrected.

## Liquid Glass requirement

- The user requires Liquid Glass for every custom card. The opaque-card decision is superseded.
- The shared surface uses regular glass and retains the Reduce Transparency system-background fallback.
- Chat scroll content reserves 20 points horizontally and 24 points vertically for surface effects.
- Details and the restored wide conversation remain unchanged.
- Seven applicable UI checks pass across both devices; the phone-only wide-layout case returns without testing.
- Screenshots and logs are in `evidence/glass-restored/`.
- Scroll viewport edges still clip content at the composer boundary. This is not a claim of zero effect clipping.

## Reading hierarchy polish

- The compact header uses labelled Details and New chat icons with 44-point targets.
- The phone panel selector shows a persistent selected background and accessibility value.
- A section omits its heading only when a direct text child renders the exact same title.
- Card content remains unchanged. All custom cards retain regular Liquid Glass.
- Nine applicable UI checks pass across phone and iPad. All 39 package tests pass.
- Current screenshots and logs are in `evidence/design-polish/`.
- VoiceOver, RTL, and the full Dynamic Type range are not verified in this round.

## Result-first reading

- The user approves result-first reading. Original text no longer precedes generated results.
- Phones open Original text in a native sheet. iPads switch the left comparison column between Chat and Original text.
- Each semantic section shares one Liquid Glass card between related text and visual components.
- Exact source passages remain selectable and ordered. Reset clears them.
- Nine applicable UI checks pass across both devices. All 39 package tests pass.
- Current evidence is in `evidence/result-first/`.
- Recorded output tests presentation only. New long-text conversion quality remains unverified.
- Independent review finds nested layouts restore child surfaces. The surface policy fix propagates section suppression through vertical and horizontal layouts.
- The regression test fails before the fix. All 40 package tests and two phone UI suites pass after the fix.
- Logs are in `evidence/nested-surface/`. Scroll-edge effect clipping remains a visual limitation.

## Reference reading scenes

- The supplied reference images guide narrative density and dated-item hierarchy.
- Generation instructions prefer a complete answer paragraph. Dashboards require an explicit user request.
- Titles use the system title2 preset instead of largeTitle.
- Standalone timeline events use compact Liquid Glass rows below date labels. Nested sections retain a single surface.
- The synthetic `--chat-reference narrative|events` scenes use the existing provider/session path.
- The scenes have no model inference, image loading, calendar access, or citations.
- Both scenes pass on phone and iPad in light and dark appearances. All 41 package tests pass.
- Current screenshots and logs are in `evidence/reference-reading/`.
- Live model compliance, inline emphasis, and image support remain unverified or out of scope.
- Independent review finds ungrouped layouts can suppress every glass surface. The inheritance fix preserves the parent surface permission without content-type inference.
- Both suppression and ungrouped-surface regression tests pass; all 42 package tests pass.
- Reference reading and synthetic chat UI suites pass on iPhone after the fix. Logs are in `evidence/surface-inheritance/`.

## Liquid Glass card colors

Optional `cardColor` accepts `neutral`, `blue`, `orange`, `green`, or `purple`.
Nodes and timeline events use the same palette. Unknown values are rejected.
Omitted colors preserve the neutral appearance and are omitted from canonical JSON.
Standalone event colors override timeline colors. A containing section keeps one surface.
Colors are explicit presentation data, not categories inferred from titles.
The shared surface uses native glass tint. Reduce Transparency uses an opaque system background with a subdued category fill.
Primary text remains system-colored. Event icons use the supplied category color.

- All 44 package tests pass. Both reference scenes pass on phone and iPad in light, dark, and the transparency fallback seam.
- Screenshots are in `evidence/card-colors/`. Independent review finds explicit null bypasses the color schema.
- Node and event decoders now reject explicit null while preserving omitted color fields.
- Both regression cases fail before the fix and pass after it. All 45 package tests pass.
- Dark event-detail contrast is adjusted after screenshot inspection. Final phone UI confirmation passes in all three appearance modes.
