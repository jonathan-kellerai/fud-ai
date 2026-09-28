import Foundation

/// Port of recon-bench.html. Every syringe-unit, blend, flag, and supply figure
/// goes through this type. Views format the values it returns.
enum ReconMath {
    static let epsilon = 1e-9
    static let footerText = "This app converts doses to syringe units and tracks supply. It sets no doses and recommends no protocol. Research compounds; not medical advice."
    static let massToMicrograms: [String: Double] = ["mcg": 1, "mg": 1000]
    static let peopleOrder = ["jonathan", "victoria"]
    static let peopleNames = ["jonathan": "Jonathan", "victoria": "Victoria"]
    static let calculatorOrder = ["tesamorelin", "retatrutide", "hcg", "mt2", "bpc157", "tb500", "glow", "nad", "kisspeptin", "aod9604", "cjc1295"]
    static let roster: [String: [String]] = [
        "jonathan": ["tesamorelin", "retatrutide", "bpc157", "tb500", "mt2", "hcg", "kisspeptin"],
        "victoria": ["glow", "mt2"]
    ]
    /// On-hand amounts in the vial's unit. Missing means the operator did not specify one.
    static let onHandDefault: [String: [String: Double]] = [
        "jonathan": [
            "tesamorelin": 35,
            "retatrutide": 10,
            "bpc157": 50,
            "tb500": 10,
            "mt2": 40,
            "hcg": 15000,
            "kisspeptin": 20
        ],
        "victoria": [:],
        "calc": [
            "aod9604": 10,
            "cjc1295": 5
        ]
    ]
    static let provenanceDescription = [
        "LABEL": "FDA prescribing info",
        "TRIAL": "published clinical trial",
        "USER": "operator's own figure",
        "NONE": "no validated human dose"
    ]
    static let weekdayShort = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    static let monthShort = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    struct Flag: Equatable, Identifiable {
        var level: String
        var code: String
        var text: String
        var id: String { code }
    }

    struct ComputeResult {
        var ok = false
        var error: String?
        var flags: [Flag] = []
        var dimension: String?
        var vialN = Double.nan
        var doseN = Double.nan
        var concentration = Double.nan
        var concentrationUnit = ""
        var perUnit = Double.nan
        var perUnitUnit = ""
        var units = Double.nan
        var volumeML = Double.nan
        var dosesPerVial = Double.nan
        var daysPerVial = Double.nan

        init(error: String? = nil) {
            self.error = error
        }
    }

    struct ReverseResult {
        var ok = false
        var amountN = Double.nan
        var dimension = ""
        var volumeML = Double.nan
    }

    struct BlendComponent: Equatable, Identifiable {
        var name: String
        var amount: Double
        var unit: String
        var limitN: Double?
        var id: String { name }
    }

    struct BlendComponentResult: Equatable, Identifiable {
        var name: String
        var vialAmount: Double
        var unit: String
        var concentration: Double
        var concentrationUnit: String
        var perUnit: Double
        var perUnitUnit: String
        var deliveredN: Double
        var over: Bool
        var id: String { name }
    }

    struct BlendResult {
        var ok = false
        var components: [BlendComponentResult] = []
        var flags: [Flag] = []
        var total: ReverseResult?
        var totalCheck: ComputeResult?
    }

    struct Preset: Equatable, Identifiable {
        var dose: Double?
        var unit: String?
        var perWeek: Double?
        var provenance: String
        var isDefault: Bool
        var draw: Double?
        var id: String { "\(provenance)-\(dose ?? -1)-\(draw ?? -1)-\(unit ?? "")-\(isDefault)" }
    }

    struct Compound: Equatable, Identifiable {
        var key: String
        var name: String
        var sub: String?
        var abbreviation: String
        var vial: Double
        var vialUnit: String
        var water: Double?
        var diluent: String
        var provenance: String?
        var tip: String?
        var calculatorOnly: Bool
        var blend: [BlendComponent]
        var presets: [Preset]
        var id: String { key }
    }

    struct Card: Equatable, Codable {
        var vial: Double
        var water: Double?
        var dose: Double?
        var doseUnit: String
        var draw: Double?
        var perWeek: Double?
        var onHand: Double?
    }

    struct VialConfig: Equatable {
        var vial: Double
        var vialUnit: String
        var water: Double
    }

    struct Frequency: Equatable, Codable {
        var type: String
        var days: [Int]
        var n: Double?

        init(type: String, days: [Int] = [], n: Double? = nil) {
            self.type = type
            self.days = days
            self.n = n
        }
    }

    struct ScheduleEntry: Equatable, Codable, Identifiable {
        var id: String
        var person: String
        var compound: String
        var dose: Double?
        var doseUnit: String?
        var draw: Double?
        var freq: Frequency
        var start: String
        var weeks: Double
    }

    struct DoseInfo {
        var ok = false
        var error: String?
        var amountN = Double.nan
        var dimension: String?
        var unitsText = "—"
        var doseText = ""
        var components: [BlendComponentResult]?
        var blendFlags: [Flag] = []
        var result: ComputeResult?
    }

    struct Occurrence: Identifiable {
        var date: String
        var dayNumber: Int
        var index: Int
        var entry: ScheduleEntry
        var entryIndex: Int
        var info: DoseInfo
        var poolKey: String
        var status: String
        var flags: [String]
        var duplicate: Bool
        var cumulativeN: Double
        var id: String { entry.id + "|" + date + "|" + String(entryIndex) + "|" + String(index) }
    }

    struct SupplyPool {
        var key: String
        var person: String
        var compound: String
        var dimension: String
        var onHandN: Double
        var known: Bool
        var consumedN: Double
        var scheduledN: Double
        var count: Int
        var covered: Int
        var short: Int
        var errors: Int
        var runOut: String?
        var lastCovered: String?
    }

    struct Duplicate {
        var person: String
        var compound: String
        var date: String
        var count: Int
    }

    struct SupplySimulation {
        var occurrences: [Occurrence]
        var pools: [String: SupplyPool]
        var poolOrder: [String]
        var duplicates: [Duplicate]
    }

    struct Coverage {
        var info: DoseInfo
        var dosesPerWeek: Double
        var scheduled: Int
        var totalN: Double
        var known: Bool
        var onHandN = Double.nan
        var dosesCovered = Double.nan
        var weeksCovered = Double.nan
    }

