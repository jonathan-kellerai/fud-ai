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
        #expect(CCLadderLogic.readinessReasons(flags: ["rir_above_max"]) == ["RIR above 2"])
        #expect(CCLadderLogic.readinessReasons(flags: ["reps_below_target"]) == ["Reps below target"])
        #expect(CCLadderLogic.readinessReasons(flags: ["possible_duplicate"]) == ["Possible duplicate session"])
        #expect(CCLadderLogic.readinessReasons(flags: ["rir_missing"]) == ["RIR missing"])
        #expect(CCLadderLogic.readinessReasons(flags: ["different_step", "before_step_start"]).isEmpty)
        #expect(CCLadderLogic.readinessReasons(flags: ["rir_above_max", "rir_above_max", "rir_missing"]) == ["RIR above 2", "RIR missing"])
        #expect(CCLadderLogic.readinessReasons(flags: ["some_new_flag"]) == ["Some new flag"])
        #expect(CCLadderLogic.readinessReasons(flags: []).isEmpty)
    }

    @Test func seriesReadinessReasonsIncludeCountingSessionFlags() throws {
        let response = try decodeLive()
        let lgr = try series("LGR", in: response)
        #expect(CCLadderLogic.readinessReasons(for: lgr) == ["Possible duplicate session", "RIR above 2", "Reps below target"])
        // SQT's only session is at a different step, so it adds nothing.
        let sqt = try series("SQT", in: response)
        #expect(CCLadderLogic.readinessReasons(for: sqt).isEmpty)
    }

    @Test func setsSummaryShowsRepsAtRIR() throws {
        let lgr = try series("LGR", in: try decodeLive())
        let session = try #require(lgr.sessions.first)
        #expect(CCLadderLogic.setsSummary(session.sets) == "10 @ RIR 3 · 10 @ RIR 3")
        #expect(CCLadderLogic.setsSummary([CCLadderSessionSet(setOrder: 1, reps: 8, rir: nil)]) == "8 @ RIR –")
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
