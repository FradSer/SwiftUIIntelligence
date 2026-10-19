# SPEC: Product Polish, Layout Deduplication, and Prompt Aesthetic Refinement

## Problem Statement
While SwiftUIIntelligence has successfully verified on-device Apple generation, pure calculations, and state consistency, the rendered interfaces currently suffer from:
1. **Layout Redundancy & Duplication**: The model plans redundant duplicate views for the same collection (e.g. up to 8 table slots where matching results or breakdown tables repeat 2-3 times).
2. **Mobile Horizontal Squeezing**: Narrow screens (iPhone) experience horizontal compression when tables are placed side-by-side in `hstack` instead of stacking vertically.
3. **Technical Leakage in Presentations**: Rendered tables and metrics expose internal technical keys (`items_1`, `people_1`) and raw schema field names (`amountMinor`, `foodMinor`) instead of human-friendly names and titles.
4. **Missing Semantic Context & Titles**: Tables and charts often render without titles or semantic SF Symbol icons, giving users raw data cards without context.

## Solution
Refine the planner guidance, component schemas, and presentation layer so that:
1. **Single-View-per-Collection Convergence**: The planner enforces a single primary card per collection; total planned slots converge cleanly to 2–6 concise components.
2. **Vertical-First Mobile Flow**: Narrow layouts default to vertical flow (`vstack`) for table cards, preserving horizontal space and legibility.
3. **Human-Readable Presentation & Dereferencing**: The presentation layer and schemas translate internal foreign keys (`itemID`, `personID`) into display names (`name`, `item`) and format technical minor-unit fields into clean localized headers.
4. **Mandatory Card Titles & Icons**: Every content card and table receives an explicit, descriptive title and appropriate SF Symbol icon.

## User Stories
1. As an iPhone user, I want tables to stack vertically so that columns are not cramped horizontally.
2. As a user reviewing an equipment comparison, I want to see a single clear table per dataset (one for selection, one for conditions, one for matches, one for measurements) rather than duplicated tables.
3. As a dining participant splitting a bill, I want to see actual dish names ("Soup", "Tea") and person names ("Ada", "Bo") rather than technical foreign keys ("items_1", "people_1").
4. As a user reviewing a meal plan, I want every card to have a clear human title (e.g., "Shopping List", "Cooking Timeline") and matching SF Symbol icon so I instantly understand what the card represents.
5. As an iPad user, I want wide layouts to retain the side-by-side Chat/Original pane on the left with prominent results on the right.

## Scenarios (BDD Gherkin)

### Scenario 1: Slot deduplication and convergence
Given a conversation requesting an equipment comparison
When the layout plan is generated
Then each data collection is projected to at most one table component
And the total number of planned slots is between 2 and 6 inclusive

### Scenario 2: Mobile vertical reading flow
Given a generated document rendered on a narrow screen
When multiple table cards are rendered
Then the tables are arranged in a vertical reading hierarchy (vstack) without side-by-side horizontal squeezing

### Scenario 3: Human-readable presentation and foreign key dereferencing
Given an accepted bill split document with item and participant assignments
When the assignment matrix or breakdown table is rendered
Then the visible columns display human-friendly names and titles rather than technical IDs or raw schema suffixes

### Scenario 4: Card titles and semantic icons
Given any generated table or chart component
When rendered as a Liquid Glass content card
Then the card displays an explicit non-empty title and a matching SF Symbol icon

## Implementation Decisions
- **Planner Constraint Refinement**: Update `calculationContainerInstructions` and `FoundationModelsProvider` planner instructions to mandate single-card-per-collection and 2–6 total slots.
- **Table Schema & Presentation Mapping**: Enhance `NativeCorrelatedComponentSchema` and `PresentationViews` to map relational foreign keys to display names and ensure column titles use natural language.
- **Liquid Glass & SF Symbols**: Ensure cards retain regular native Liquid Glass with Reduce Transparency fallback and semantic SF Symbol icons.
- **Seam**: Public `DocumentGenerationRequest` and `FoundationModelsDocumentProvider` generation pipeline, verified through unit tests and `SwiftUIIntelligenceModelProbe`.

## Testing Decisions
- Behavioral unit tests in `SwiftUIIntelligenceTests` verifying:
  - Deduplication of slots per collection.
  - Presence of human titles on generated tables and charts.
  - Column name formatting and key dereferencing.
- Native UI tests on iPhone and iPad simulators verifying vertical mobile layout and visual readability.

## Out of Scope
- Introducing external model providers, network calls, or cloud dependencies.
- Modifying underlying deterministic calculation logic or state math.
- Disabling Liquid Glass or system Reduce Transparency fallback.