    struct SupplyLine: Identifiable, Equatable {
        var id: String
        var level: String
        var text: String
    }

    static let compounds: [String: Compound] = makeCompounds()

    static func compound(_ key: String) -> Compound? {
        compounds[key]
    }

    static func compute(
        vialAmount: Double,
        vialUnit: String,
        waterML: Double,
        dose: Double,
        doseUnit: String,
        perWeek: Double = .nan
    ) -> ComputeResult {
        var result = ComputeResult()
        guard let vialNormalized = normalize(amount: vialAmount, unit: vialUnit) else {
            result.error = "BAD_VIAL_UNIT"
            return result
        }
        result.dimension = vialNormalized.dimension
        let hasDose = dose > 0
        if hasDose {
            guard let doseNormalized = normalize(amount: dose, unit: doseUnit) else {
                result.error = "BAD_DOSE_UNIT"
                return result
            }
            if doseNormalized.dimension != vialNormalized.dimension {
                result.error = "IU_MISMATCH"
                let text = vialNormalized.dimension == "IU"
                    ? "IU vial requires an IU dose. IU is never converted to mass."
                    : "Mass vial cannot take an IU dose. IU is never converted to mass."
                result.flags.append(Flag(level: "red", code: "iu-mismatch", text: text))
                return result
            }
            result.doseN = doseNormalized.value
        }
        guard vialAmount > 0 else {
            result.error = "NEED_VIAL"
            return result
        }
        result.vialN = vialNormalized.value
        if hasDose {
            result.dosesPerVial = clean(result.vialN / result.doseN)
            if result.doseN > result.vialN + epsilon {
                result.flags.append(Flag(level: "red", code: "exceeds-vial", text: "Dose exceeds the whole vial."))
            }
            if perWeek > 0 {
                result.daysPerVial = clean(result.dosesPerVial * 7 / perWeek)
                if result.daysPerVial > 28 + epsilon {
                    result.flags.append(Flag(
                        level: "amber",
                        code: "outlasts-28",
                        text: "Vial outlasts 28 days at this frequency (\(fmtTrim(result.daysPerVial, 1)) days)."
                    ))
                }
            }
        }
        guard waterML > 0 else {
            result.error = "NEED_WATER"
            result.flags = sortedFlags(result.flags)
            return result
        }
        if waterML > 3 + epsilon {
            result.flags.append(Flag(
                level: "amber",
                code: "water-high",
                text: "Water above 3 mL. Many 5–10 mg vials only hold ~3 mL."
            ))
        }
        let concentrationN = vialNormalized.value / waterML
        result.concentration = clean(vialNormalized.dimension == "IU" ? concentrationN : concentrationN / 1000)
        result.concentrationUnit = vialNormalized.dimension == "IU" ? "IU/mL" : "mg/mL"
        result.perUnit = clean(concentrationN / 100)
        result.perUnitUnit = vialNormalized.dimension == "IU" ? "IU" : "mcg"
        guard hasDose else {
            result.error = "NEED_DOSE"
            result.flags = sortedFlags(result.flags)
            return result
        }
        result.units = clean(result.doseN * waterML * 100 / vialNormalized.value)
        result.volumeML = clean(result.units / 100)
        result.ok = true
        if result.units > 100 + epsilon {
            result.flags.append(Flag(level: "red", code: "exceeds-syringe", text: "Over 100 units: exceeds one U-100 syringe."))
        }
        if result.units < 5 - epsilon {
            result.flags.append(Flag(level: "amber", code: "small-draw", text: "Under 5 units: hard to read accurately on the syringe."))
        }
        let hasRed = result.flags.contains { $0.level == "red" }
        if !hasRed && result.units >= 5 - epsilon && result.units <= 100 + epsilon {
            result.flags.append(Flag(level: "green", code: "readable", text: "Draw is in the readable range (5–100 units)."))
        }
        result.flags = sortedFlags(result.flags)
        return result
    }

    static func reverseCompute(vialAmount: Double, vialUnit: String, waterML: Double, units: Double) -> ReverseResult {
        guard let vialNormalized = normalize(amount: vialAmount, unit: vialUnit),
              vialAmount > 0, waterML > 0, units >= 0 else {
            return ReverseResult()
        }
        return ReverseResult(
            ok: true,
            amountN: clean(units * vialNormalized.value / (waterML * 100)),
            dimension: vialNormalized.dimension,
            volumeML: clean(units / 100)
        )
    }

    static func blendBreakdown(
        blend: [BlendComponent],
        blendVialNominal: Double,
        vialAmount: Double,
        waterML: Double,
        units: Double
    ) -> BlendResult {
        let scale = vialAmount / blendVialNominal
        var result = BlendResult()
        let total = reverseCompute(vialAmount: vialAmount, vialUnit: "mg", waterML: waterML, units: units)
        guard total.ok, scale > 0 else { return result }
        result.total = total
        result.totalCheck = compute(vialAmount: vialAmount, vialUnit: "mg", waterML: waterML, dose: total.amountN, doseUnit: "mcg")
        result.ok = true
        for component in blend {
            let amount = clean(component.amount * scale)
            let base = compute(vialAmount: amount, vialUnit: component.unit, waterML: waterML, dose: .nan, doseUnit: component.unit)
            let reversed = reverseCompute(vialAmount: amount, vialUnit: component.unit, waterML: waterML, units: units)
            let over = component.limitN != nil && reversed.amountN > (component.limitN ?? 0) + epsilon
            result.components.append(BlendComponentResult(
                name: component.name,
                vialAmount: amount,
                unit: component.unit,
                concentration: base.concentration,
                concentrationUnit: base.concentrationUnit,
                perUnit: base.perUnit,
                perUnitUnit: base.perUnitUnit,
                deliveredN: reversed.amountN,
                over: over
            ))
            if over, let limit = component.limitN {
                result.flags.append(Flag(
                    level: "amber",
                    code: "blend-\(component.name)",
                    text: "\(component.name) above \(fmtAmountN(limit, "mass")) at this draw (\(fmtAmountN(reversed.amountN, "mass")))."
                ))
            }
        }
        return result
    }

    static func hasFlag(_ result: ComputeResult, _ code: String) -> Bool {
        result.flags.contains { $0.code == code }
    }

