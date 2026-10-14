# Chatbot-generated native documents

The primary experience is a conversation and its current document. iPhone uses native Chat/Document controls with a shared composer; wide iPad shows transcript and document side by side. Loading and errors remain visible above the content, and the last valid document survives failures. Provider labels distinguish live Apple generation, synthetic tests and recorded Mac output.

All surfaces and controls use SwiftUI system-default presentation. Native controls are not restyled. Content cards use regular Liquid Glass with concentric corners and a 20pt minimum fallback. They add no custom shadows or decoration. Standalone interactive documents use Form/Section; other layouts retain semantic content grouping. System navigation, backgrounds and controls own their appearance. System text styles, meaningful data/status colors and adaptive layout remain.

The schema owns content/layout choice, while the precompiled renderer owns readable native component implementation. Document horizontal layouts adapt on narrow screens; metric grids adapt their columns; chart labels/legends and numeric values remain readable; tables scroll horizontally. Containers use explicit accessibility containment so their IDs do not overwrite leaf button IDs. No changes to system accessibility settings.

All examples inherit system/host backgrounds; the earlier blue backdrop and custom decorative theme have been removed. We deliberately do not add generated wallpaper, images, arbitrary chart expressions or new business workflows. Default provider uses the available on-device API; simulator recorded-output mode makes its origin explicit.

Previous weather visual design and all source were preserved in `evidence/chat-before`. The complete OpenUI GIF module and interaction list is the weather acceptance baseline. The weather-specific reference view is preserved, and a typed adapter covers the same data with generic SDK components. Native Liquid Glass, platform type, screen adaptation and native chart defaults intentionally differ from the web GIF. New results and explicit differences are in `evidence/rich-final`; previous chat results are retained in `evidence/chat-final`.

## Original source cards

The demo document page preserves submitted user text independently of model output.
An original source card retains exact characters and supports text selection.
The original text renders in full without a preview line limit or an expansion control.
Phones scroll the original source and generated content together.
Content has horizontal insets inside the scroll view, in addition to the page insets.
The document column shows generated results first. Phones open complete original text in a sheet. Wide iPads select Chat or Original text in the left column.
Follow-up messages remain in source order. New chat clears the source cards.

## Reading hierarchy

Layout containers do not add an enclosing surface. Content groups and leaf content retain reading cards.
Scroll views own their viewport boundary; preview wrappers do not add a second clip.
The chat header shows the app name, Details, and New chat.
Details holds model provenance, document revision, JSON inspection, and JSON copying.

## Card material requirement

All custom cards use the shared regular Liquid Glass surface.
Reduce Transparency uses the system-background fallback in the same shape.
The document scroll content reserves 20 points horizontally and 24 points vertically for glass effects.
No custom shadows or duplicate clipping wrappers are added.

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
- Independent review is pending. Scroll-edge effect clipping remains a visual limitation.

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
- Independent review is pending.

## Liquid Glass card colors

Optional `cardColor` accepts `neutral`, `blue`, `orange`, `green`, or `purple`.
Nodes and timeline events use the same palette. Unknown values are rejected.
Omitted colors preserve the neutral appearance and are omitted from canonical JSON.
Standalone event colors override timeline colors. A containing section keeps one surface.
Colors are explicit presentation data, not categories inferred from titles.
The shared surface uses native glass tint. Reduce Transparency uses an opaque system background with a subdued category fill.
Primary text remains system-colored. Event icons use the supplied category color.
