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
- `README.md` holds English prose. `README.zh-CN.md` mirrors it in Chinese.
- Both READMEs open with the `A FRAD PRODUCT` badge, the follower badge, and the Swift and platform badges.

## Verification

Verification uses Xcode 27.0 and its Swift toolchain on this Mac.

- Before the rename: all 35 package tests pass.
- After the final code changes: all 35 package tests pass through `./scripts/test-package.sh`.
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
- The legal claim in each README derives from the tracked project files and the earlier rename record.

Build logs are in `/tmp/swiftuiintelligence-*.log`.
The UI test result is under `/tmp/swiftuiintelligence-rename-ios/Logs/Test/`.

## Limits

No real-device signing, deployment, or new live model generation is tested.
The full historical UI suite is not rerun; two relevant UI tests run after the rename.
All project files were untracked before this work. No reliable Git diff baseline exists.
The evidence directory is about 4 GB with 5022 files; four files exceed the 100 MB push limit. It is not tracked.

## Active work

The rename, the workspace directory rename to `SwiftUIIntelligence`, the independent review, and the private publication are complete.
The README restructure is complete: English `README.md`, Chinese `README.zh-CN.md`, and the badge block. No known
compilation failures or unresolved review findings remain.
