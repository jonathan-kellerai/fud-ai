//
//  CCStepForm.swift
//  calorietracker
//
//  JL Physical — start/end form art and cues for one Convict Conditioning
//  step. Step names and targets still come from the bridge; the art and cues
//  are bundled presentation copy keyed by series code and step number.
//

import Foundation

/// Which ladder step the form sheet shows.
struct CCFormSelection: Identifiable, Equatable {
    var series: String
    var step: Int

    var id: String { CCFormCues.key(series: series, step: step) }
}

/// Asset names for the bundled step illustrations in Assets.xcassets/CCLadderArt.
enum CCStepArt {
    enum Phase: String, CaseIterable, Identifiable {
        case start, end

        var id: String { rawValue }
    }

    /// ("SQT", 3, .start) -> "CCLadderArt/SQT-03-start".
    static func name(series: String, step: Int, phase: Phase) -> String {
        String(format: "CCLadderArt/%@-%02d-%@", series.uppercased(), step, phase.rawValue)
    }
}

/// Form cues and VoiceOver text for one step, from CCFormCues.json.
struct CCFormCue: Decodable, Equatable {
    var start: [String]
    var end: [String]
    var altStart: String
    var altEnd: String

    func cues(for phase: CCStepArt.Phase) -> [String] {
        switch phase {
        case .start: start
        case .end: end
        }
    }

    func altText(for phase: CCStepArt.Phase) -> String {
        switch phase {
        case .start: altStart
        case .end: altEnd
        }
    }
}

/// The bundled cues, decoded once. A missing or malformed file means no cues,
/// never a crash: the sheet still shows the target and the art.
enum CCFormCues {
    static let all: [String: CCFormCue] = load(from: .main)

    /// ("SQT", 3) -> "SQT-03".
    static func key(series: String, step: Int) -> String {
        String(format: "%@-%02d", series.uppercased(), step)
    }

    static func cue(series: String, step: Int) -> CCFormCue? {
        all[key(series: series, step: step)]
    }

    static func load(from bundle: Bundle) -> [String: CCFormCue] {
        guard let url = bundle.url(forResource: "CCFormCues", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return [:] }
        return decode(data)
    }

    static func decode(_ data: Data) -> [String: CCFormCue] {
        (try? JSONDecoder().decode([String: CCFormCue].self, from: data)) ?? [:]
    }
}

extension CCLadderLogic {
    /// The bridge's step with this number, nil when the series does not send it.
    static func stepInfo(_ number: Int, in series: CCSeriesState) -> CCLadderStep? {
        series.steps.first { $0.step == number }
    }

    /// The form sheet target for a logger exercise: its series at the current
    /// step, or at the logged step when the series has not started.
    static func formSelection(exerciseKey: String, exerciseName: String, in response: CCLaddersResponse?) -> CCFormSelection? {
        guard let response,
              let series = loggerSeries(exerciseKey: exerciseKey, exerciseName: exerciseName, in: response),
              let step = series.currentStep ?? loggedStep(series, exerciseKey: exerciseKey, exerciseName: exerciseName)?.step
        else { return nil }
        return CCFormSelection(series: series.series, step: step)
    }
}
