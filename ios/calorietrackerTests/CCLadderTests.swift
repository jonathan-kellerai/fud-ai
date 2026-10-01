import Foundation
import Testing
@testable import calorietracker

/// Convict Conditioning ladders. The fixture is a trimmed copy of a live
/// GET /api/cc/ladders response. Step standards are validated against the
/// bridge's own rule table, never against a table written here.
@MainActor
struct CCLadderTests {
    private func decodeLive() throws -> CCLaddersResponse {
        try JSONDecoder().decode(CCLaddersResponse.self, from: Data(Self.liveJSON.utf8))
    }

    private func series(_ code: String, in response: CCLaddersResponse) throws -> CCSeriesState {
        try #require(response.series.first(where: { $0.series == code }))
    }

    @Test func decodesAllSixSeries() throws {
        let response = try decodeLive()
        #expect(response.series.map(\.series) == ["PSH", "SQT", "PLL", "LGR", "BRG", "HSP"])
        #expect(response.rule?.maxRir == 2)
        #expect(response.rule?.workingSets == 2)
        #expect(response.rule?.requiredStreak == 2)
        #expect(response.rule?.masterStep == 10)
        #expect(response.activeProgram?.name == "Program V2")

        let sqt = try series("SQT", in: response)
        #expect(sqt.currentStep == 2)
        #expect(sqt.stepName == "Jackknife squat")
        #expect(sqt.inProgram)
        #expect(sqt.programExercises.first?.reps == "8-15")
        #expect(sqt.lastEvent?.eventType == "advance")
        #expect(sqt.sessions.count == 1)
        #expect(sqt.sessions.first?.sets.count == 2)
        #expect(sqt.sessions.first?.sets.first?.rir == 5)
        #expect(sqt.sessions.first?.countsTowardCurrentStep == false)
    }

    @Test func seriesWithoutStepDataAreNotSetUp() throws {
        let response = try decodeLive()
        for code in ["PSH", "PLL", "HSP"] {
            let item = try series(code, in: response)
            #expect(item.steps.isEmpty, "\(code) should have no steps")
            #expect(CCLadderLogic.isSetUp(item) == false, "\(code) should not be set up")
            #expect(item.currentStep == nil)
            #expect(CCLadderLogic.showsAdvance(item) == false)
            #expect(CCLadderLogic.showsGoBack(item) == false)
            #expect(CCLadderLogic.isMaster(item) == false)
        }
    }

    /// Build-time check of every step standard the bridge sends: ten steps,
    /// numbered 1...10, named, and each target equal to the rule table.
    @Test func setUpSeriesStepStandardsMatchTheBridgeRule() throws {
        let response = try decodeLive()
        let rule = try #require(response.rule)
        #expect(rule.targetRepsByStep.count == 10)
        for code in ["SQT", "LGR", "BRG"] {
            let item = try series(code, in: response)
            #expect(CCLadderLogic.isSetUp(item), "\(code) should be set up")
            #expect(item.steps.count == 10, "\(code) should have 10 steps")
            #expect(item.steps.map(\.step) == Array(1...10), "\(code) steps should be numbered 1...10")
            for step in item.steps {
                #expect(!step.name.trimmingCharacters(in: .whitespaces).isEmpty, "\(code) step \(step.step) has no name")
                #expect(!(step.workingReps ?? "").isEmpty, "\(code) step \(step.step) has no working range")
                let expected = try #require(rule.targetRepsByStep[step.step], "rule has no target for step \(step.step)")
                #expect(step.targetReps == expected, "\(code) step \(step.step) target \(String(describing: step.targetReps)) != rule \(expected)")
            }
            if let current = CCLadderLogic.currentStepInfo(item) {
                #expect(current.name == item.stepName)
                #expect(item.targetReps == current.targetReps)
            }
        }
    }

    @Test func advanceHiddenWhenNotReady() throws {
        let sqt = try series("SQT", in: try decodeLive())
        #expect(sqt.ready == false)
        #expect(CCLadderLogic.showsAdvance(sqt) == false)
        #expect(CCLadderLogic.changeRequest(for: sqt, direction: .advance) == nil)
    }

    @Test func advanceShownWhenReadyBelowStepTen() throws {
        var lgr = try series("LGR", in: try decodeLive())
        lgr.ready = true
        lgr.streak = 2
        #expect(CCLadderLogic.showsAdvance(lgr))
        let request = try #require(CCLadderLogic.changeRequest(for: lgr, direction: .advance))
        #expect(request.series == "LGR")
        #expect(request.eventType == "advance")
        #expect(request.fromStep == 1)
        #expect(request.toStep == 2)
        #expect(request.createdBy == "app")

        lgr.currentStep = 9
        #expect(CCLadderLogic.showsAdvance(lgr))
    }

    @Test func stepTenIsMasterWithoutAdvance() throws {
        var brg = try series("BRG", in: try decodeLive())
        brg.currentStep = 10
        brg.ready = true
        #expect(CCLadderLogic.isMaster(brg))
        #expect(CCLadderLogic.showsAdvance(brg) == false)
        #expect(CCLadderLogic.showsGoBack(brg))
        #expect(CCLadderLogic.changeRequest(for: brg, direction: .advance) == nil)
    }

    /// The bridge's master flag does not hide Advance below step 10.
    @Test func masterFlagBelowStepTenStillShowsAdvance() throws {
        var flagged = try series("BRG", in: try decodeLive())
        flagged.master = true
        flagged.currentStep = 1
        flagged.ready = true
        #expect(CCLadderLogic.isMaster(flagged) == false)
        #expect(CCLadderLogic.showsAdvance(flagged))
        let request = try #require(CCLadderLogic.changeRequest(for: flagged, direction: .advance))
        #expect(request.fromStep == 1)
        #expect(request.toStep == 2)
    }

    /// Step 10 is the master step even if the bridge rule says otherwise.
    @Test func ruleMasterStepDoesNotMoveTheBoundary() throws {
        let json = Self.liveJSON.replacingOccurrences(of: "\"master_step\":10", with: "\"master_step\":12")
        #expect(json != Self.liveJSON)
        let response = try JSONDecoder().decode(CCLaddersResponse.self, from: Data(json.utf8))
        #expect(response.rule?.masterStep == 12)

        var brg = try series("BRG", in: response)
        brg.ready = true
        brg.currentStep = 10
        #expect(CCLadderLogic.isMaster(brg))
        #expect(CCLadderLogic.showsAdvance(brg) == false)
        #expect(CCLadderLogic.changeRequest(for: brg, direction: .advance) == nil)

        brg.currentStep = 9
        #expect(CCLadderLogic.isMaster(brg) == false)
        #expect(CCLadderLogic.showsAdvance(brg))
    }

    @Test func advanceHiddenWithoutACurrentStep() throws {
        var sqt = try series("SQT", in: try decodeLive())
        sqt.currentStep = nil
        sqt.ready = true
        #expect(CCLadderLogic.showsAdvance(sqt) == false)
        #expect(CCLadderLogic.showsGoBack(sqt) == false)
        #expect(CCLadderLogic.stepStatus(step: 1, current: nil) == .upcoming)
    }