    static func sortedFlags(_ flags: [Flag]) -> [Flag] {
        let order = ["red": 0, "amber": 1, "green": 2]
        return flags.sorted { (order[$0.level] ?? 9) < (order[$1.level] ?? 9) }
    }

    static func worstLevel(_ flags: [Flag]) -> String? {
        let order = ["red": 0, "amber": 1, "green": 2]
        var bestRank = Int.max
        var best: String?
        for flag in flags {
            let rank = order[flag.level] ?? 9
            if rank < bestRank {
                bestRank = rank
                best = flag.level
            }
        }
        return best
    }

    static func normalize(amount: Double, unit: String) -> (value: Double, dimension: String)? {
        if unit == "IU" { return (amount, "IU") }
        guard let factor = massToMicrograms[unit] else { return nil }
        return (clean(amount * factor), "mass")
    }

    static func clean(_ value: Double) -> Double {
        guard value.isFinite else { return value }
        let rounded = jsRound(value * 1e9) / 1e9
        return rounded == 0 ? 0 : rounded
    }

    static func jsRound(_ value: Double) -> Double {
        guard value.isFinite else { return value }
        return floor(value + 0.5)
    }

    static func toNumber(_ value: String) -> Double {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard !trimmed.isEmpty else { return .nan }
        guard trimmed.range(of: #"^[-+]?(\d+\.?\d*|\.\d+)$"#, options: .regularExpression) != nil else { return .nan }
        return Double(trimmed) ?? .nan
    }

    static func fmtUnits(_ units: Double) -> String { fmtTrim(units, 2) }

    static func fmtML(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        return toFixed(clean(value), 3)
    }

    static func fmtAmountN(_ amount: Double, _ dimension: String) -> String {
        guard amount.isFinite else { return "—" }
        if dimension == "IU" { return fmtTrim(amount, 2) + " IU" }
        if amount >= 1000 - epsilon { return fmtTrim(amount / 1000, 3) + " mg" }
        return fmtTrim(amount, 2) + " mcg"
    }

    static func fmtAmountIn(_ amount: Double, unit: String) -> String {
        guard amount.isFinite else { return "—" }
        if unit == "IU" { return fmtTrim(amount, 2) + " IU" }
        if unit == "mg" { return fmtTrim(amount / 1000, 3) + " mg" }
        return fmtTrim(amount, 2) + " mcg"
    }

    static func fmtTrim(_ value: Double, _ digits: Int) -> String {
        guard value.isFinite else { return "—" }
        var text = toFixed(clean(value), digits)
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        if text == "-0" { text = "0" }
        return group(text)
    }

    static func jsNumber(_ value: Double) -> String {
        guard value.isFinite else { return "" }
        let cleaned = clean(value)
        if abs(cleaned) < 1e15 && cleaned == jsRound(cleaned) {
            let body = integerString(abs(cleaned))
            return cleaned < 0 ? "-" + body : body
        }
        return fmtTrim(cleaned, 12).replacingOccurrences(of: ",", with: "")
    }

    static func whyText(_ error: String?) -> String {
        switch error {
        case "NEED_VIAL": return "Enter the vial amount."
        case "NEED_WATER": return "Enter the water volume."
        case "NEED_DOSE": return "Enter a dose."
        case "IU_MISMATCH": return "Unit mismatch — no conversion made."
        default: return "Enter values."
        }
    }

    static func defaultPreset(for key: String) -> Preset? {
        compounds[key]?.presets.first { $0.isDefault }
    }

    static func defaultCard(person: String, key: String) -> Card {
        let compound = compounds[key]
        let preset = defaultPreset(for: key)
        let onHand = onHandDefault[person]?[key]
        let doseUnit: String
        if let unit = preset?.unit, !unit.isEmpty {
            doseUnit = unit
        } else {
            doseUnit = compound?.vialUnit == "IU" ? "IU" : "mg"
        }
        return Card(
            vial: compound?.vial ?? .nan,
            water: compound?.water,
            dose: preset?.dose,
            doseUnit: doseUnit,
            draw: preset?.draw,
            perWeek: preset?.perWeek,
            onHand: onHand
        )
    }

    static func defaultCards() -> [String: [String: Card]] {
        var cards: [String: [String: Card]] = [:]
        for person in peopleOrder {
            var personCards: [String: Card] = [:]
            for key in roster[person] ?? [] {
                personCards[key] = defaultCard(person: person, key: key)
            }
            cards[person] = personCards
        }
        return cards
    }

    static func config(for card: Card, key: String) -> VialConfig {
        VialConfig(vial: card.vial, vialUnit: compounds[key]?.vialUnit ?? "mg", water: card.water ?? .nan)
    }

    static func matchesPreset(key: String, dose: Double, unit: String) -> Preset? {
        guard let compound = compounds[key], let entered = normalize(amount: dose, unit: unit), entered.value > 0 else { return nil }
        for preset in compound.presets {
            guard let presetDose = preset.dose, let presetUnit = preset.unit,
                  let normalized = normalize(amount: presetDose, unit: presetUnit) else { continue }
            if normalized.dimension == entered.dimension && abs(normalized.value - entered.value) < epsilon {
                return preset
            }
        }
        return nil
    }

    static func showsCustomDose(key: String, dose: Double, unit: String) -> Bool {
        guard let compound = compounds[key], compound.presets.contains(where: { $0.dose != nil }), dose > 0 else { return false }
        return matchesPreset(key: key, dose: dose, unit: unit) == nil
    }

    static func presetLabel(_ preset: Preset) -> String {
        if let draw = preset.draw {
            return fmtUnits(draw) + " unit draw" + (preset.isDefault ? " (default)" : "") + " · " + preset.provenance
        }
        let cadence: String
        if preset.perWeek == 7 { cadence = "/day" }
        else if preset.perWeek == 1 { cadence = "/week" }
        else { cadence = "" }
        return fmtTrim(preset.dose ?? .nan, 3) + " " + (preset.unit ?? "") + cadence + (preset.isDefault ? " (default)" : "") + " · " + preset.provenance
    }

    static func blendDoseField(vial: Double, vialUnit: String, water: Double, draw: Double) -> String {
        let reversed = reverseCompute(vialAmount: vial, vialUnit: vialUnit, waterML: water, units: draw)
        guard reversed.ok else { return "" }
        return fmtTrim(reversed.amountN / 1000, 6).replacingOccurrences(of: ",", with: "")
    }

    static func onHandText(value: Double?, key: String) -> String? {
        guard let value, value >= 0, let compound = compounds[key] else { return nil }
        var text = fmtTrim(value, 3) + " " + compound.vialUnit
        if compound.vial > 0 {
            text += " (" + fmtTrim(value / compound.vial, 2) + " × " + fmtTrim(compound.vial, 3) + " " + compound.vialUnit + " vials)"
        }
        return text
    }

    static func calculatorOnHandLine(key: String?, value: Double?, source: String) -> String {
        guard let key, let compound = compounds[key] else { return "" }
        let body: String
        if let text = onHandText(value: value, key: key) {
            body = "On hand (\(source)): \(text)"
        } else {
            body = "On hand: not set"
        }
        if compound.presets.isEmpty && compound.provenance == nil {
            return body + " · No preset dose or water volume supplied for this compound."
        }
        return body
    }

    static func dosesRemaining(onHand: Double?, vialUnit: String, doseN: Double, doseDimension: String?) -> Double {
        guard let onHand, onHand >= 0, doseN > 0, let doseDimension,
              let normalized = normalize(amount: onHand, unit: vialUnit),
              normalized.dimension == doseDimension else { return .nan }
        return normalized.value / doseN
    }

    static func daysFromRemaining(_ remaining: Double, perWeek: Double) -> Double {
        guard remaining.isFinite, perWeek > 0 else { return .nan }
        return remaining * 7 / perWeek
    }

    static func inventorySupplyDays(
        onHand: Double?,
        selectedUnit: String,
        catalogUnit: String,
        result: ComputeResult,
        perWeek: Double
    ) -> Double {
        guard selectedUnit == catalogUnit, result.ok, let onHand, onHand >= 0, perWeek > 0, result.doseN > 0,
              let normalized = normalize(amount: onHand, unit: selectedUnit),
              normalized.dimension == result.dimension else { return .nan }
        return normalized.value / result.doseN * 7 / perWeek
    }

    static func inventorySupplyDaysText(
        hasCompound: Bool,
        onHand: Double?,
        selectedUnit: String,
        catalogUnit: String,
        result: ComputeResult,
        perWeek: Double
    ) -> String {
        let days = inventorySupplyDays(onHand: onHand, selectedUnit: selectedUnit, catalogUnit: catalogUnit, result: result, perWeek: perWeek)
        if days.isFinite { return fmtTrim(days, 1) + " days" }
        guard hasCompound else { return "—" }
        if let onHand, onHand >= 0 { return perWeek > 0 ? "—" : "set frequency" }
        return "set on-hand"
    }

    static func vialDaysText(result: ComputeResult, perWeek: Double) -> String {
        if result.daysPerVial.isFinite { return fmtTrim(result.daysPerVial, 1) + " days" }
        return perWeek > 0 ? "—" : "set frequency"
    }

    static func remainingText(known: Bool, remaining: Double) -> String {
        guard known else { return "set on-hand" }
        return remaining.isFinite ? fmtTrim(remaining, 2) : "—"
    }

    static func supplyDaysText(known: Bool, remaining: Double, perWeek: Double) -> String {
        guard known else { return "set on-hand" }
        let days = daysFromRemaining(remaining, perWeek: perWeek)
        return days.isFinite ? fmtTrim(days, 1) + " days" : "—"
    }

    static func reverseCheckText(reverse: ReverseResult, doseUnit: String) -> String {
        guard reverse.ok else { return "—" }
        let showUnit = reverse.dimension == "IU" ? "IU" : (doseUnit == "mcg" || doseUnit == "mg" ? doseUnit : "mg")
        var text = fmtAmountIn(reverse.amountN, unit: showUnit)
        if reverse.dimension == "mass" {
            let other = showUnit == "mg" ? "mcg" : "mg"
            text += " (" + fmtAmountIn(reverse.amountN, unit: other) + ")"
        }
        return text + " · " + fmtML(reverse.volumeML) + " mL"
    }

    static func reverseMatchText(reverse: ReverseResult, result: ComputeResult, unitsText: String) -> (matched: Bool, text: String) {
        guard reverse.ok, result.ok else { return (false, "") }
        if abs(reverse.amountN - result.doseN) < epsilon {
            return (true, "Matches the entered dose.")
        }
        return (false, "Does not match the entered dose (\(unitsText) units).")
    }

    static func calculatorBlend(key: String, vialAmount: Double, vialUnit: String, water: Double, result: ComputeResult) -> (flags: [Flag], breakdown: BlendResult?) {
        guard let compound = compounds[key], !compound.blend.isEmpty else { return ([], nil) }
        if vialUnit != "mg" {
            return ([Flag(level: "amber", code: "blend-unit", text: "Blend breakdown needs the vial in mg.")], nil)
        }
        guard result.ok else { return ([], nil) }
        let breakdown = blendBreakdown(blend: compound.blend, blendVialNominal: compound.vial, vialAmount: vialAmount, waterML: water, units: result.units)
        return (breakdown.flags, breakdown)
    }

    static func entryDoseInfo(entry: ScheduleEntry, config: VialConfig) -> DoseInfo {
        guard let compound = compounds[entry.compound] else {
            return DoseInfo(error: "NEED_DOSE")
        }
        if !compound.blend.isEmpty {
            let reversed = reverseCompute(vialAmount: config.vial, vialUnit: config.vialUnit, waterML: config.water, units: entry.draw ?? .nan)
            if !reversed.ok {
                return DoseInfo(
                    error: "NEED_WATER",
                    dimension: "mass",
                    doseText: fmtUnits(entry.draw ?? .nan) + " u draw"
                )
            }
            let computed = compute(vialAmount: config.vial, vialUnit: config.vialUnit, waterML: config.water, dose: reversed.amountN, doseUnit: "mcg")
            let breakdown = blendBreakdown(blend: compound.blend, blendVialNominal: compound.vial, vialAmount: config.vial, waterML: config.water, units: entry.draw ?? .nan)
            return DoseInfo(
                ok: computed.ok,
                error: computed.error,
                amountN: reversed.amountN,
                dimension: "mass",
                unitsText: computed.ok ? fmtUnits(computed.units) : "—",
                doseText: fmtAmountN(reversed.amountN, "mass") + " blend",
                components: breakdown.components,
                blendFlags: breakdown.flags,
                result: computed
            )
        }
        let computed = compute(
            vialAmount: config.vial,
            vialUnit: config.vialUnit,
            waterML: config.water,
            dose: entry.dose ?? .nan,
            doseUnit: entry.doseUnit ?? ""
        )
        return DoseInfo(
            ok: computed.ok,
            error: computed.error,
            amountN: computed.error == "IU_MISMATCH" ? .nan : computed.doseN,
            dimension: computed.dimension,
            unitsText: computed.ok ? fmtUnits(computed.units) : "—",
            doseText: fmtTrim(entry.dose ?? .nan, 3) + " " + (entry.doseUnit ?? ""),
            result: computed
        )
    }

    static func entryUnitsText(entry: ScheduleEntry, config: (String, String) -> VialConfig) -> String {
        entryDoseInfo(entry: entry, config: config(entry.person, entry.compound)).unitsText
    }

    static func dosesPerWeek(_ frequency: Frequency) -> Double {
        switch frequency.type {
        case "daily": return 7
        case "weekly": return 1
        case "weekdays": return Double(frequency.days.count)
        case "everyN":
            guard let interval = frequency.n, interval > 0 else { return .nan }
            return 7 / interval
        default: return .nan
        }
    }

    static func frequencyText(_ frequency: Frequency) -> String {
        switch frequency.type {
        case "daily": return "daily"
        case "weekly": return "weekly"
        case "weekdays":
            return frequency.days.sorted().compactMap { day in
                weekdayShort.indices.contains(day) ? weekdayShort[day] : nil
            }.joined(separator: "/")
        case "everyN":
            return "every " + jsNumber(frequency.n ?? .nan) + " days"
        default: return ""
        }
    }

    static func expandEntry(_ entry: ScheduleEntry) -> [(date: String, dayNumber: Int, index: Int)] {
        let rounded = jsRound(entry.weeks * 7)
        guard rounded.isFinite, rounded > 0, rounded < 100_000, parseISO(entry.start) != nil else { return [] }
        let total = Int(rounded)
        var doses: [(date: String, dayNumber: Int, index: Int)] = []
        for offset in 0..<total {
            let date = addDays(entry.start, offset)
            let include: Bool
            switch entry.freq.type {
            case "daily": include = true
            case "weekly": include = offset % 7 == 0
            case "weekdays": include = entry.freq.days.contains(weekday(date))
            case "everyN":
                if let interval = entry.freq.n, interval >= 1, interval == floor(interval), interval < Double(Int.max) {
                    include = offset % Int(interval) == 0
                } else {
                    include = false
                }
            default: include = false
            }
            if include {
                doses.append((date, offset + 1, doses.count + 1))
            }
        }
        return doses
    }

    static func simulateSupply(
        entries: [ScheduleEntry],
        config: (String, String) -> VialConfig,
        onHand: (String, String) -> Double?
    ) -> SupplySimulation {
        var occurrences: [Occurrence] = []
        for (entryIndex, entry) in entries.enumerated() {
            let info = entryDoseInfo(entry: entry, config: config(entry.person, entry.compound))
            for dose in expandEntry(entry) {
                occurrences.append(Occurrence(
                    date: dose.date,
                    dayNumber: dose.dayNumber,
                    index: dose.index,
                    entry: entry,
                    entryIndex: entryIndex,
                    info: info,
                    poolKey: entry.person + "|" + entry.compound,
                    status: "ok",
                    flags: [],
                    duplicate: false,
                    cumulativeN: .nan
                ))
            }
        }
        occurrences.sort { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date < rhs.date }
            return lhs.entryIndex < rhs.entryIndex
        }
        var pools: [String: SupplyPool] = [:]
        var poolOrder: [String] = []
        for index in occurrences.indices {
            let key = occurrences[index].poolKey
            if pools[key] == nil {
                let compoundKey = occurrences[index].entry.compound
                let person = occurrences[index].entry.person
                let unit = compounds[compoundKey]?.vialUnit ?? "mg"
                let known = knownOnHand(onHand(person, compoundKey), unit: unit)
                pools[key] = SupplyPool(
                    key: key,
                    person: person,
                    compound: compoundKey,
                    dimension: unit == "IU" ? "IU" : "mass",
                    onHandN: known.amount,
                    known: known.known,
                    consumedN: 0,
                    scheduledN: 0,
                    count: 0,
                    covered: 0,
                    short: 0,
                    errors: 0,
                    runOut: nil,
                    lastCovered: nil
                )
                poolOrder.append(key)
            }
            guard var pool = pools[key] else { continue }
            let amount = occurrences[index].info.amountN
            if !(amount > 0) {
                occurrences[index].status = "error"
                pool.errors += 1
                occurrences[index].flags.append(occurrences[index].info.error == "IU_MISMATCH" ? "IU/mass mismatch" : "dose invalid")
                pools[key] = pool
                continue
            }
            pool.count += 1
            pool.scheduledN = clean(pool.scheduledN + amount)
            if !pool.known {
                occurrences[index].status = "noonhand"
                occurrences[index].flags.append("on-hand not set")
            } else {
                pool.consumedN = clean(pool.consumedN + amount)
                occurrences[index].cumulativeN = pool.consumedN
                if pool.consumedN > pool.onHandN + epsilon {
                    occurrences[index].status = "short"
                    pool.short += 1
                    if pool.runOut == nil { pool.runOut = occurrences[index].date }
                    occurrences[index].flags.append("past run-out: no material")
                } else {
                    pool.covered += 1
                    pool.lastCovered = occurrences[index].date
                }
            }
            if !occurrences[index].info.ok && occurrences[index].status == "ok" {
                occurrences[index].status = "nowater"
            }
            if !occurrences[index].info.ok {
                let message = occurrences[index].info.error == "NEED_WATER" ? "units: set water volume" : "units unavailable"
                occurrences[index].flags.append(message)
            }
            pools[key] = pool
        }
        var grouped: [String: [Int]] = [:]
        for index in occurrences.indices {
            let groupKey = occurrences[index].poolKey + "|" + occurrences[index].date
            grouped[groupKey, default: []].append(index)
        }
        var duplicates: [Duplicate] = []
        for indices in grouped.values {
            let identifiers = Set(indices.map { occurrences[$0].entry.id })
            guard identifiers.count > 1 else { continue }
            for index in indices {
                occurrences[index].duplicate = true
                occurrences[index].flags.append("same compound twice this day")
            }
            let first = occurrences[indices[0]]
            duplicates.append(Duplicate(person: first.entry.person, compound: first.entry.compound, date: first.date, count: indices.count))
        }
        return SupplySimulation(occurrences: occurrences, pools: pools, poolOrder: poolOrder, duplicates: duplicates)
    }

