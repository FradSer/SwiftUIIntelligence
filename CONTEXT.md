# Current project state
## Goal and boundaries
Deliver independently integrable SwiftUIIntelligence and three reactive AI-authored examples through one generic protocol.
Examples: equipment comparison, meal planning, exact shared-meal splitting. Preserve all durable goal acceptance conditions.
Prefer Apple Intelligence. No keyword-to-page routing, fixed JSON templates, OpenUI Lang, or generated code execution.
No production writes, cloud resources, permissions, private test data, system-setting changes, or new publication authorization.
Keep repository private. Evidence stays local/untracked. Preserve pre-existing untracked .pi directory.
Read @PRODUCT.md for scope and @DESIGN.md for UI requirements.
## Confirmed design
Host registers pure calculations with typed scalar and flat-record signatures; AI authors IDs, data, bindings and layout.
Registration grants no side effects. Existing buttons retain explicit user-action boundaries.
User approves data -> AI explicit ID-bound calculation maps -> layout. No generated IDs, defaults, automatic maps or repairs.
Registered signatures define required source record slots. Accepted source and bindings remain fixed across later retries.
Flat records use stable IDs, exact declared primitive fields, no arbitrary nested paths.
Bills use integer minor units, equal item shares, proportional fees, largest remainders with stable ID ties.
Generic instant signature type uses ISO8601 text values and binds only to native date state. No calendar access.
## Core implementation
Feature work is uncommitted; resumed baseline HEAD was961ac20.
CalculationRegistry validates exact scalar/record signatures and returns all validated results or throws.
Plans check compatible types, references, cycles, unique output owners, source/output collisions before callbacks.
Record numbers are finite and bounded1e9. Core record kinds remain text/number/boolean; instant record schemas reject.
DocumentState atomically commits scalar/record candidates after calculations and presentation checks.
Failures preserve prior values and plans. Stable source edits survive compatible reloads; resets restore defaults.
Derived outputs are read-only. Unchanged cell writes preserve validation errors during native rollback.
Generic rendering supports bound text, numeric chart points, timeline text, and record-driven list/table/chart/timeline.
Editable table fields use native text, numeric controls and toggles on source collections only.
Chart invariants validate before commits/drawing; empty charts keep titles and removed selection labels do not render.
Table values use round-trip Double strings. Cell IDs use node:row:field:column and accessibility containment.
Renderer gates incoming content until canonical JSON/registry revision/state identity loads successfully.
Public GeneratedDocumentView renders with session.calculationRegistry; parent registry replacement cannot create drift.
Legacy session-initializer calculations argument is documented as compatibility-only. Configure registry on the session.
## Provider and validation
DocumentChatSession advertises signatures, validates calculated defaults and commits only complete validated documents.
Request/session sourceValidation and declarationValidation are pure, rerunnable callbacks, separate from final component requirements.
Native data stage validates source before bindings; bindings validate declarations before layout; final acceptance repeats all checks.
Apple planner selects capabilities/components/state kinds from allowlists, not topic keywords.
Empty selection routes ordinary generation. Host components and exact control types remain authoritative.
Native source schemas use closed signature fields, required record slots, model-authored IDs and values.
StateCount/stateKinds are explicit host constraints; empty stateKinds means unrestricted, positive count requires state.
Compact stage-specific prompts preserve safety and facts. Layout retains explicit-category colors and narrative grouping.
NativeCalculationData preserves source values/row order and reserves authored output IDs without creating maps.
Numeric declarations require authored bounds/step; kind-inapplicable keys/null reject rather than use core defaults.
Bindings use compatible authored ID enums. One native invocation slot per selected capability matches reserved outputs.
This restriction does not change core public calculation graphs.
NativeStagedSchema preserves full declarations for assembly within64KiB.
Layout receives original conversation and reference catalog; source rows are not duplicated but remain in final data.
Catalog includes each derived collection ID, registered fields and editable:false, never computed rows.
Single optional projection properties keep grammar small; final runtime requires source/fields paired and compatible.
Cumulative snapshots never render; separate validated inert preview components render progressively. Only final validated documents commit.
NativeStageRunner allows3attempts per stage, at most9generation calls plus planner. Accepted earlier stages do not rerun.
Cancellation checks surround awaits/stream completion/publication. Feedback remains stage-specific.
## Examples and fact acceptance
Example/SharedInteractions is SwiftUIIntelligenceExamples, separate from core SDK. Tests and hosts share algorithms.
Comparison uses caller-defined measurements/conditions and retains productID plus display name.
Meal scales original quantities and explicit sequential durations backward from supplied instant; no inferred concurrency.
Bill returns exact summaries and per-item shares using original assignment IDs.
All algorithms, adapters, relocation and identity corrections have final reviews with no remaining findings.
ExampleAcceptance checks only synthetic source facts, not generation: one calculation, disjoint source/output scalars, remapped IDs and complete records.
Equipment facts/limits, six bill assignments/fee, meal quantities/roles/ordered durations all checked.
Meal instants compare parsed dates, not exact spelling. Source-only early meal check requires base2/current3/instant.
Acceptance review corrections are closed; no validator inserts or repairs data.
ExampleRequests contains natural-language synthetic sources only. --interactive-examples populates existing ChatScreen composer.
ModelProbe --interactive-example equipment|meal|bill saves actual requests/stages. No accepted complete live example yet.
Read @Example/SharedInteractions/README.md for signatures and limits.
## Live results
Reference URL direct fetch returns403; search summaries are not verified source passages.
Available Apple model passes plain controls, simple empty objects and simple record arrays.
Full complete-document request measures12781tokens vs4096limit; scoped meal still5401tokens.
Data/binding/layout staging improves fit but does not establish correctness.
Latest minimal scalar role-data control preserves input2 and evaluates4: evidence/live-calculated-control-role-data/.
Latest meal progression:
- Missing base2 rejected early; role wording and precise missing-instant feedback improve data, without changed facts.
- instant planner initially omitteddate and rejected; generic instruction now selectsdate.
- Timestamp-containing IDs reject; generic ID syntax instruction produces valid IDs.
- Data and bindings now preserve base2/current3/date, ingredients and steps.
- Layout still mixes source and derived fields. Metadata-only projection check rejects within layout retries.
Latest bill reaches full JSON but registry rejects item/person references differing from assignment references.
Bill targetfirst IDsresolve but peoplecopieditems/feeaddedasitem, sourcefactsreject.
Targetcatalog onlydeclareddependencies. Next scoped-targets stillcounts/duplicateIDs/contextfails.
Live single-schema no contexterror but incomplete billfacts reject3attempts; evidence/live-calculated-bill-single-schema/.
Early bill source check now rejects missingpeople/items/matrix/fee and wrongactualrowrefs beforebindings, no datarepair.
Latest equipment current-contract has correct measurements but productID values pack-cedar/pack-moss do not match authored product row IDs.
Bindings reject3attempts; data retained unchanged. Evidence/live-calculated-equipment-current-contract/.
Live equipment-early-source rejects3data attempts before bindings.
Live reference-feedback stillwrong after3attempts; evidence/live-calculated-equipment-reference-feedback/. No names->IDs repair.
User approves hostdeclared input-field->targetinput rowreferences; native authors targetsfirst, enumrefs actualIDs, no namelinking/repair.
Provider now generates scalarroles/outputIDs then target-first inputcollections with actualrowIDenumrefs; no automaticmaps/repair.
Live typed-references failsduplicate conditionrowIDs and source/outputIDcollision;3dataattempts rejected. Evidence/live-calculated-equipment-typed-references/.
Duplicate rowID diagnostic now names input/actualID; RED/GREEN284tests, no dedup or repair.
Provider review finds equal-schema inputroles lost onflattening. Data nowretains cap/paramrecordIDs; AIbinding enum/runtime checks exactrole.
All3have actual live attempts; none passes full factual/interactivity acceptance or unseen-input generalization.
Do not repeat identical live calls. Next needs smaller strongly correlated layout generation and generic source-role/reference support.
## Latest verification
Evidence/native-equipment-bill/RESULTS.md logs/images; inspectedphonebilldark1658+iPadequipmentlight. Extra65536accept65537reject malformed/symlink verifiedstaged+exacterrorsGREEN.
ProjectdupA049 fixedA04B;79PBXobjects unique (old81includedclasses/objects dictionaries),2reviewsPASS. Plist/nativeboundary/iOSReleasepass resourcepresent loaderexcluded; nativetaskdone.
Current389tests+host/ReleaseGREEN. WideLEFT Chat/Original RIGHTresults nativeiPadPASS aftermove; oldmissingselectorreview supersededpending.
390tests+host/ReleaseGREEN. Equipmenthosttasklive counts2products2conditions4measurements but2duplicateRowIDs/1collectionreuse rejects source; evidence/live-calculated-equipment-host-task/.
Relationguide32IDs6pairswrongflags; exactcount6rows5IDs4pairsalltrue rejects no promotion.
SessionSHAbebb523ba0b8e77256b5f8a827849d676f934462457dcd7eb4700d5c5dea847a; actualcandidate reviewe449/d617pending.
NativeiPad scopedOriginalsheetGREEN nofirstMatch; phoneCopyPaste exactcompleteDetailsJSON equalityGREEN. Current389tests+host/ReleaseGREEN; reviewe449pending.
Live minimal progressivecontrol receives5component events and finalinput2/output4 passes. Evidence/live-progressive-control/.
This verifies minimal rawproviderchannel, not live UI completeexamples.
Component/slot helpers, meal interaction acceptance, and production wiring; component path live generates source-correct meal but lacks required editors/derived shopping and misorders timelinefields.
Independent host builds in /tmp/swiftuiintelligence-reactive-minimalhost; latest Release build passed before recent instant/catalog edits.
Latest native wrapper lifecycle and record-edit regressions pass on iPhone; earlier record edits also pass on iPad.
git diff --check passes.
Native evidence under evidence/calculation-lifecycle:
- wrapper-registry: parent registry replacement retains original session result6, not replacement9.
- latest-wrapper-and-metric: latest phone registry lifecycle, record/metric edits and negative rollback tests pass.
- latest-contracts-metric: latest phone edits/metric/invalidrollback rerun passes after acceptance corrections.
- public-registry-final: successful edits and negative amount rollback/error.
- phone-cells-final/ipad-cells-retry: toggle/amount125->0->125->150.
- record-timeline-green: calculated record event updates with text.
- empty-chart-red/green: empty title reproduced/fixed.
- chart-failure-green: invalid radar replacement suppressed.
- list-query-fix: table/list both visible; screenshots in list-attachments.
- shared-host-regression/ipad-reading-regression/reset-regression: existing reading, Details, transcript/source retained.
- reading-after-components: latest phone hierarchy/Details regressions pass despite ongoing purpose test RED.
These are synthetic provider UI checks, not live three-example rendering.
Phone7E4437E7-369A-466E-9C89-75FC93643440; iPad AA1CD39D-8DB8-4E45-88B7-986F29B3B19F.
Use /tmp/swiftuiintelligence-record-list-ios or -ipad for native builds.
## Preserved UI and known limits
Every custom card uses regular Liquid Glass, system Reduce Transparency fallback, no decorative shadows.
Optional neutral/blue/orange/green/purple cardColor; unknown/null reject; categories never inferred from titles.
Results first. Complete exact original passages remain selectable and ordered independently of model reconstruction.
Phones use Original text sheet; wide iPads retain Chat/Original text beside results.
Details holds provenance, revision and selectable/copyable JSON. Related content shares one card.
Keep system typography, native controls, semantic symbols and horizontal insets.
Scroll viewport can clip glass near composer. Full VoiceOver/RTL/contrast measurements/OS26runtime/physical devices unverified.
## Active work
Workflow idea-to-ship implementation. Durable goal remains unmet.
Metadata-only projection and text-candidate scope reviews find no concrete regression or safety issue.
User approves AI-authored container tree/slots plus individually generated leaf components; exact slot substitution/order, no titles/defaults/templates added.
User also approves native-only mode enum static/records, mapped shape-only to internal projected bool; no invalid choice repair or public JSON change.
User approves per-slot modelauthored purpose string, passed unchanged without keywordinterpretation/binding inference.
Interaction remains disabled until final acceptance. A child owns per-component schema helper/tests, another owns slot-plan schema/strict assembly tests.
Slot review finds projection mode not enforced during assembly (P1).
Both mismatch directions reproduce before fix; assembly enforces projected/static fields. Final P1 correction review passes.
Initial12level/not schema replaced by compact recursive Node refs and native-compatible empty floating array; runtime depth12/node/slot bounds remain.
Provider wiring now generates model slot tree then individual components; each and final document validate with no partial UI.
Live source-correct meal lacks editors/quantity display and misorders timeline roles; not interactive acceptance.
Component runtime review finds no concrete bugs. Meal acceptance review finds step2 control could pass3->4stateprobe.
Acceptance requires step1 for boundpeoplefield; correction review closesP2.
Live interaction-contract times out180s after missingcontrols then invalidslot rejection; no process remains or accepted doc.
Specific missing-interaction feedback retry completes within300s but again marks textslots projected=true; rejected3plans.
Meal probe explicitly requires table/timeline and stepper/datePicker; live required-plan still marks textslots projected and rejects3plans.
Live slot-modes produces valid text/control modes and actualeditors but chooses static table/timeline; finalinteractive rejects.
Generic DocumentRequirements.projectedComponents checks record-backed kinds in plan/final doc; mealprobe requires table/timeline projections.
Final static-substitute rejection, projected-only planner scope, unsupported-kind regression coverage passes.
Data-stage prompt now includes only host state requirements, not layout/control/projection requirements; final acceptance unchanged.
Regression ensures stage separation. Latest prompt narrowing needs liveverification; mode/requirements review pending.
Timeline/list native candidates now exclude numeric-only collections and nontext fields; RED/GREEN regression passes.
Generic optional metric valueBinding now resolves declared numeric state with roundtrip display and candidate validation; staticvalue remainsrequired/oldJSONcompatible.
Old tests explicitly marking metric unsupported updated to navigationLink per expanded supported contract.
Bill interaction review finds conserving wrongpersonalfees, ambiguousminorunit/staleamount labels and fractional slidergrid can pass.
Bill fee/grid/label corrections independently reviewedclosed.
Do not count existing fullbillacceptance as closed until corrections.
Equipment review finds globalunitlabelswap, untestedminbounds and deselectionlatch falsepositives.
Retained fixes reviewed: minbounds/deselection closed; unit headings/prefix labels overreject found.
Valid condition column heading and USDprice/gramsweight regression reproduces; unitfree headings now ignored, explicit clauses validate units.
User approves native scalarrole slots fullauthoreddeclarations or explicitIDrefs, no valuededup/publicmapinference. Later AIbinding call remains explicit.
NativeScalarRoles helper now schema-guides full perparameter declarations or explicitsharedIDrefs, preserves authoredobjects and no publicmapinference.
Live scalar-roles emitsdistinct2/3but illegal timestampIDs and prescaledsourceingredients; rejected. Evidence/live-calculated-meal-scalar-roles/.
Helper review finds Unicode code-point mismatch; normalizeRoles now rejects >4000scalars text and >80scalars options; boundary RED/GREEN passes.
Bridge review finds late source constraints; validateSourceState checks count/kinds before source acceptance without layout requirements.
Focused independent review returns no findings for all3fixes; prior fulltests, host and Release pass.
Progressive core boundary child owns new protocol/session/tests only. Separate complete preview frames validated independently; old cumulative snapshots remain nonrenderable.
Previewrenderer uses isolatedstate, inertactionregistry and disabledcontrols/navigation. Public GeneratedDocumentView shows provisionalcomponentlist beside unchanged acceptedview.
Two-component RED exposes percardscroll compression. DocumentPreviewView embedded option+single outerScrollView fixes it.
Phone progressive-two-components-green.xcresult and iPad progressive-two-components-ipad.xcresult verify firstinert, secondreachable, cancelboth/retainold.
Final previewUIreview finds no materialissues; current269tests/Releasepass. Phone swipe/iPad visiblehittability establish2componentreachability, not iPadswipe.
Concurrency correction reviewedclosed onexacthash. ParentAXid override reproducedRED; containment fixesGREEN.
Evidence/calculation-lifecycle/progressive-preview-contained.xcresult and progressive-preview-ipad.xcresult pass onphone/iPad; inertcontrols do not mutate oldstate or callhost.
Malformedframes consume validationbudget;32badframes prevent furtherpreviewdecodes; finalvaliddoc unaffected.
Duplicate rootID withinattempt rejects withoutappend; RED/GREEN268tests+hostbuildpass. Native slotIDs alreadyunique.
Review finds callerTaskcancel leaveslatepreview active. Perrequest Mutexcancel flag set synchronously, guardedMainActor cleanup and previewgate rejectlateframes.
Deterministic ignoringprovider caller-cancel test RED2issues thenGREEN. Added oldcancel/newrequest latecallback isolation regression.
Duringvalidation review finds cancel flag onlyentrychecked; publication now rechecks request/phase/cancel.
Observer regression gates syncvalidator/cancelsdetached: RED transientpreview setter ->GREEN269tests/hostbuild.
Empty cleanup guards avoid nil-to-nil events. During-validation P2 correction review closes with no further findings.
Verified sessionSHA2569f5a56482dbbf875b87c51be28e5c4553bdfe8e524ba1dba6a49eaf8dd4fb2fe;269tests/latestReleasepass.
Attemptidentity/reset/list/cumulativebudgets implemented. Matrix documented in evidence/shared-interactions/PROGRESSIVE-RESULTS.md.
MainChatScreen displays validatedpreviews in document scroll. Perrequest firstarrival auto-selectsresults once; laterframes/retries respect userChatselection.
Retry-selection correction reviewedclosed. Chatfixture cancellationcleanup now attemptIDguarded, resetadvance perrequest.
Latest native chat-selection-cancel-current.xcresult passes selection+cancel;284tests pass. No modelcalls.
Native finalsuccess preview->acceptedinteractive tests pass bothdevices: progressive-final-current.xcresult/progressive-final-ipad.xcresult plusattachments.
Preview disappears; only final controls/hostactions enabled. Syntheticprovider, not3liveexampleacceptance.
Progressive machinery task complete: all blocking reviewsclosed, native phone/iPad matrices and minimal liveemission verified,291tests/Releasepass.
recordInputDescriptions implemented/reviewclosed;304tests/host/Releasepass. No keywordrouting/templates; duplicateJSONmember rejection not claimed, multi-cap promptlookup source-reviewed only.
Layout P2 correctionreviewclosed: static/records mixedallowed coveragechecks unchanged; containerinstructions reviewclosed.
Componentprompt reduction reviewed no findings; exactslot/fullsource/catalog/feedback retained, finalassemblyunchanged. Qualitynotproved.
Slot-context allbeforecomponents. NativeAPI schema1695tokens/context4096. Scratch includeSchemafalse no contexterror but repeatedgrids/noslots invalid; NOTpromoted.
Evidence/planner-token-measurement/RESULTS.md counts separate nottotal. Flat topology+perkindpayload design accepted asinternalexperiment only.
Topologyacceptor handedoff9testsRED/GREEN; integrated. TopologySchema batch/payload nativeconvert2GREEN; assembly preservesproperties/order/mixedmodes APIRED->GREEN.
Scratch flatlive run rejectsbatch1: no root(parentdata), controlsasparents; 0payloadcalls, norepair. Evidence/live-equipment-flat-topology/RESULTS.md.
Billdiagnosis: invaliditem entersdependencycatalog thenassignmentduplicates maskfacts. Optionalperinput purehostcallback beforetargetinsertion selected; no modelrepair.
API/session+example integrated, native admission/scopedcopies/probe wired. Liveearlyinput bill3wrongitemrejects,0assignmentcalls, accurateitemfeedback but factsnotcorrected.
Systemicreview no converterdefect causesfee; minimalenvelope scratchalsofails10.21s evidence/live-bill-envelope-experiment/. No prodchanges.
Live correlated equipment:2contextfail(4099/4097),1invalidchartroles text/number/text reject. No positionalrepair/nativeprefixItems support; LIVE-STATUS updated.
Live 3 examples pass: equipment, meal, bill. Unseen generalization verified. OpenUI Paris hotel & gallery cases supported: UINode image component, capsule badges, pill/circle buttons, multi-column cards, single-line table rows. 399 tests, MinimalHost, Release build pass. Independent review passed.