    @Test func goBackHiddenAtStepOneAndShownAbove() throws {
        let response = try decodeLive()
        let lgr = try series("LGR", in: response)
        #expect(lgr.currentStep == 1)
        #expect(CCLadderLogic.showsGoBack(lgr) == false)
        #expect(CCLadderLogic.changeRequest(for: lgr, direction: .regress) == nil)

        let sqt = try series("SQT", in: response)
        #expect(CCLadderLogic.showsGoBack(sqt))
        let request = try #require(CCLadderLogic.changeRequest(for: sqt, direction: .regress))
        #expect(request.eventType == "regress")
        #expect(request.fromStep == 2)
        #expect(request.toStep == 1)
    }

    @Test func stepStatusMarksDoneCurrentAndUpcoming() {
        #expect(CCLadderLogic.stepStatus(step: 1, current: 2) == .done)
        #expect(CCLadderLogic.stepStatus(step: 2, current: 2) == .current)
        #expect(CCLadderLogic.stepStatus(step: 3, current: 2) == .upcoming)
    }

    @Test func decodingToleratesMissingStepsAndUnknownKeys() throws {
        let json = #"""
        {"series":[{"series":"PSH","label":"Push-up","current_step":null,"brand_new_key":{"x":1}},
                   {"series":"SQT","label":"Squat","current_step":3,"ready":true}],
         "rule":{"max_rir":2},"extra":[1,2,3]}
        """#
        let response = try JSONDecoder().decode(CCLaddersResponse.self, from: Data(json.utf8))
        #expect(response.series.count == 2)
        #expect(response.series[0].steps.isEmpty)
        #expect(response.series[0].flags.isEmpty)
        #expect(response.series[0].sessions.isEmpty)
        #expect(response.series[1].steps.isEmpty)
        #expect(response.series[1].currentStep == 3)
        // Ready from the bridge still cannot show Advance without step data.
        #expect(CCLadderLogic.showsAdvance(response.series[1]) == false)
        #expect(response.rule?.targetRepsByStep.isEmpty == true)
    }

    @Test func decodingRequiresSeries() {
        let json = #"{"rule":{"max_rir":2}}"#
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(CCLaddersResponse.self, from: Data(json.utf8))
        }
    }

    @Test func readinessReasonsMapping() {
        // RIR is no longer part of the rule, and rep progress is good news.
        #expect(CCLadderLogic.readinessReasons(flags: ["rir_above_max"]).isEmpty)
        #expect(CCLadderLogic.readinessReasons(flags: ["rir_missing"]).isEmpty)
        #expect(CCLadderLogic.readinessReasons(flags: ["rep_progress"]).isEmpty)
        #expect(CCLadderLogic.readinessReasons(flags: ["reps_below_target"]) == ["Reps below target"])
        #expect(CCLadderLogic.readinessReasons(flags: ["possible_duplicate"]) == ["Possible duplicate session"])
        #expect(CCLadderLogic.readinessReasons(flags: ["hold_below_target"]) == ["Hold below target"])
        #expect(CCLadderLogic.readinessReasons(flags: ["different_step", "before_step_start"]).isEmpty)
        #expect(CCLadderLogic.readinessReasons(flags: ["reps_below_target", "reps_below_target", "rir_missing"]) == ["Reps below target"])
        #expect(CCLadderLogic.readinessReasons(flags: ["some_new_flag"]) == ["Some new flag"])
        #expect(CCLadderLogic.readinessReasons(flags: []).isEmpty)
    }

    @Test func seriesReadinessReasonsIncludeCountingSessionFlags() throws {
        let response = try decodeLive()
        let lgr = try series("LGR", in: response)
        #expect(CCLadderLogic.readinessReasons(for: lgr) == ["Possible duplicate session", "Reps below target"])
        // SQT's only session is at a different step, so it adds nothing.
        let sqt = try series("SQT", in: response)
        #expect(CCLadderLogic.readinessReasons(for: sqt).isEmpty)
    }

    @Test func setsSummaryShowsRepsAtRIR() throws {
        let lgr = try series("LGR", in: try decodeLive())
        let session = try #require(lgr.sessions.first)
        #expect(CCLadderLogic.setsSummary(session.sets) == "10 @ RIR 3 · 10 @ RIR 3")
        // RIR is optional now, so a set without it shows reps only.
        #expect(CCLadderLogic.setsSummary([CCLadderSessionSet(setOrder: 1, reps: 8, rir: nil)]) == "8")
        #expect(CCLadderLogic.setsSummary([]) == "No sets")
    }

    @Test func setsSummaryShowsHoldSeconds() {
        let sets = [CCLadderSessionSet(setOrder: 2, reps: 60), CCLadderSessionSet(setOrder: 1, reps: 75)]
        #expect(CCLadderLogic.setsSummary(sets, isHold: true) == "1:15 · 1:00")
    }

    @Test func eventRequestEncodesSnakeCase() throws {
        let request = CCLadderEventRequest(series: "SQT", eventType: "advance", fromStep: 2, toStep: 3, reason: "r", createdBy: "app")
        let data = try JSONEncoder().encode(request)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["series"] as? String == "SQT")
        #expect(object["event_type"] as? String == "advance")
        #expect(object["from_step"] as? Int == 2)
        #expect(object["to_step"] as? Int == 3)
        #expect(object["created_by"] as? String == "app")
    }

    // MARK: - Graduate-at targets

    private func decodeTargets() throws -> CCLaddersResponse {
        try JSONDecoder().decode(CCLaddersResponse.self, from: Data(Self.targetsJSON.utf8))
    }

    @Test func decodesBookTargetsForAllSixSeries() throws {
        let response = try decodeTargets()
        let rule = try #require(response.rule)
        #expect(response.series.map(\.series) == ["PSH", "SQT", "PLL", "LGR", "BRG", "HSP"])
        #expect(rule.targetsBySeries.count == 6)
        #expect(rule.targetsBySeries["PSH"]?[1] == CCStepTarget(sets: 3, reps: 50, holdSec: nil, label: "3×50"))
        #expect(rule.targetsBySeries["HSP"]?[2] == CCStepTarget(sets: 1, reps: nil, holdSec: 60, label: "1:00 hold"))

        for item in response.series {
            #expect(CCLadderLogic.isSetUp(item), "\(item.series) should be set up")
            #expect(item.steps.map(\.step) == Array(1...10), "\(item.series) steps should be numbered 1...10")
            for step in item.steps {
                let expected = try #require(rule.targetsBySeries[item.series]?[step.step])
                #expect(step.targetLabel == expected.label, "\(item.series) step \(step.step) label")
                #expect(CCLadderLogic.stepTargetLabel(step, series: item.series, rule: rule) == expected.label)
            }
            #expect(CCLadderLogic.graduateAtText(item, rule: rule) != nil, "\(item.series) has no graduate-at text")
        }

        let psh = try series("PSH", in: response)
        #expect(CCLadderLogic.graduateAtText(psh, rule: rule) == "Graduate at 3×50")
        let sqt = try series("SQT", in: response)
        #expect(sqt.targetSets == 3)
        #expect(sqt.targetReps == 40)
        #expect(CCLadderLogic.graduateAtText(sqt, rule: rule) == "Graduate at 3×40")
        #expect(sqt.progress == CCRepProgress(bestTotalRepsLast: 52, bestTotalRepsPrev: 46, delta: 6, improved: true, pctOfTarget: 43.3))
        #expect(sqt.ready == false)
        #expect(CCLadderLogic.isImproving(sqt))
        let latest = try #require(sqt.sessions.first)
        #expect(latest.totalReps == 52)
        #expect(latest.pctOfTarget == 43.3)
        #expect(CCLadderLogic.showsRepProgress(latest))
        #expect(CCLadderLogic.showsRepProgress(sqt.sessions[1]) == false)
        // Sets carry no RIR and the summary does not ask for it.
        #expect(CCLadderLogic.setsSummary(latest.sets) == "18 · 17 · 17")
        #expect(CCLadderLogic.readinessReasons(for: sqt) == ["Reps below target"])

        let hsp = try series("HSP", in: response)
        #expect(hsp.targetHoldSec == 120)
        #expect(hsp.targetLabel == "2:00 hold")
        #expect(CCLadderLogic.graduateAtText(hsp, rule: rule) == "Graduate at 2:00 hold")
        #expect(CCLadderLogic.isHoldSeries(hsp, rule: rule))
        #expect(CCLadderLogic.isHoldSeries(sqt, rule: rule) == false)
        #expect(hsp.steps.prefix(3).map(\.targetHoldSec) == [120, 60, 120])
        #expect(hsp.steps.dropFirst(3).allSatisfy { $0.targetHoldSec == nil })
        let headstand = try #require(hsp.sessions.first)
        #expect(CCLadderLogic.setsSummary(headstand.sets, isHold: true) == "1:15")
        #expect(CCLadderLogic.sessionTotalsText(headstand, isHold: true) == "Total 75s · 63% of target")
    }

    @Test func oldPayloadDecodesWithoutTargets() throws {
        let response = try decodeLive()
        let rule = try #require(response.rule)
        #expect(rule.targetsBySeries.isEmpty)
        let sqt = try series("SQT", in: response)
        #expect(sqt.targetLabel == nil)
        #expect(sqt.targetSets == nil)
        #expect(sqt.targetHoldSec == nil)
        #expect(sqt.progress == nil)
        #expect(sqt.sessions.allSatisfy { $0.totalReps == nil && $0.pctOfTarget == nil })
        #expect(sqt.steps.allSatisfy { $0.targetLabel == nil && $0.bookName == nil && $0.pages == nil })
        #expect(sqt.steps.allSatisfy { CCLadderLogic.stepTargetLabel($0, series: "SQT", rule: rule) == nil })
        // Falls back to the old target reps.
        #expect(CCLadderLogic.graduateAtText(sqt, rule: rule) == "Graduate at 15 reps")
        #expect(CCLadderLogic.isHoldSeries(sqt, rule: rule) == false)
        #expect(CCLadderLogic.progressText(sqt.progress) == nil)
    }

    @Test func holdLabelFormatting() {
        #expect(CCLadderLogic.clockText(seconds: 120) == "2:00")
        #expect(CCLadderLogic.clockText(seconds: 75) == "1:15")
        #expect(CCLadderLogic.clockText(seconds: 5) == "0:05")
        #expect(CCLadderLogic.clockText(seconds: 0) == "0:00")
        #expect(CCLadderLogic.clockText(seconds: -3) == "0:00")
        #expect(CCLadderLogic.holdText(seconds: 60) == "1:00 hold")
        #expect(CCLadderLogic.composedLabel(CCStepTarget(sets: 1, holdSec: 120)) == "2:00 hold")
        #expect(CCLadderLogic.composedLabel(CCStepTarget(sets: 2, holdSec: 60)) == "2×1:00 hold")
        #expect(CCLadderLogic.composedLabel(CCStepTarget(sets: 3, reps: 40)) == "3×40")
        #expect(CCLadderLogic.composedLabel(CCStepTarget(sets: 2, reps: 1, label: "3×40")) == "3×40")
        #expect(CCLadderLogic.composedLabel(CCStepTarget(sets: 2, reps: 30, label: "  ")) == "2×30")
        #expect(CCLadderLogic.composedLabel(CCStepTarget(reps: 40)) == nil)
    }

    @Test func graduateTargetFallbacks() {
        let steps = [CCLadderStep(step: 1, name: "Wall headstand", workingReps: "8–15")]
        // Series sets × reps without a label.
        #expect(CCLadderLogic.graduateTarget(CCSeriesState(series: "PSH", currentStep: 1, targetReps: 40, targetSets: 3, steps: steps)) == "3×40")
        // Series hold without a label.
        #expect(CCLadderLogic.graduateTarget(CCSeriesState(series: "HSP", currentStep: 1, targetSets: 1, targetHoldSec: 120, steps: steps)) == "2:00 hold")
        // Old target reps, then the working range.
        #expect(CCLadderLogic.graduateTarget(CCSeriesState(series: "SQT", currentStep: 1, targetReps: 15, steps: steps)) == "15 reps")
        #expect(CCLadderLogic.graduateTarget(CCSeriesState(series: "SQT", currentStep: 1, steps: steps)) == "8–15 reps")
        #expect(CCLadderLogic.graduateTarget(CCSeriesState(series: "SQT", currentStep: nil, steps: steps)) == nil)
    }

    @Test func graduateTargetUsesRuleTableWhenStepHasNone() throws {
        let response = try decodeTargets()
        let rule = try #require(response.rule)
        let bare = CCSeriesState(series: "HSP", currentStep: 2, steps: [CCLadderStep(step: 2, name: "Crow stand")])
        #expect(CCLadderLogic.graduateAtText(bare, rule: rule) == "Graduate at 1:00 hold")
        #expect(CCLadderLogic.isHoldSeries(bare, rule: rule))
        #expect(CCLadderLogic.isHoldSeries(bare) == false)
    }

    @Test func progressDisplayText() {
        let up = CCRepProgress(bestTotalRepsLast: 52, bestTotalRepsPrev: 46, delta: 6, improved: true, pctOfTarget: 43.3)
        #expect(CCLadderLogic.progressText(up) == "Rep progress: 46 → 52 (+6) · 43% of target")
        let computed = CCRepProgress(bestTotalRepsLast: 40, bestTotalRepsPrev: 43)
        #expect(CCLadderLogic.progressText(computed) == "Rep progress: 43 → 40 (−3)")
        let flat = CCRepProgress(bestTotalRepsLast: 120, bestTotalRepsPrev: 120, delta: 0, pctOfTarget: 100)
        #expect(CCLadderLogic.progressText(flat) == "Rep progress: 120 → 120 (±0) · 100% of target")
        let firstOnly = CCRepProgress(bestTotalRepsLast: 40, pctOfTarget: 26.7)
        #expect(CCLadderLogic.progressText(firstOnly) == "Rep progress: 40 · 27% of target")
        let hold = CCRepProgress(bestTotalRepsLast: 75, bestTotalRepsPrev: 60, delta: 15, improved: true, pctOfTarget: 62.5)
        #expect(CCLadderLogic.progressText(hold, isHold: true) == "Hold progress: 60s → 75s (+15s) · 63% of target")
        #expect(CCLadderLogic.progressText(nil) == nil)
        #expect(CCLadderLogic.progressText(CCRepProgress()) == nil)

        let session = CCLadderSession(totalReps: 52, pctOfTarget: 43.3)
        #expect(CCLadderLogic.sessionTotalsText(session) == "Total 52 · 43% of target")
        #expect(CCLadderLogic.sessionTotalsText(CCLadderSession(totalReps: 75), isHold: true) == "Total 75s")
        #expect(CCLadderLogic.sessionTotalsText(CCLadderSession()) == nil)

        // improved == true is progress even when the series is not ready.
        #expect(CCLadderLogic.isImproving(CCSeriesState(series: "SQT", progress: up, ready: false)))
        #expect(CCLadderLogic.isImproving(CCSeriesState(series: "SQT", progress: flat)) == false)
        #expect(CCLadderLogic.isImproving(CCSeriesState(series: "SQT")) == false)
    }

    @Test func ruleTextDescribesTheGraduateAtRule() throws {
        let text = CCLadderLogic.ruleText(try decodeTargets().rule)
        #expect(text.contains("graduate-at target in 2 consecutive sessions"))
        #expect(text.contains("RIR") == false)
        #expect(text.contains("working range") == false)
    }

    @Test func loggerHintShowsTheGraduateAtTarget() throws {
        let response = try decodeTargets()
        let knee = try #require(CCLadderLogic.loggerHint(
            exerciseKey: "cc leg raise ladder - step 1 knee tuck",
            exerciseName: "CC leg raise ladder - step 1 Knee tuck",
            in: response
        ))
        #expect(knee == CCLoggerLadderHint(text: "Graduate at 3×40", isHold: false))

        let headstand = try #require(CCLadderLogic.loggerHint(
            exerciseKey: "Wall headstand",
            exerciseName: "CC handstand ladder - step 1 Wall headstand",
            in: response
        ))
        #expect(headstand == CCLoggerLadderHint(text: "Graduate at 2:00 hold", isHold: true))

        // The program still names step 2, but the ladder has moved on.
        var moved = response
        let index = try #require(moved.series.firstIndex { $0.series == "SQT" })
        moved.series[index].currentStep = 3
        moved.series[index].targetLabel = nil
        moved.series[index].targetSets = nil
        moved.series[index].targetReps = nil
        let squat = try #require(CCLadderLogic.loggerHint(
            exerciseKey: "Jackknife squat",
            exerciseName: "CC squat ladder - step 2 Jackknife squat",
            in: moved
        ))
        #expect(squat.text == "Ladder now at step 3 · Supported squat · graduate at 3×30")

        // Units follow the logged step, not the current one. HSP is on step 1 (a hold).
        let pushUp = try #require(CCLadderLogic.loggerHint(
            exerciseKey: "Half handstand push-up",
            exerciseName: "CC handstand ladder - step 4 Half handstand push-up",
            in: response
        ))
        #expect(pushUp == CCLoggerLadderHint(text: "Ladder now at step 1 · Wall headstand · graduate at 2:00 hold", isHold: false))

        // HSP moved to step 4 (reps), but the program still logs the step 2 hold.
        var hspMoved = response
        let hspIndex = try #require(hspMoved.series.firstIndex { $0.series == "HSP" })
        hspMoved.series[hspIndex].currentStep = 4
        hspMoved.series[hspIndex].targetLabel = nil
        hspMoved.series[hspIndex].targetSets = nil
        hspMoved.series[hspIndex].targetHoldSec = nil
        let crow = try #require(CCLadderLogic.loggerHint(
            exerciseKey: "Crow stand",
            exerciseName: "CC handstand ladder - step 2 Crow stand",
            in: hspMoved
        ))
        #expect(crow.isHold)
        #expect(crow.text.hasPrefix("Ladder now at step 4 · Half handstand push-up"))
        let hspSeries = try #require(hspMoved.series.first { $0.series == "HSP" })
        #expect(CCLadderLogic.loggedStep(hspSeries, exerciseKey: "", exerciseName: "CC handstand ladder - Half handstand push-up")?.step == 4)

        #expect(CCLadderLogic.loggerHint(exerciseKey: "Knee tuck", exerciseName: "Knee tuck", in: nil) == nil)
        #expect(CCLadderLogic.loggerHint(exerciseKey: "lat pulldown", exerciseName: "Lat pulldown", in: response) == nil)
        #expect(CCLadderLogic.isLadderExerciseName("CC bridge ladder - step 1 Short bridge"))
        #expect(CCLadderLogic.isLadderExerciseName("Short bridge") == false)
    }

    /// The new /api/cc/ladders shape: book graduate-at targets for all six
    /// series, HSP steps 1-3 as timed holds, rep progress on SQT and HSP.
    static let targetsJSON = #"""
    {"generated_at":"2026-09-30T12:29:09.967Z",
     "rule":{"description":"A session qualifies when it reaches the step graduate-at target. Ready after 2 consecutive qualifying sessions.","required_streak":2,"master_step":10,"targets_by_series":{"PSH":{"1":{"sets":3,"reps":50,"hold_sec":null,"label":"3×50"},"2":{"sets":3,"reps":40,"hold_sec":null,"label":"3×40"},"3":{"sets":3,"reps":30,"hold_sec":null,"label":"3×30"},"4":{"sets":2,"reps":25,"hold_sec":null,"label":"2×25"},"5":{"sets":2,"reps":20,"hold_sec":null,"label":"2×20"},"6":{"sets":2,"reps":20,"hold_sec":null,"label":"2×20"},"7":{"sets":2,"reps":20,"hold_sec":null,"label":"2×20"},"8":{"sets":2,"reps":20,"hold_sec":null,"label":"2×20"},"9":{"sets":2,"reps":10,"hold_sec":null,"label":"2×10"},"10":{"sets":1,"reps":100,"hold_sec":null,"label":"1×100"}},"SQT":{"1":{"sets":3,"reps":50,"hold_sec":null,"label":"3×50"},"2":{"sets":3,"reps":40,"hold_sec":null,"label":"3×40"},"3":{"sets":3,"reps":30,"hold_sec":null,"label":"3×30"},"4":{"sets":2,"reps":50,"hold_sec":null,"label":"2×50"},"5":{"sets":2,"reps":30,"hold_sec":null,"label":"2×30"},"6":{"sets":2,"reps":20,"hold_sec":null,"label":"2×20"},"7":{"sets":2,"reps":20,"hold_sec":null,"label":"2×20"},"8":{"sets":2,"reps":20,"hold_sec":null,"label":"2×20"},"9":{"sets":2,"reps":20,"hold_sec":null,"label":"2×20"},"10":{"sets":2,"reps":50,"hold_sec":null,"label":"2×50"}},"PLL":{"1":{"sets":3,"reps":40,"hold_sec":null,"label":"3×40"},"2":{"sets":3,"reps":30,"hold_sec":null,"label":"3×30"},"3":{"sets":3,"reps":20,"hold_sec":null,"label":"3×20"},"4":{"sets":2,"reps":15,"hold_sec":null,"label":"2×15"},"5":{"sets":2,"reps":10,"hold_sec":null,"label":"2×10"},"6":{"sets":2,"reps":10,"hold_sec":null,"label":"2×10"},"7":{"sets":2,"reps":9,"hold_sec":null,"label":"2×9"},"8":{"sets":2,"reps":8,"hold_sec":null,"label":"2×8"},"9":{"sets":2,"reps":7,"hold_sec":null,"label":"2×7"},"10":{"sets":2,"reps":6,"hold_sec":null,"label":"2×6"}},"LGR":{"1":{"sets":3,"reps":40,"hold_sec":null,"label":"3×40"},"2":{"sets":3,"reps":35,"hold_sec":null,"label":"3×35"},"3":{"sets":3,"reps":30,"hold_sec":null,"label":"3×30"},"4":{"sets":3,"reps":25,"hold_sec":null,"label":"3×25"},"5":{"sets":2,"reps":20,"hold_sec":null,"label":"2×20"},"6":{"sets":2,"reps":15,"hold_sec":null,"label":"2×15"},"7":{"sets":2,"reps":15,"hold_sec":null,"label":"2×15"},"8":{"sets":2,"reps":15,"hold_sec":null,"label":"2×15"},"9":{"sets":2,"reps":15,"hold_sec":null,"label":"2×15"},"10":{"sets":2,"reps":30,"hold_sec":null,"label":"2×30"}},"BRG":{"1":{"sets":3,"reps":50,"hold_sec":null,"label":"3×50"},"2":{"sets":3,"reps":40,"hold_sec":null,"label":"3×40"},"3":{"sets":3,"reps":30,"hold_sec":null,"label":"3×30"},"4":{"sets":2,"reps":25,"hold_sec":null,"label":"2×25"},"5":{"sets":2,"reps":20,"hold_sec":null,"label":"2×20"},"6":{"sets":2,"reps":15,"hold_sec":null,"label":"2×15"},"7":{"sets":2,"reps":10,"hold_sec":null,"label":"2×10"},"8":{"sets":2,"reps":8,"hold_sec":null,"label":"2×8"},"9":{"sets":2,"reps":6,"hold_sec":null,"label":"2×6"},"10":{"sets":2,"reps":30,"hold_sec":null,"label":"2×30"}},"HSP":{"1":{"sets":1,"reps":null,"hold_sec":120,"label":"2:00 hold"},"2":{"sets":1,"reps":null,"hold_sec":60,"label":"1:00 hold"},"3":{"sets":1,"reps":null,"hold_sec":120,"label":"2:00 hold"},"4":{"sets":2,"reps":20,"hold_sec":null,"label":"2×20"},"5":{"sets":2,"reps":15,"hold_sec":null,"label":"2×15"},"6":{"sets":2,"reps":12,"hold_sec":null,"label":"2×12"},"7":{"sets":2,"reps":10,"hold_sec":null,"label":"2×10"},"8":{"sets":2,"reps":8,"hold_sec":null,"label":"2×8"},"9":{"sets":2,"reps":6,"hold_sec":null,"label":"2×6"},"10":{"sets":1,"reps":5,"hold_sec":null,"label":"1×5"}}}},
     "active_program":{"id":"qa-program","name":"Program V2","version":3},
     "series":[
      {"series":"PSH","label":"Push-up","current_step":1,"step_name":"Wall push-up","since":"2026-09-15T04:00:00.000Z","target_reps":50,"target_sets":3,"target_hold_sec":null,"target_label":"3×50","progress":null,"master":false,"ready":false,"streak":0,"required_streak":2,"flags":[],"in_program":false,"program_exercises":[],"last_event":null,"sessions":[],"steps":[
        {"step":1,"name":"Wall push-up","target_sets":3,"target_reps":50,"target_hold_sec":null,"target_label":"3×50"},
        {"step":2,"name":"Incline push-up","target_sets":3,"target_reps":40,"target_hold_sec":null,"target_label":"3×40"},
        {"step":3,"name":"Kneeling push-up","target_sets":3,"target_reps":30,"target_hold_sec":null,"target_label":"3×30"},
        {"step":4,"name":"Half push-up","target_sets":2,"target_reps":25,"target_hold_sec":null,"target_label":"2×25"},
        {"step":5,"name":"Full push-up","target_sets":2,"target_reps":20,"target_hold_sec":null,"target_label":"2×20"},
        {"step":6,"name":"Close push-up","target_sets":2,"target_reps":20,"target_hold_sec":null,"target_label":"2×20"},
        {"step":7,"name":"Uneven push-up","target_sets":2,"target_reps":20,"target_hold_sec":null,"target_label":"2×20"},
        {"step":8,"name":"Half one-arm push-up","target_sets":2,"target_reps":20,"target_hold_sec":null,"target_label":"2×20"},
        {"step":9,"name":"Lever push-up","target_sets":2,"target_reps":10,"target_hold_sec":null,"target_label":"2×10"},
        {"step":10,"name":"One-arm push-up","target_sets":1,"target_reps":100,"target_hold_sec":null,"target_label":"1×100"}]},
      {"series":"SQT","label":"Squat","current_step":2,"step_name":"Jackknife squat","since":"2026-09-15T04:00:00.000Z","target_reps":40,"target_sets":3,"target_hold_sec":null,"target_label":"3×40","progress":{"best_total_reps_last":52,"best_total_reps_prev":46,"delta":6,"improved":true,"pct_of_target":43.3},"master":false,"ready":false,"streak":0,"required_streak":2,"flags":[],"in_program":true,"program_exercises":[{"day":"Lower B + Cond","exercise":"CC squat ladder - step 2 Jackknife squat","step":2,"sets":2,"reps":"8-15"}],"last_event":null,"sessions":[{"workout_id":"qa-sqt-2","session_date":"2026-09-29","program_day":null,"title":null,"exercise":"Jackknife squat","step":2,"sets":[{"set_order":1,"reps":18,"rir":null,"load_lb":0},{"set_order":2,"reps":17,"rir":null,"load_lb":0},{"set_order":3,"reps":17,"rir":null,"load_lb":0}],"counts_toward_current_step":true,"qualifying":false,"flags":["rep_progress","reps_below_target"],"total_reps":52,"pct_of_target":43.3},{"workout_id":"qa-sqt-1","session_date":"2026-09-26","program_day":null,"title":null,"exercise":"Jackknife squat","step":2,"sets":[{"set_order":1,"reps":16,"rir":null,"load_lb":0},{"set_order":2,"reps":15,"rir":null,"load_lb":0},{"set_order":3,"reps":15,"rir":null,"load_lb":0}],"counts_toward_current_step":true,"qualifying":false,"flags":["reps_below_target"],"total_reps":46,"pct_of_target":38.3}],"steps":[
        {"step":1,"name":"Shoulderstand squat","target_sets":3,"target_reps":50,"target_hold_sec":null,"target_label":"3×50"},
        {"step":2,"name":"Jackknife squat","target_sets":3,"target_reps":40,"target_hold_sec":null,"target_label":"3×40"},
        {"step":3,"name":"Supported squat","target_sets":3,"target_reps":30,"target_hold_sec":null,"target_label":"3×30"},
        {"step":4,"name":"Half squat","target_sets":2,"target_reps":50,"target_hold_sec":null,"target_label":"2×50"},
        {"step":5,"name":"Full squat","target_sets":2,"target_reps":30,"target_hold_sec":null,"target_label":"2×30"},
        {"step":6,"name":"Close squat","target_sets":2,"target_reps":20,"target_hold_sec":null,"target_label":"2×20"},
        {"step":7,"name":"Uneven squat","target_sets":2,"target_reps":20,"target_hold_sec":null,"target_label":"2×20"},
        {"step":8,"name":"Half one-leg squat","target_sets":2,"target_reps":20,"target_hold_sec":null,"target_label":"2×20"},
        {"step":9,"name":"Assisted one-leg squat","target_sets":2,"target_reps":20,"target_hold_sec":null,"target_label":"2×20"},
        {"step":10,"name":"One-leg squat (pistol)","target_sets":2,"target_reps":50,"target_hold_sec":null,"target_label":"2×50"}]},
      {"series":"PLL","label":"Pull-up","current_step":1,"step_name":"Vertical pull","since":"2026-09-15T04:00:00.000Z","target_reps":40,"target_sets":3,"target_hold_sec":null,"target_label":"3×40","progress":null,"master":false,"ready":false,"streak":0,"required_streak":2,"flags":[],"in_program":false,"program_exercises":[],"last_event":null,"sessions":[],"steps":[
        {"step":1,"name":"Vertical pull","target_sets":3,"target_reps":40,"target_hold_sec":null,"target_label":"3×40"},
        {"step":2,"name":"Horizontal pull","target_sets":3,"target_reps":30,"target_hold_sec":null,"target_label":"3×30"},
        {"step":3,"name":"Jackknife pull-up","target_sets":3,"target_reps":20,"target_hold_sec":null,"target_label":"3×20"},
        {"step":4,"name":"Half pull-up","target_sets":2,"target_reps":15,"target_hold_sec":null,"target_label":"2×15"},
        {"step":5,"name":"Full pull-up","target_sets":2,"target_reps":10,"target_hold_sec":null,"target_label":"2×10"},
        {"step":6,"name":"Close pull-up","target_sets":2,"target_reps":10,"target_hold_sec":null,"target_label":"2×10"},
        {"step":7,"name":"Uneven pull-up","target_sets":2,"target_reps":9,"target_hold_sec":null,"target_label":"2×9"},
        {"step":8,"name":"Half one-arm pull-up","target_sets":2,"target_reps":8,"target_hold_sec":null,"target_label":"2×8"},
        {"step":9,"name":"Assisted one-arm pull-up","target_sets":2,"target_reps":7,"target_hold_sec":null,"target_label":"2×7"},
        {"step":10,"name":"One-arm pull-up","target_sets":2,"target_reps":6,"target_hold_sec":null,"target_label":"2×6"}]},
      {"series":"LGR","label":"Leg raise","current_step":1,"step_name":"Knee tuck","since":"2026-09-15T04:00:00.000Z","target_reps":40,"target_sets":3,"target_hold_sec":null,"target_label":"3×40","progress":{"best_total_reps_last":120,"best_total_reps_prev":120,"delta":0,"improved":false,"pct_of_target":100},"master":false,"ready":true,"streak":2,"required_streak":2,"flags":[],"in_program":true,"program_exercises":[{"day":"Upper Push","exercise":"CC leg raise ladder - step 1 Knee tuck","step":1,"sets":2,"reps":"8-15"}],"last_event":null,"sessions":[{"workout_id":"qa-lgr-2","session_date":"2026-09-29","program_day":null,"title":null,"exercise":"Knee tuck","step":1,"sets":[{"set_order":1,"reps":40,"rir":null,"load_lb":0},{"set_order":2,"reps":40,"rir":null,"load_lb":0},{"set_order":3,"reps":40,"rir":null,"load_lb":0}],"counts_toward_current_step":true,"qualifying":true,"flags":[],"total_reps":120,"pct_of_target":100},{"workout_id":"qa-lgr-1","session_date":"2026-09-22","program_day":null,"title":null,"exercise":"Knee tuck","step":1,"sets":[{"set_order":1,"reps":40,"rir":null,"load_lb":0},{"set_order":2,"reps":40,"rir":null,"load_lb":0},{"set_order":3,"reps":40,"rir":null,"load_lb":0}],"counts_toward_current_step":true,"qualifying":true,"flags":[],"total_reps":120,"pct_of_target":100}],"steps":[
        {"step":1,"name":"Knee tuck","target_sets":3,"target_reps":40,"target_hold_sec":null,"target_label":"3×40"},
        {"step":2,"name":"Flat knee raise","target_sets":3,"target_reps":35,"target_hold_sec":null,"target_label":"3×35"},
        {"step":3,"name":"Flat bent-leg raise","target_sets":3,"target_reps":30,"target_hold_sec":null,"target_label":"3×30"},
        {"step":4,"name":"Flat frog raise","target_sets":3,"target_reps":25,"target_hold_sec":null,"target_label":"3×25"},
        {"step":5,"name":"Flat straight-leg raise","target_sets":2,"target_reps":20,"target_hold_sec":null,"target_label":"2×20"},
        {"step":6,"name":"Hanging knee raise","target_sets":2,"target_reps":15,"target_hold_sec":null,"target_label":"2×15"},
        {"step":7,"name":"Hanging bent-leg raise","target_sets":2,"target_reps":15,"target_hold_sec":null,"target_label":"2×15"},
        {"step":8,"name":"Hanging frog raise","target_sets":2,"target_reps":15,"target_hold_sec":null,"target_label":"2×15"},
        {"step":9,"name":"Partial hanging straight-leg raise","target_sets":2,"target_reps":15,"target_hold_sec":null,"target_label":"2×15"},
        {"step":10,"name":"Hanging straight-leg raise","target_sets":2,"target_reps":30,"target_hold_sec":null,"target_label":"2×30"}]},
      {"series":"BRG","label":"Bridge","current_step":1,"step_name":"Short bridge","since":"2026-09-15T04:00:00.000Z","target_reps":50,"target_sets":3,"target_hold_sec":null,"target_label":"3×50","progress":{"best_total_reps_last":40,"best_total_reps_prev":null,"delta":null,"improved":false,"pct_of_target":26.7},"master":false,"ready":false,"streak":0,"required_streak":2,"flags":[],"in_program":true,"program_exercises":[{"day":"Upper Physique","exercise":"CC bridge ladder - step 1 Short bridge","step":1,"sets":2,"reps":"8-15"}],"last_event":null,"sessions":[{"workout_id":"qa-brg-1","session_date":"2026-09-21","program_day":null,"title":null,"exercise":"Short bridge","step":1,"sets":[{"set_order":1,"reps":20,"rir":null,"load_lb":0},{"set_order":2,"reps":20,"rir":null,"load_lb":0}],"counts_toward_current_step":true,"qualifying":false,"flags":["reps_below_target"],"total_reps":40,"pct_of_target":26.7}],"steps":[
        {"step":1,"name":"Short bridge","target_sets":3,"target_reps":50,"target_hold_sec":null,"target_label":"3×50"},
        {"step":2,"name":"Straight bridge","target_sets":3,"target_reps":40,"target_hold_sec":null,"target_label":"3×40"},
        {"step":3,"name":"Angled bridge","target_sets":3,"target_reps":30,"target_hold_sec":null,"target_label":"3×30"},
        {"step":4,"name":"Head bridge","target_sets":2,"target_reps":25,"target_hold_sec":null,"target_label":"2×25"},
        {"step":5,"name":"Half bridge","target_sets":2,"target_reps":20,"target_hold_sec":null,"target_label":"2×20"},
        {"step":6,"name":"Full bridge","target_sets":2,"target_reps":15,"target_hold_sec":null,"target_label":"2×15"},
        {"step":7,"name":"Wall-walk bridge (down)","target_sets":2,"target_reps":10,"target_hold_sec":null,"target_label":"2×10"},
        {"step":8,"name":"Wall-walk bridge (up)","target_sets":2,"target_reps":8,"target_hold_sec":null,"target_label":"2×8"},
        {"step":9,"name":"Closing bridge","target_sets":2,"target_reps":6,"target_hold_sec":null,"target_label":"2×6"},
        {"step":10,"name":"Stand-to-stand bridge","target_sets":2,"target_reps":30,"target_hold_sec":null,"target_label":"2×30"}]},
      {"series":"HSP","label":"Handstand push-up","current_step":1,"step_name":"Wall headstand","since":"2026-09-15T04:00:00.000Z","target_reps":null,"target_sets":1,"target_hold_sec":120,"target_label":"2:00 hold","progress":{"best_total_reps_last":75,"best_total_reps_prev":60,"delta":15,"improved":true,"pct_of_target":62.5},"master":false,"ready":false,"streak":0,"required_streak":2,"flags":[],"in_program":false,"program_exercises":[],"last_event":null,"sessions":[{"workout_id":"qa-hsp-2","session_date":"2026-09-28","program_day":null,"title":null,"exercise":"Wall headstand","step":1,"sets":[{"set_order":1,"reps":75,"rir":null,"load_lb":0}],"counts_toward_current_step":true,"qualifying":false,"flags":["rep_progress","hold_below_target"],"total_reps":75,"pct_of_target":62.5},{"workout_id":"qa-hsp-1","session_date":"2026-09-25","program_day":null,"title":null,"exercise":"Wall headstand","step":1,"sets":[{"set_order":1,"reps":60,"rir":null,"load_lb":0}],"counts_toward_current_step":true,"qualifying":false,"flags":["hold_below_target"],"total_reps":60,"pct_of_target":50}],"steps":[
        {"step":1,"name":"Wall headstand","target_sets":1,"target_reps":null,"target_hold_sec":120,"target_label":"2:00 hold"},
        {"step":2,"name":"Crow stand","target_sets":1,"target_reps":null,"target_hold_sec":60,"target_label":"1:00 hold"},
        {"step":3,"name":"Wall handstand","target_sets":1,"target_reps":null,"target_hold_sec":120,"target_label":"2:00 hold"},
        {"step":4,"name":"Half handstand push-up","target_sets":2,"target_reps":20,"target_hold_sec":null,"target_label":"2×20"},
        {"step":5,"name":"Handstand push-up","target_sets":2,"target_reps":15,"target_hold_sec":null,"target_label":"2×15"},
        {"step":6,"name":"Close handstand push-up","target_sets":2,"target_reps":12,"target_hold_sec":null,"target_label":"2×12"},
        {"step":7,"name":"Uneven handstand push-up","target_sets":2,"target_reps":10,"target_hold_sec":null,"target_label":"2×10"},
        {"step":8,"name":"Half one-arm handstand push-up","target_sets":2,"target_reps":8,"target_hold_sec":null,"target_label":"2×8"},
        {"step":9,"name":"Lever handstand push-up","target_sets":2,"target_reps":6,"target_hold_sec":null,"target_label":"2×6"},
        {"step":10,"name":"One-arm handstand push-up","target_sets":1,"target_reps":5,"target_hold_sec":null,"target_label":"1×5"}]}
     ]}
    """#

    static let liveJSON = #"""
    {"generated_at":"2026-09-30T12:29:09.967Z",
     "rule":{"target_reps":"per series: top of the current step's working range (series[].target_reps)","target_reps_by_step":{"1":15,"2":15,"3":15,"4":15,"5":15,"6":12,"7":12,"8":12,"9":8,"10":8},"max_rir":2,"working_sets":2,"required_streak":2,"master_step":10},
     "active_program":{"id":"d79f1d3f-f553-4d18-8081-d85943344397","name":"Program V2","version":3},
     "series":[
      {"series":"PSH","label":"Push-up","current_step":null,"step_name":null,"since":null,"target_reps":null,"master":false,"ready":false,"streak":0,"required_streak":2,"flags":[],"in_program":false,"program_exercises":[],"last_event":null,"sessions":[],"steps":[]},
      {"series":"SQT","label":"Squat","current_step":2,"step_name":"Jackknife squat","since":"2026-09-26T14:35:00.000Z","target_reps":15,"master":false,"ready":false,"streak":0,"required_streak":2,"flags":[],"in_program":true,"program_exercises":[{"day":"Lower B + Cond","exercise":"CC squat ladder - step 2 Jackknife squat","step":2,"sets":2,"reps":"8-15"}],"last_event":{"id":"0944c064-a842-464a-bd7b-c2813c9e1546","series":"SQT","event_type":"advance","from_step":1,"to_step":2,"occurred_at":"2026-09-26T14:35:00.000Z","reason":"baseline","created_by":"coach"},"sessions":[{"workout_id":"59cb7ce8-7fc1-42f0-994c-f6688452a5f8","session_date":"2026-09-24","program_day":"Day5_LowerB_Cond","title":"Lower B","exercise":"Shoulderstand squat","step":1,"sets":[{"set_order":6,"reps":15,"rir":5,"load_lb":0},{"set_order":7,"reps":15,"rir":5,"load_lb":0}],"counts_toward_current_step":false,"qualifying":false,"flags":["different_step","before_step_start","rir_above_max"]}],"steps":[
        {"step":1,"name":"Shoulderstand squat","working_reps":"8–15","target_reps":15},
        {"step":2,"name":"Jackknife squat","working_reps":"8–15","target_reps":15},
        {"step":3,"name":"Supported squat","working_reps":"8–15","target_reps":15},
        {"step":4,"name":"Half squat","working_reps":"8–15","target_reps":15},
        {"step":5,"name":"Full squat","working_reps":"8–15","target_reps":15},
        {"step":6,"name":"Close squat","working_reps":"6–12","target_reps":12},
        {"step":7,"name":"Uneven squat","working_reps":"6–12","target_reps":12},
        {"step":8,"name":"Half one-leg squat","working_reps":"6–12","target_reps":12},
        {"step":9,"name":"Assisted one-leg squat","working_reps":"3–8","target_reps":8},
        {"step":10,"name":"One-leg squat (pistol)","working_reps":"3–8","target_reps":8}
      ]},
      {"series":"PLL","label":"Pull-up","current_step":null,"step_name":null,"since":null,"target_reps":null,"master":false,"ready":false,"streak":0,"required_streak":2,"flags":[],"in_program":false,"program_exercises":[],"last_event":null,"sessions":[],"steps":[]},
      {"series":"LGR","label":"Leg raise","current_step":1,"step_name":"Knee tuck","since":"2026-09-15T04:00:00.000Z","target_reps":15,"master":false,"ready":false,"streak":0,"required_streak":2,"flags":["possible_duplicate"],"in_program":true,"program_exercises":[{"day":"Upper Push","exercise":"CC leg raise ladder - step 1 Knee tuck","step":1,"sets":2,"reps":"8-15"}],"last_event":{"id":"55365173-6407-43ae-b554-6576dec2915c","series":"LGR","event_type":"start","from_step":null,"to_step":1,"occurred_at":"2026-09-15T04:00:00.000Z","reason":"baseline","created_by":"coach"},"sessions":[{"workout_id":"425845cf-95b9-4ec8-a506-00a19e33fb18","session_date":"2026-09-16","program_day":"Day2_UpperPush","title":"Upper Push","exercise":"Knee tuck","step":1,"sets":[{"set_order":3,"reps":10,"rir":3,"load_lb":0},{"set_order":4,"reps":10,"rir":3,"load_lb":0}],"counts_toward_current_step":true,"qualifying":false,"flags":["rir_above_max","reps_below_target","possible_duplicate"]},{"workout_id":"495ad24a-1738-4676-8701-5f585ec5eea6","session_date":"2026-09-15","program_day":"Day2_UpperPush","title":"Upper Push","exercise":"Knee tuck","step":1,"sets":[{"set_order":8,"reps":10,"rir":3,"load_lb":0},{"set_order":9,"reps":10,"rir":3,"load_lb":0}],"counts_toward_current_step":true,"qualifying":false,"flags":["rir_above_max","reps_below_target"]}],"steps":[
        {"step":1,"name":"Knee tuck","working_reps":"8–15","target_reps":15},
        {"step":2,"name":"Flat knee raise","working_reps":"8–15","target_reps":15},
        {"step":3,"name":"Flat bent-leg raise","working_reps":"8–15","target_reps":15},
        {"step":4,"name":"Flat frog raise","working_reps":"8–15","target_reps":15},
        {"step":5,"name":"Flat straight-leg raise","working_reps":"8–15","target_reps":15},
        {"step":6,"name":"Hanging knee raise","working_reps":"6–12","target_reps":12},
        {"step":7,"name":"Hanging bent-leg raise","working_reps":"6–12","target_reps":12},
        {"step":8,"name":"Hanging frog raise","working_reps":"6–12","target_reps":12},
        {"step":9,"name":"Partial hanging straight-leg raise","working_reps":"3–8","target_reps":8},
        {"step":10,"name":"Hanging straight-leg raise","working_reps":"3–8","target_reps":8}
      ]},
      {"series":"BRG","label":"Bridge","current_step":1,"step_name":"Short bridge","since":"2026-09-21T04:00:00.000Z","target_reps":15,"master":false,"ready":false,"streak":0,"required_streak":2,"flags":[],"in_program":true,"program_exercises":[{"day":"Upper Physique","exercise":"CC bridge ladder - step 1 Short bridge","step":1,"sets":2,"reps":"8-15"}],"last_event":{"id":"32e9feba-70a8-4bf7-9ad8-69ac15423cdb","series":"BRG","event_type":"start","from_step":null,"to_step":1,"occurred_at":"2026-09-21T04:00:00.000Z","reason":"baseline","created_by":"coach"},"sessions":[{"workout_id":"ee35b96a-64d6-4243-bb31-0d23698c5899","session_date":"2026-09-21","program_day":"Day4_UpperPhysique","title":"Upper Physique","exercise":"Short bridge","step":1,"sets":[{"set_order":9,"reps":8,"rir":2,"load_lb":0},{"set_order":10,"reps":8,"rir":2,"load_lb":0}],"counts_toward_current_step":true,"qualifying":false,"flags":["reps_below_target"]}],"steps":[
        {"step":1,"name":"Short bridge","working_reps":"8–15","target_reps":15},
        {"step":2,"name":"Straight bridge","working_reps":"8–15","target_reps":15},
        {"step":3,"name":"Angled bridge","working_reps":"8–15","target_reps":15},
        {"step":4,"name":"Head bridge","working_reps":"8–15","target_reps":15},
        {"step":5,"name":"Half bridge","working_reps":"8–15","target_reps":15},
        {"step":6,"name":"Full bridge","working_reps":"6–12","target_reps":12},
        {"step":7,"name":"Wall-walk bridge (down)","working_reps":"6–12","target_reps":12},
        {"step":8,"name":"Wall-walk bridge (up)","working_reps":"6–12","target_reps":12},
        {"step":9,"name":"Closing bridge","working_reps":"3–8","target_reps":8},
        {"step":10,"name":"Stand-to-stand bridge","working_reps":"3–8","target_reps":8}
      ]},
      {"series":"HSP","label":"Handstand push-up","current_step":null,"step_name":null,"since":null,"target_reps":null,"master":false,"ready":false,"streak":0,"required_streak":2,"flags":[],"in_program":false,"program_exercises":[],"last_event":null,"sessions":[],"steps":[]}
     ]}
    """#
}