    static func coverage(entry: ScheduleEntry, config: VialConfig, onHand: Double?) -> Coverage {
        let compound = compounds[entry.compound]
        let info = entryDoseInfo(entry: entry, config: config)
        let perWeek = dosesPerWeek(entry.freq)
        let scheduled = expandEntry(entry).count
        var result = Coverage(
            info: info,
            dosesPerWeek: perWeek,
            scheduled: scheduled,
            totalN: clean(info.amountN * Double(scheduled)),
            known: (onHand ?? -1) >= 0
        )
        guard result.known, info.amountN > 0, let onHand, let unit = compound?.vialUnit,
              let normalized = normalize(amount: onHand, unit: unit) else { return result }
        result.onHandN = normalized.value
        result.dosesCovered = clean(normalized.value / info.amountN)
        result.weeksCovered = clean(result.dosesCovered / perWeek)
        return result
    }

    static func coverageMessage(entry: ScheduleEntry, config: VialConfig, onHand: Double?, simulation: SupplySimulation?) -> (level: String, text: String) {
        guard let compound = compounds[entry.compound] else { return ("red", "Dose cannot be used.") }
        let covered = coverage(entry: entry, config: config, onHand: onHand)
        if !covered.known {
            return ("amber", "\(compound.name): on-hand not set — supply cannot be computed; every dose is flagged.")
        }
        if !(covered.info.amountN > 0) {
            return ("red", "\(compound.name): dose cannot be used (\(covered.info.error ?? "invalid")).")
        }
        let dimension = compound.vialUnit == "IU" ? "IU" : "mass"
        let doseWord = covered.dosesPerWeek == 1 ? "dose" : "doses"
        var text = "\(compound.name) supply: \(fmtAmountN(covered.onHandN, dimension)) on hand ÷ \(fmtAmountN(covered.info.amountN, dimension)) per dose = \(fmtTrim(covered.dosesCovered, 2)) doses → covers \(fmtTrim(covered.weeksCovered, 2)) weeks at \(fmtTrim(covered.dosesPerWeek, 2)) \(doseWord)/week. This entry schedules \(covered.scheduled) doses (\(fmtAmountN(covered.totalN, dimension)))."
        var level = "amber"
        if let simulation {
            let mine = simulation.occurrences.filter { $0.entry.id == entry.id }
            let shortNumbers = mine.filter { $0.status == "short" }.map(\.index)
            let pool = simulation.pools[entry.person + "|" + entry.compound]
            if !shortNumbers.isEmpty {
                level = "red"
                let last = pool?.lastCovered.map(formatDate) ?? "none"
                let runOut = pool?.runOut.map(formatDate) ?? ""
                let span = shortNumbers.count > 1 ? "\(shortNumbers[0])–\(shortNumbers[shortNumbers.count - 1])" : "\(shortNumbers[0])"
                text += " Run-out: last covered dose \(last); out of material from \(runOut). Doses \(span) of this entry are flagged red."
            } else {
                text += " Schedule is covered by on-hand supply."
            }
        }
        return (level, text)
    }

