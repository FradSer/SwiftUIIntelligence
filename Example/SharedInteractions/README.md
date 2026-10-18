# Shared interactive examples

This example-only module supplies pure calculations. The core SDK contains no scenario-specific components.

## Current status

The module registers three capabilities through CalculationRegistry:

- compare-records filters caller-defined numeric measurements and retains valid selections.
- meal-plan scales source ingredients and schedules supplied sequential steps backward from a meal instant.
- split-bill allocates integer minor units with deterministic rounding and proportional service fees.

ExampleRequests contains synthetic natural-language source datasets. It contains no document JSON or fixed page layouts.
The common Demo ChatScreen registers all three capabilities when launched with --interactive-examples.
The explicit button selection identifies the example acceptance policy; composer edits do not infer or change that identity.
The per-send policy freezes requirements and source/declaration/final checks, and retries retain that policy.
New chat clears selection. Selection does not recreate the session or replace an accepted document.
The current Demo wiring is under native regression verification. A provider must author the document, bindings, and source records.

These are integration work in progress, not three accepted runnable examples.
The minimal live scalar request preserves input 2 and evaluates output 4.
One live meal document passes source and calculation checks but lacks required editors and complete derived views.
Later attempts fail strict plan or interaction acceptance. No complete interactive example is accepted yet.
The runtime does not insert missing state, repair binding values, or report synthetic success.

## Input and output contracts

| Capability | Scalar inputs | Source record parameters | Record outputs |
|---|---|---|---|
| compare-records | None | products, measurements, conditions | matches, measurements |
| meal-plan | basePeople, people, mealTime | ingredients, steps | shopping, schedule |
| split-bill | feeMinor | people, items, assignments | breakdown, shares |

Inspect ExampleCalculations.registry().signatures for exact primitive field names and types.
Bind scalar inputs to declared state fields. Bind record inputs to declared source collections with matching schemas.
`recordReferences` in a calculation signature declares a text field's target input parameter.
For example, comparison measurements reference product row IDs; bill assignments reference item and person row IDs.
Native generation authors target collections first, then guides reference fields with the exact authored IDs.
The registry rejects unresolved references before the callback. It never matches display names or repairs IDs.
Optional `recordInputDescriptions` explains each host parameter's meaning. The provider passes this text unchanged to its collection call.
The SDK does not interpret description keywords, choose a business page, or create rows from descriptions.
The probe supplies `sourceInputValidation` through `ExampleAcceptance.validateSourceInput`.
For bill inputs, it rejects incorrect items, people, or row counts before dependent generation.
This early check does not establish cross-input participation or fee correctness. Full-source and final validators remain required.
The SDK callback is pure, optional, and may run repeatedly. It never creates replacement records.
Bind outputs to unique state or collection IDs. Derived outputs are read-only.
Use table editableFields only for displayed source fields.
The state runtime validates all calculated and projected data before committing an edit.

Bill amounts use minor units, not formatted currency amounts. One bill uses one currency.
Each item divides equally between included participants. Service fees divide in proportion to allocated food amounts.
The largest-remainder method assigns residual units. Stable participant IDs break ties.
Nonzero unassigned items and zero-food bills with fees reject.
The adapter caps the final total at one billion minor units to match the generic numeric record bound.

Meal steps are sequential in supplied order. The module does not infer concurrent cooking or access a calendar.
Quantities always scale from source values, not the previous calculated result.
The meal acceptance validator requires bound people-count declarations to use integer endpoints within `1...MealPlanning.maximumPeople` and step `1`.
The host signature now declares the same limits through generic `inputNumberConstraints` for both count roles.
Native generation is guided by those constraints, and the registry rejects fractional or out-of-domain calculation inputs before the callback.
Rejected edits retain prior scalar and record state. Step remains control metadata, not a runtime value lattice.
The original base count remains an example source/interaction rule; the numeric domain does not make it globally immutable.

## Verification

Run ./scripts/test-package.sh from the repository root.
Tests import this module, so runtime hosts and regression tests share the same algorithms.
Native synthetic tests prove selected shared rendering and editing paths, not model generation or generalization.

The model probe supports:

    swift run --disable-sandbox SwiftUIIntelligenceModelProbe <evidence-folder> --interactive-example meal

Replace meal with equipment or bill for the other source datasets.
The probe now checks source facts and the selected complete interaction contract before it reports success.
Interaction validators inspect authored bindings and mutate isolated state. They do not operate a rendered interface.
Native interaction acceptance and runtime screenshots remain separate requirements.
Do not treat Schema construction, recorded rendering, or isolated state tests as live UI generation.