    static func supplyLines(entries: [ScheduleEntry], simulation: SupplySimulation, config: (String, String) -> VialConfig, onHand: (String, String) -> Double?) -> [SupplyLine] {
        var lines: [SupplyLine] = []
        for entry in entries where entry.compound == "retatrutide" {
            let message = coverageMessage(entry: entry, config: config(entry.person, entry.compound), onHand: onHand(entry.person, entry.compound), simulation: simulation)
            lines.append(SupplyLine(id: "reta-" + entry.id, level: message.level, text: message.text))
        }
        for key in simulation.poolOrder {
            guard let pool = simulation.pools[key], let compound = compounds[pool.compound] else { continue }
            let person = peopleNames[pool.person] ?? pool.person
            var text: String
            var level = ""
            if !pool.known {
                level = "amber"
                text = "on-hand not set — all \(pool.count) scheduled doses flagged (\(fmtAmountN(pool.scheduledN, pool.dimension)) scheduled)."
            } else {
                text = "on hand \(fmtAmountN(pool.onHandN, pool.dimension)) · scheduled \(fmtAmountN(pool.scheduledN, pool.dimension)) over \(pool.count) doses · "
                if pool.short > 0 {
                    level = "red"
                    let through = pool.lastCovered.map { " through \(formatDate($0))" } ?? ""
                    let doseWord = pool.short == 1 ? "dose" : "doses"
                    text += "RUN-OUT: covers \(pool.covered) doses\(through); out from \(formatDate(pool.runOut ?? "")) (\(pool.short) \(doseWord) flagged red)."
                } else {
                    text += "covered; \(fmtAmountN(clean(pool.onHandN - pool.consumedN), pool.dimension)) left after schedule."
                }
            }
            if pool.errors > 0 {
                text += " \(pool.errors) dose(s) unusable (unit error)."
            }
            lines.append(SupplyLine(id: "pool-" + key, level: level, text: "\(person) · \(compound.name) — \(text)"))
        }
        for duplicate in simulation.duplicates {
            let person = peopleNames[duplicate.person] ?? duplicate.person
            let name = compounds[duplicate.compound]?.name ?? duplicate.compound
            lines.append(SupplyLine(
                id: "dup-\(duplicate.person)-\(duplicate.compound)-\(duplicate.date)",
                level: "amber",
                text: "Same-day duplicate: \(person) · \(name) is scheduled \(duplicate.count)× on \(formatDate(duplicate.date))."
            ))
        }
        return lines
    }

    static func parseISO(_ text: String) -> (year: Int, month: Int, day: Int)? {
        let parts = text.split(separator: "-")
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day) else { return nil }
        return (year, month, day)
    }

    static func addDays(_ iso: String, _ count: Int) -> String {
        guard let parts = parseISO(iso) else { return iso }
        let civil = civilFromDays(daysFromCivil(year: parts.year, month: parts.month, day: parts.day) + count)
        return isoString(year: civil.0, month: civil.1, day: civil.2)
    }

    static func weekday(_ iso: String) -> Int {
        guard let parts = parseISO(iso) else { return 0 }
        let raw = (daysFromCivil(year: parts.year, month: parts.month, day: parts.day) + 4) % 7
        return raw >= 0 ? raw : raw + 7
    }

    static func formatDate(_ iso: String) -> String {
        guard let parts = parseISO(iso) else { return iso }
        return "\(weekdayShort[weekday(iso)]) \(parts.day) \(monthShort[parts.month - 1]) \(parts.year)"
    }

    static func formatDateShort(_ iso: String) -> String {
        guard let parts = parseISO(iso) else { return iso }
        return "\(weekdayShort[weekday(iso)]) \(parts.day) \(monthShort[parts.month - 1])"
    }

    static func todayISO(now: Date = Date(), calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        return isoString(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    static func mondayOf(_ iso: String) -> String {
        let day = weekday(iso)
        return addDays(iso, -((day + 6) % 7))
    }

    static func shiftAnchor(_ iso: String, view: String, direction: Int) -> String {
        if view == "month" {
            guard let parts = parseISO(iso) else { return iso }
            let first = isoString(year: parts.year, month: parts.month, day: 1)
            guard let start = parseISO(first) else { return iso }
            var month = start.month + direction
            var year = start.year
            while month < 1 { month += 12; year -= 1 }
            while month > 12 { month -= 12; year += 1 }
            return isoString(year: year, month: month, day: 1)
        }
        return addDays(iso, 7 * direction)
    }

    static func weekDays(anchor: String) -> (label: String, days: [String]) {
        let start = mondayOf(anchor)
        let days = (0..<7).map { addDays(start, $0) }
        return (formatDateShort(start) + " – " + formatDateShort(addDays(start, 6)), days)
    }

    static func monthDays(anchor: String) -> (label: String, days: [(iso: String, inMonth: Bool)]) {
        guard let parts = parseISO(anchor) else { return ("", []) }
        let first = isoString(year: parts.year, month: parts.month, day: 1)
        let start = mondayOf(first)
        let days = (0..<42).map { offset -> (String, Bool) in
            let iso = addDays(start, offset)
            let inMonth = parseISO(iso)?.month == parts.month
            return (iso, inMonth)
        }
        return ("\(monthShort[parts.month - 1]) \(parts.year)", days)
    }

    static func shouldSyncTakenToBridge(syncEnabled: Bool, markingTaken: Bool) -> Bool {
        syncEnabled && markingTaken
    }

    private static func knownOnHand(_ raw: Double?, unit: String) -> (known: Bool, amount: Double) {
        guard let raw, raw >= 0, raw.isFinite, let normalized = normalize(amount: raw, unit: unit), normalized.value >= 0, normalized.value.isFinite else {
            return (false, .nan)
        }
        return (true, normalized.value)
    }

    private static func makeCompounds() -> [String: Compound] {
        let rows: [Compound] = [
            Compound(key: "tesamorelin", name: "Tesamorelin", sub: nil, abbreviation: "Tesa", vial: 5, vialUnit: "mg", water: 0.5, diluent: "water", provenance: "LABEL", tip: "Egrifta SV 1.4 mg/day. Egrifta WR is 1.28 mg/day. The 2 mg figure belongs to the original Egrifta, discontinued in the US.", calculatorOnly: false, blend: [], presets: [
                Preset(dose: 1.4, unit: "mg", perWeek: 7, provenance: "LABEL", isDefault: true, draw: nil),
                Preset(dose: 1.28, unit: "mg", perWeek: 7, provenance: "LABEL", isDefault: false, draw: nil)
            ]),
            Compound(key: "retatrutide", name: "Retatrutide", sub: nil, abbreviation: "Reta", vial: 10, vialUnit: "mg", water: 1.0, diluent: "water", provenance: "TRIAL", tip: "Phase 2 starting dose (Jastreboff 2023, NEJM 389:514). Trial ladder escalates 2 → 4 → 8 → 12 mg at intervals of at least 4 weeks. Phase 3 used 2 → 4 → 6 → 9 → 12.", calculatorOnly: false, blend: [], presets: [
                Preset(dose: 2, unit: "mg", perWeek: 1, provenance: "TRIAL", isDefault: true, draw: nil),
                Preset(dose: 4, unit: "mg", perWeek: 1, provenance: "TRIAL", isDefault: false, draw: nil),
                Preset(dose: 6, unit: "mg", perWeek: 1, provenance: "TRIAL", isDefault: false, draw: nil),
                Preset(dose: 8, unit: "mg", perWeek: 1, provenance: "TRIAL", isDefault: false, draw: nil)
            ]),
            Compound(key: "hcg", name: "HCG", sub: nil, abbreviation: "HCG", vial: 5000, vialUnit: "IU", water: 1.0, diluent: "water", provenance: "TRIAL", tip: "250–500 IU, 2–3×/week, described as an adjunct to testosterone therapy. Higher regimens (1,000–2,000 IU) appear in hypogonadotropic hypogonadism literature.", calculatorOnly: false, blend: [], presets: [
                Preset(dose: 500, unit: "IU", perWeek: nil, provenance: "TRIAL", isDefault: true, draw: nil),
                Preset(dose: 250, unit: "IU", perWeek: nil, provenance: "TRIAL", isDefault: false, draw: nil),
                Preset(dose: 1500, unit: "IU", perWeek: nil, provenance: "TRIAL", isDefault: false, draw: nil)
            ]),
            Compound(key: "mt2", name: "MT2", sub: nil, abbreviation: "MT2", vial: 10, vialUnit: "mg", water: 2.0, diluent: "water", provenance: "USER", tip: "Community loading convention. The only Phase I trial (Dorr 1996, n=3) used 0.025 mg/kg — roughly 1.9 mg at 77 kg, far above this figure. No validated maintenance dose exists.", calculatorOnly: false, blend: [], presets: [
                Preset(dose: 250, unit: "mcg", perWeek: nil, provenance: "USER", isDefault: true, draw: nil),
                Preset(dose: 500, unit: "mcg", perWeek: nil, provenance: "USER", isDefault: false, draw: nil)
            ]),
            Compound(key: "bpc157", name: "BPC-157", sub: nil, abbreviation: "BPC", vial: 10, vialUnit: "mg", water: 3.0, diluent: "water", provenance: "USER", tip: "No validated human dosing regimen exists. A 2026 review in Pharmaceutics reports no approved formulation, no validated dosing regimen, no completed Phase II, and fewer than 30 human subjects across three uncontrolled pilots. This figure is community convention, not evidence.", calculatorOnly: false, blend: [], presets: [
                Preset(dose: 500, unit: "mcg", perWeek: nil, provenance: "USER", isDefault: true, draw: nil)
            ]),
            Compound(key: "tb500", name: "TB-500", sub: nil, abbreviation: "TB", vial: 5, vialUnit: "mg", water: 1.0, diluent: "water", provenance: "USER", tip: "No completed human dose-ranging study by injection. The only randomised human trials of thymosin β4 were topical.", calculatorOnly: false, blend: [], presets: [
                Preset(dose: 2, unit: "mg", perWeek: nil, provenance: "USER", isDefault: true, draw: nil)
            ]),
            Compound(key: "glow", name: "Glow blend", sub: "GHK-Cu / BPC-157 / TB-500", abbreviation: "Glow", vial: 70, vialUnit: "mg", water: 2.0, diluent: "water", provenance: "USER", tip: "Fixed 50:10:10 ratio — components cannot be dosed independently. GHK-Cu human data is topical. No human data exists for the three-component combination.", calculatorOnly: false, blend: [
                BlendComponent(name: "GHK-Cu", amount: 50, unit: "mg", limitN: 2000),
                BlendComponent(name: "BPC-157", amount: 10, unit: "mg", limitN: 750),
                BlendComponent(name: "TB-500", amount: 10, unit: "mg", limitN: nil)
            ], presets: [
                Preset(dose: nil, unit: nil, perWeek: nil, provenance: "USER", isDefault: true, draw: 10)
            ]),
            Compound(key: "nad", name: "NAD+", sub: nil, abbreviation: "NAD", vial: 100, vialUnit: "mg", water: 0.5, diluent: "saline", provenance: "NONE", tip: "Subcutaneous NAD+ has no standardised dosing. Published human protocols are oral or IV only.", calculatorOnly: true, blend: [], presets: []),
            Compound(key: "kisspeptin", name: "Kisspeptin-10", sub: nil, abbreviation: "KP-10", vial: 10, vialUnit: "mg", water: nil, diluent: "water", provenance: "NONE", tip: "No validated chronic dose. Human studies used acute IV infusion. KP-10 has a ~4-minute plasma half-life.", calculatorOnly: false, blend: [], presets: []),
            Compound(key: "aod9604", name: "AOD-9604", sub: nil, abbreviation: "AOD", vial: 5, vialUnit: "mg", water: nil, diluent: "water", provenance: nil, tip: nil, calculatorOnly: true, blend: [], presets: []),
            Compound(key: "cjc1295", name: "CJC-1295", sub: nil, abbreviation: "CJC", vial: 5, vialUnit: "mg", water: nil, diluent: "water", provenance: nil, tip: nil, calculatorOnly: true, blend: [], presets: [])
        ]
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.key, $0) })
    }

    private static func toFixed(_ value: Double, _ digits: Int) -> String {
        guard value.isFinite else { return "—" }
        let negative = value < 0
        let scale = pow(10.0, Double(max(digits, 0)))
        let scaled = jsRound(abs(value) * scale)
        var digitsText = integerString(scaled)
        if digits > 0 {
            if digitsText.count <= digits {
                digitsText = String(repeating: "0", count: digits + 1 - digitsText.count) + digitsText
            }
            let split = digitsText.index(digitsText.endIndex, offsetBy: -digits)
            return (negative ? "-" : "") + digitsText[..<split] + "." + digitsText[split...]
        }
        if digitsText == "0" { return "0" }
        return (negative ? "-" : "") + digitsText
    }

    private static func integerString(_ value: Double) -> String {
        var whole = jsRound(abs(value))
        if !whole.isFinite || whole < 1 { return "0" }
        var characters: [Character] = []
        var guardCount = 0
        while whole >= 1 && guardCount < 24 {
            let next = floor(whole / 10)
            let digit = min(9, max(0, Int(jsRound(whole - next * 10))))
            characters.append(Character(String(digit)))
            whole = next
            guardCount += 1
        }
        return String(characters.reversed())
    }

    private static func group(_ text: String) -> String {
        var body = text
        var negative = false
        if body.hasPrefix("-") {
            negative = true
            body.removeFirst()
        }
        let pieces = body.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let integer = pieces.first ?? ""
        let grouped = insertThousands(integer)
        let sign = negative ? "-" : ""
        if pieces.count > 1 { return sign + grouped + "." + pieces[1] }
        return sign + grouped
    }

    private static func insertThousands(_ integer: String) -> String {
        guard integer.count > 3 else { return integer }
        var result = ""
        for (offset, character) in integer.reversed().enumerated() {
            if offset != 0 && offset % 3 == 0 { result.append(",") }
            result.append(character)
        }
        return String(result.reversed())
    }

    private static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        var year = year
        if month <= 2 { year -= 1 }
        let era = (year >= 0 ? year : year - 399) / 400
        let yearOfEra = year - era * 400
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146097 + dayOfEra - 719468
    }

    private static func civilFromDays(_ zValue: Int) -> (Int, Int, Int) {
        let z = zValue + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let dayOfEra = z - era * 146097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36524 - dayOfEra / 146096) / 365
        let year = yearOfEra + era * 400
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthPart = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * monthPart + 2) / 5 + 1
        let month = monthPart + (monthPart < 10 ? 3 : -9)
        return (year + (month <= 2 ? 1 : 0), month, day)
    }

    private static func isoString(year: Int, month: Int, day: Int) -> String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }
}
