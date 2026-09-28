import SwiftUI

enum ReconSection: String, CaseIterable, Identifiable {
    case calculator = "Calculator"
    case draw = "Dosing Draw"
    case calendar = "Calendar"
    var id: String { rawValue }
}

enum ReconCalendarView: String, CaseIterable, Identifiable {
    case week = "Week"
    case month = "Month"
    case list = "List"
    var id: String { rawValue }
}

struct ReconView: View {
    @State private var store = ReconBenchStore()
    @State private var section = ReconSection.calculator
    @State private var calculatorKey = ""
    @State private var vialText = ""
    @State private var vialUnit = "mg"
    @State private var waterText = ""
    @State private var doseText = ""
    @State private var doseUnit = "mg"
    @State private var frequencyText = ""
    @State private var reverseText = ""
    @State private var calculatorTipOpen = false
    @State private var drawPerson = "jonathan"
    @State private var openTips: Set<String> = []
    @State private var drafts: [String: String] = [:]
    @State private var calendarPerson = "jonathan"
    @State private var calendarCompound = "tesamorelin"
    @State private var calendarDose = ""
    @State private var calendarDoseUnit = "mg"
    @State private var calendarFrequency = "weekly"
    @State private var calendarWeekdays: Set<Int> = []
    @State private var calendarEveryN = ""
    @State private var calendarStart = Date()
    @State private var calendarWeeks = ""
    @State private var calendarView = ReconCalendarView.week
    @State private var anchor = ReconMath.todayISO()
    @State private var calendarNotice = ""
    @State private var calendarWarning: (level: String, text: String)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sectionPicker
                switch section {
                case .calculator: calculatorPane
                case .draw: drawPane
                case .calendar: calendarPane
                }
                Text(ReconMath.footerText)
                    .font(.system(size: 13))
                    .foregroundStyle(IronTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(IronTheme.canvas)
        .navigationTitle("Recon")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if anchor.isEmpty { anchor = ReconMath.todayISO() }
        }
    }

    private var sectionPicker: some View {
        HStack(spacing: 0) {
            ForEach(ReconSection.allCases) { item in
                Button(item.rawValue) { section = item }
                    .font(.system(size: 13, weight: .heavy))
                    .fontWidth(.condensed)
                    .foregroundStyle(section == item ? IronTheme.textPrimary : IronTheme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(section == item ? IronTheme.blood : IronTheme.surfaceRaised)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: IronTheme.buttonRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: IronTheme.buttonRadius, style: .continuous).stroke(IronTheme.hairline, lineWidth: 1))
    }

    private var calculatorResult: ReconMath.ComputeResult {
        ReconMath.compute(
            vialAmount: ReconMath.toNumber(vialText),
            vialUnit: vialUnit,
            waterML: ReconMath.toNumber(waterText),
            dose: ReconMath.toNumber(doseText),
            doseUnit: doseUnit,
            perWeek: ReconMath.toNumber(frequencyText)
        )
    }

    private var calculatorPane: some View {
        let result = calculatorResult
        let compound = ReconMath.compounds[calculatorKey]
        let blend = ReconMath.calculatorBlend(key: calculatorKey, vialAmount: ReconMath.toNumber(vialText), vialUnit: vialUnit, water: ReconMath.toNumber(waterText), result: result)
        let onHand = store.calculatorOnHand(key: calculatorKey)
        return VStack(alignment: .leading, spacing: 12) {
            fieldLabel("Preset")
            Picker("Preset", selection: $calculatorKey) {
                Text("Custom (no preset)").tag("")
                ForEach(ReconMath.calculatorOrder, id: \.self) { key in
                    if let item = ReconMath.compounds[key] {
                        Text(calculatorPresetTitle(item)).tag(key)
                    }
                }
            }
            .onChange(of: calculatorKey) { _, newValue in
                loadCalculatorPreset(newValue)
            }
            numberField("Vial", text: $vialText)
            unitPicker(selection: $vialUnit, options: ["mcg", "mg", "IU"])
            numberField(compound?.diluent == "saline" ? "Diluent: saline (mL)" : "Bacteriostatic water (mL)", text: $waterText)
            provenanceRow(key: calculatorKey, dose: ReconMath.toNumber(doseText), unit: doseUnit, tipOpen: $calculatorTipOpen)
            numberField("Dose", text: $doseText)
            unitPicker(selection: $doseUnit, options: ["mg", "mcg", "IU"])
            presetMenu(key: calculatorKey) { preset in
                guard let dose = preset.dose, let unit = preset.unit else { return }
                doseText = ReconMath.jsNumber(dose)
                doseUnit = unit
                if let perWeek = preset.perWeek { frequencyText = ReconMath.jsNumber(perWeek) }
            }
            numberField("Injections / week", text: $frequencyText)
            hero(result: result, key: calculatorKey, doseText: doseText, large: true)
            statGrid([
                ("Concentration", finite(result.concentration) ? ReconMath.fmtTrim(result.concentration, 3) + " " + result.concentrationUnit : "—", false),
                ("Per unit", finite(result.perUnit) ? ReconMath.fmtTrim(result.perUnit, 3) + " " + result.perUnitUnit : "—", false),
                ("Volume drawn", result.ok ? ReconMath.fmtML(result.volumeML) + " mL" : "—", false),
                ("Doses per vial", finite(result.dosesPerVial) ? ReconMath.fmtTrim(result.dosesPerVial, 2) : "—", false),
                ("Days per vial", ReconMath.vialDaysText(result: result, perWeek: ReconMath.toNumber(frequencyText)), false),
                ("Days from on-hand", ReconMath.inventorySupplyDaysText(hasCompound: compound != nil, onHand: onHand.value, selectedUnit: vialUnit, catalogUnit: compound?.vialUnit ?? vialUnit, result: result, perWeek: ReconMath.toNumber(frequencyText)), true)
            ])
            Text(ReconMath.calculatorOnHandLine(key: calculatorKey.isEmpty ? nil : calculatorKey, value: onHand.value, source: onHand.source))
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(IronTheme.textSecondary)
            if let breakdown = blend.breakdown {
                Text("Fixed ratio: components CANNOT be dosed independently. Moving the draw moves all three.")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(IronTheme.rust)
                blendTable(breakdown)
            }
            flagList(result.flags + blend.flags)
            reverseRow(result: result)
        }
        .padding(12)
        .modifier(IronCardModifier())
    }

    private var drawPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 0) {
                ForEach(ReconMath.peopleOrder, id: \.self) { person in
                    Button(ReconMath.peopleNames[person] ?? person) { drawPerson = person }
                        .font(.system(size: 15, weight: .heavy))
                        .fontWidth(.condensed)
                        .foregroundStyle(drawPerson == person ? IronTheme.textPrimary : IronTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(drawPerson == person ? IronTheme.blood : IronTheme.surfaceRaised)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: IronTheme.buttonRadius, style: .continuous))
            Button("Reset to presets") {
                store.reset(person: drawPerson)
                drafts = drafts.filter { !$0.key.hasPrefix(drawPerson + "|") }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(IronTheme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(IronTheme.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: IronTheme.buttonRadius, style: .continuous))
            ForEach(ReconMath.roster[drawPerson] ?? [], id: \.self) { key in
                if ReconMath.compounds[key]?.blend.isEmpty == false {
                    blendCard(person: drawPerson, key: key)
                } else {
                    doseCard(person: drawPerson, key: key)
                }
            }
        }
    }

    private func doseCard(person: String, key: String) -> some View {
        let compound = ReconMath.compounds[key]
        let card = store.card(person: person, key: key)
        let result = ReconMath.compute(vialAmount: card.vial, vialUnit: compound?.vialUnit ?? "mg", waterML: card.water ?? .nan, dose: card.dose ?? .nan, doseUnit: card.doseUnit, perWeek: card.perWeek ?? .nan)
        let known = (card.onHand ?? -1) >= 0
        let remaining = ReconMath.dosesRemaining(onHand: card.onHand, vialUnit: compound?.vialUnit ?? "mg", doseN: result.doseN, doseDimension: result.dimension)
        let units = compound?.vialUnit == "IU" ? ["IU", "mg", "mcg"] : ["mg", "mcg", "IU"]
        return VStack(alignment: .leading, spacing: 10) {
            cardHeader(key: key)
            numberField("Vial (\(compound?.vialUnit ?? ""))", text: draftBinding(person: person, key: key, field: "vial", value: card.vial) { value in
                store.updateCard(person: person, key: key) { $0.vial = value ?? 0 }
            })
            numberField(compound?.diluent == "saline" ? "Saline (mL)" : "Water (mL)", text: draftBinding(person: person, key: key, field: "water", value: card.water) { value in
                store.updateCard(person: person, key: key) { $0.water = value }
            })
            if ReconMath.showsCustomDose(key: key, dose: card.dose ?? .nan, unit: card.doseUnit) {
                chip("CUSTOM")
            }
            numberField("Dose", text: draftBinding(person: person, key: key, field: "dose", value: card.dose) { value in
                store.updateCard(person: person, key: key) { $0.dose = value }
            })
            unitPicker(selection: Binding(get: { card.doseUnit }, set: { unit in
                store.updateCard(person: person, key: key) { $0.doseUnit = unit }
            }), options: units)
            presetMenu(key: key) { preset in
                guard let dose = preset.dose, let unit = preset.unit else { return }
                clearDraft(person: person, key: key, fields: ["dose", "perWeek"])
                store.updateCard(person: person, key: key) { card in
                    card.dose = dose
                    card.doseUnit = unit
                    if let perWeek = preset.perWeek { card.perWeek = perWeek }
                }
            }
            numberField("Injections / week", text: draftBinding(person: person, key: key, field: "perWeek", value: card.perWeek) { value in
                store.updateCard(person: person, key: key) { $0.perWeek = value }
            })
            numberField("On hand (\(compound?.vialUnit ?? ""))", text: draftBinding(person: person, key: key, field: "onHand", value: card.onHand) { value in
                store.updateCard(person: person, key: key) { $0.onHand = value }
            })
            Text("Units to draw")
                .font(.system(size: 12, weight: .heavy))
                .fontWidth(.condensed)
                .foregroundStyle(IronTheme.textSecondary)
            hero(result: result, key: key, doseText: card.dose.map(ReconMath.jsNumber) ?? "", large: false)
            statGrid([
                ("Concentration", finite(result.concentration) ? ReconMath.fmtTrim(result.concentration, 3) + " " + result.concentrationUnit : "—", false),
                ("Per unit", finite(result.perUnit) ? ReconMath.fmtTrim(result.perUnit, 3) + " " + result.perUnitUnit : "—", false),
                ("Volume drawn", result.ok ? ReconMath.fmtML(result.volumeML) + " mL" : "—", false),
                ("Doses per vial", finite(result.dosesPerVial) ? ReconMath.fmtTrim(result.dosesPerVial, 2) : "—", false),
                ("On hand", known ? (ReconMath.onHandText(value: card.onHand, key: key) ?? "—") : "set on-hand", true),
                ("Doses remaining", ReconMath.remainingText(known: known, remaining: remaining), true),
                ("Days of supply", ReconMath.supplyDaysText(known: known, remaining: remaining, perWeek: card.perWeek ?? .nan), true),
                ("Frequency", (card.perWeek ?? 0) > 0 ? ReconMath.fmtTrim(card.perWeek ?? .nan, 2) + " / week" : "—", true)
            ])
            flagList(result.flags)
        }
        .padding(12)
        .modifier(IronCardModifier())
    }

    private func blendCard(person: String, key: String) -> some View {
        let compound = ReconMath.compounds[key]
        let card = store.card(person: person, key: key)
        let breakdown = ReconMath.blendBreakdown(blend: compound?.blend ?? [], blendVialNominal: compound?.vial ?? 70, vialAmount: card.vial, waterML: card.water ?? .nan, units: card.draw ?? .nan)
        let known = (card.onHand ?? -1) >= 0
        let amount = breakdown.total?.amountN ?? .nan
        let remaining = ReconMath.dosesRemaining(onHand: card.onHand, vialUnit: "mg", doseN: amount, doseDimension: "mass")
        return VStack(alignment: .leading, spacing: 10) {
            cardHeader(key: key)
            Text("Components CANNOT be dosed independently — moving the draw moves all three.")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(IronTheme.rust)
            numberField("Vial (total blend, mg)", text: draftBinding(person: person, key: key, field: "vial", value: card.vial) { value in
                store.updateCard(person: person, key: key) { $0.vial = value ?? 0 }
            })
            numberField("Water (mL)", text: draftBinding(person: person, key: key, field: "water", value: card.water) { value in
                store.updateCard(person: person, key: key) { $0.water = value }
            })
            numberField("Units drawn (U-100)", text: draftBinding(person: person, key: key, field: "draw", value: card.draw) { value in
                store.updateCard(person: person, key: key) { $0.draw = value }
            })
            numberField("Injections / week", text: draftBinding(person: person, key: key, field: "perWeek", value: card.perWeek) { value in
                store.updateCard(person: person, key: key) { $0.perWeek = value }
            })
            numberField("On hand (total blend, mg)", text: draftBinding(person: person, key: key, field: "onHand", value: card.onHand) { value in
                store.updateCard(person: person, key: key) { $0.onHand = value }
            })
            if breakdown.ok, let check = breakdown.totalCheck, let total = breakdown.total {
                hero(result: check, key: key, doseText: ReconMath.jsNumber(total.amountN), large: false)
                blendTable(breakdown)
                let flags = ReconMath.sortedFlags(check.flags + breakdown.flags)
                statGrid([
                    ("Blend per draw", ReconMath.fmtAmountN(total.amountN, "mass"), false),
                    ("Volume drawn", ReconMath.fmtML(total.volumeML) + " mL", false),
                    ("Doses remaining", ReconMath.remainingText(known: known, remaining: remaining), true),
                    ("Days of supply", ReconMath.supplyDaysText(known: known, remaining: remaining, perWeek: card.perWeek ?? .nan), true)
                ])
                flagList(flags)
            } else {
                let error = (card.water ?? 0) > 0 ? "NEED_DOSE" : "NEED_WATER"
                hero(result: ReconMath.ComputeResult(error: error), key: key, doseText: "", large: false)
                statGrid([("Doses remaining", known ? "—" : "set on-hand", true)])
            }
        }
        .padding(12)
        .modifier(IronCardModifier())
    }

    private var calendarPane: some View {
        let simulation = ReconMath.simulateSupply(entries: store.entries, config: { store.config(person: $0, key: $1) }, onHand: { store.onHand(person: $0, key: $1) })
        return VStack(alignment: .leading, spacing: 12) {
            calendarForm()
            if !calendarNotice.isEmpty {
                banner(calendarNotice, level: "info")
            }
            if let calendarWarning {
                banner(calendarWarning.text, level: calendarWarning.level)
            }
            ForEach(ReconMath.supplyLines(entries: store.entries, simulation: simulation, config: { store.config(person: $0, key: $1) }, onHand: { store.onHand(person: $0, key: $1) })) { line in
                banner(line.text, level: line.level.isEmpty ? "info" : line.level)
            }
            if let notice = store.syncNotice, store.bridgeSyncEnabled {
                banner(notice, level: "amber")
            }
            HStack(spacing: 0) {
                ForEach(ReconCalendarView.allCases) { item in
                    Button(item.rawValue) { calendarView = item }
                        .font(.system(size: 13, weight: .heavy))
                        .fontWidth(.condensed)
                        .foregroundStyle(calendarView == item ? IronTheme.textPrimary : IronTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(calendarView == item ? IronTheme.blood : IronTheme.surfaceRaised)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: IronTheme.buttonRadius, style: .continuous))
            HStack {
                Button("←") { anchor = ReconMath.shiftAnchor(anchor, view: calendarView.rawValue.lowercased(), direction: -1) }
                Button("Today") { anchor = ReconMath.todayISO() }
                Button("→") { anchor = ReconMath.shiftAnchor(anchor, view: calendarView.rawValue.lowercased(), direction: 1) }
            }
            .font(.system(size: 15, weight: .semibold, design: .monospaced))
            .foregroundStyle(IronTheme.textPrimary)
            Text(calendarLabel)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(IronTheme.brass)
            Text("Tap a dose to log it as taken. Units are computed live from each person's current vial and water settings on the Dosing Draw tab.")
                .font(.system(size: 13))
                .foregroundStyle(IronTheme.textSecondary)
            calendarGrid(simulation)
            entryList(simulation)
            Toggle(isOn: Binding(get: { store.bridgeSyncEnabled }, set: { store.bridgeSyncEnabled = $0 })) {
                Text("Sync taken doses to the bridge")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(IronTheme.textPrimary)
            }
            .tint(IronTheme.blood)
            Text("Off by default. Taken doses stay on this phone until this is on.")
                .font(.system(size: 12))
                .foregroundStyle(IronTheme.textSecondary)
        }
        .padding(12)
        .modifier(IronCardModifier())
    }

    private func calendarForm() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldLabel("Add schedule entry")
            Picker("Person", selection: $calendarPerson) {
                Text("Jonathan").tag("jonathan")
                Text("Victoria").tag("victoria")
            }
            .onChange(of: calendarPerson) { _, _ in
                let keys = ReconMath.roster[calendarPerson] ?? []
                if !keys.contains(calendarCompound) { calendarCompound = keys.first ?? "" }
                syncCalendarUnits()
            }
            Picker("Compound", selection: $calendarCompound) {
                ForEach(ReconMath.roster[calendarPerson] ?? [], id: \.self) { key in
                    Text(ReconMath.compounds[key]?.name ?? key).tag(key)
                }
            }
            .onChange(of: calendarCompound) { _, _ in syncCalendarUnits() }
            let blend = ReconMath.compounds[calendarCompound]?.blend.isEmpty == false
            numberField(blend ? "Units drawn (U-100)" : "Dose", text: $calendarDose)
            if !blend {
                unitPicker(selection: $calendarDoseUnit, options: ReconMath.compounds[calendarCompound]?.vialUnit == "IU" ? ["IU"] : ["mg", "mcg"])
            }
            Picker("Frequency", selection: $calendarFrequency) {
                Text("Daily").tag("daily")
                Text("Specific weekdays").tag("weekdays")
                Text("Weekly").tag("weekly")
                Text("Every N days").tag("everyN")
            }
            if calendarFrequency == "weekdays" {
                weekdayPicker
            }
            if calendarFrequency == "everyN" {
                numberField("Every N days", text: $calendarEveryN)
            }
            DatePicker("Start date", selection: $calendarStart, displayedComponents: .date)
                .foregroundStyle(IronTheme.textPrimary)
            numberField("Duration (weeks)", text: $calendarWeeks)
            if let preview = calendarPreview {
                Text(preview)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(IronTheme.textSecondary)
            }
            Button("Add entry") { addCalendarEntry() }
                .font(.system(size: 15, weight: .heavy))
                .fontWidth(.condensed)
                .foregroundStyle(IronTheme.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(IronTheme.blood)
                .clipShape(RoundedRectangle(cornerRadius: IronTheme.buttonRadius, style: .continuous))
        }
    }

    private var weekdayPicker: some View {
        let order = [1, 2, 3, 4, 5, 6, 0]
        return HStack {
            ForEach(order, id: \.self) { day in
                Button(ReconMath.weekdayShort[day]) {
                    if calendarWeekdays.contains(day) { calendarWeekdays.remove(day) } else { calendarWeekdays.insert(day) }
                }
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(calendarWeekdays.contains(day) ? IronTheme.textPrimary : IronTheme.textSecondary)
                .padding(6)
                .background(calendarWeekdays.contains(day) ? IronTheme.blood : IronTheme.surfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: IronTheme.buttonRadius, style: .continuous))
            }
        }
    }

    private var calendarPreview: String? {
        let amount = ReconMath.toNumber(calendarDose)
        guard amount > 0, let compound = ReconMath.compounds[calendarCompound] else { return nil }
        let entry = draftEntry(id: "preview")
        let info = ReconMath.entryDoseInfo(entry: entry, config: store.config(person: calendarPerson, key: calendarCompound))
        if !compound.blend.isEmpty {
            let parts = (info.components ?? []).map { $0.name + " " + ReconMath.fmtAmountN($0.deliveredN, "mass") }.joined(separator: " · ")
            return "Draw \(ReconMath.fmtUnits(entry.draw ?? .nan)) units → \(parts)"
        }
        let person = ReconMath.peopleNames[calendarPerson] ?? calendarPerson
        let units = info.ok ? info.unitsText + " units" : ReconMath.whyText(info.error)
        var text = "Units at current \(person) vial/water: \(units)"
        if calendarCompound == "retatrutide" && calendarErrors().isEmpty {
            let previewEntry = draftEntry(id: "preview")
            let simulation = ReconMath.simulateSupply(
                entries: store.entries + [previewEntry],
                config: { store.config(person: $0, key: $1) },
                onHand: { store.onHand(person: $0, key: $1) }
            )
            let message = ReconMath.coverageMessage(
                entry: previewEntry,
                config: store.config(person: calendarPerson, key: calendarCompound),
                onHand: store.onHand(person: calendarPerson, key: calendarCompound),
                simulation: simulation
            )
            text += "\nPreview — " + message.text
        }
        return text
    }

    private func addCalendarEntry() {
        let errors = calendarErrors()
        if !errors.isEmpty {
            calendarNotice = ""
            calendarWarning = ("red", errors.joined(separator: " "))
            return
        }
        let entry = draftEntry(id: "e" + UUID().uuidString.prefix(10).description)
        store.add(entry)
        anchor = entry.start
        let compound = ReconMath.compounds[entry.compound]
        let person = ReconMath.peopleNames[entry.person] ?? entry.person
        calendarNotice = "Added: \(person) · \(compound?.name ?? entry.compound) · \(ReconMath.frequencyText(entry.freq)) from \(ReconMath.formatDate(entry.start)) for \(ReconMath.fmtTrim(entry.weeks, 2)) weeks."
        if entry.compound == "retatrutide" {
            let simulation = ReconMath.simulateSupply(entries: store.entries, config: { store.config(person: $0, key: $1) }, onHand: { store.onHand(person: $0, key: $1) })
            let message = ReconMath.coverageMessage(entry: entry, config: store.config(person: entry.person, key: entry.compound), onHand: store.onHand(person: entry.person, key: entry.compound), simulation: simulation)
            calendarWarning = message
        } else {
            calendarWarning = nil
        }
    }

    private func calendarErrors() -> [String] {
        var errors: [String] = []
        let compound = ReconMath.compounds[calendarCompound]
        let amount = ReconMath.toNumber(calendarDose)
        if compound?.blend.isEmpty == false {
            if !(amount > 0) { errors.append("Enter units drawn.") }
        } else if !(amount > 0) {
            errors.append("Enter a dose.")
        }
        if calendarFrequency == "weekdays" && calendarWeekdays.isEmpty {
            errors.append("Pick at least one weekday.")
        }
        if calendarFrequency == "everyN" {
            let interval = ReconMath.toNumber(calendarEveryN)
            if !(interval >= 1) || floor(interval) != interval { errors.append("Every N days needs a whole number ≥ 1.") }
        }
        if ReconMath.parseISO(ReconMath.todayISO(now: calendarStart)) == nil {
            errors.append("Pick a start date.")
        }
        if !(ReconMath.toNumber(calendarWeeks) > 0) { errors.append("Enter duration in weeks.") }
        return errors
    }

    private func draftEntry(id: String) -> ReconMath.ScheduleEntry {
        let blend = ReconMath.compounds[calendarCompound]?.blend.isEmpty == false
        let amount = ReconMath.toNumber(calendarDose)
        var frequency = ReconMath.Frequency(type: calendarFrequency)
        if calendarFrequency == "weekdays" { frequency.days = calendarWeekdays.sorted() }
        if calendarFrequency == "everyN" { frequency.n = ReconMath.toNumber(calendarEveryN) }
        return ReconMath.ScheduleEntry(
            id: id,
            person: calendarPerson,
            compound: calendarCompound,
            dose: blend ? nil : amount,
            doseUnit: blend ? nil : calendarDoseUnit,
            draw: blend ? amount : nil,
            freq: frequency,
            start: ReconMath.todayISO(now: calendarStart),
            weeks: ReconMath.toNumber(calendarWeeks)
        )
    }

    private var calendarLabel: String {
        if store.entries.isEmpty { return "" }
        switch calendarView {
        case .list: return "All doses"
        case .week: return ReconMath.weekDays(anchor: anchor).label
        case .month: return ReconMath.monthDays(anchor: anchor).label
        }
    }

    @ViewBuilder
    private func calendarGrid(_ simulation: ReconMath.SupplySimulation) -> some View {
        if store.entries.isEmpty {
            Text("No schedule entries. The calendar ships empty — add entries above.")
                .font(.system(size: 15))
                .foregroundStyle(IronTheme.textSecondary)
        } else if calendarView == .list {
            let grouped = Dictionary(grouping: simulation.occurrences, by: \.date)
            ForEach(grouped.keys.sorted(), id: \.self) { date in
                VStack(alignment: .leading, spacing: 6) {
                    Text(ReconMath.formatDate(date))
                        .font(.system(size: 13, weight: .heavy))
                        .fontWidth(.condensed)
                        .foregroundStyle(IronTheme.textSecondary)
                    ForEach(grouped[date] ?? []) { occurrence in
                        occurrenceButton(occurrence)
                    }
                }
            }
        } else if calendarView == .week {
            let days = ReconMath.weekDays(anchor: anchor).days
            ForEach(days, id: \.self) { day in
                dayColumn(day, occurrences: simulation.occurrences.filter { $0.date == day }, inMonth: true)
            }
        } else {
            let days = ReconMath.monthDays(anchor: anchor).days
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                dayColumn(day.iso, occurrences: simulation.occurrences.filter { $0.date == day.iso }, inMonth: day.inMonth)
            }
        }
    }

    private func dayColumn(_ iso: String, occurrences: [ReconMath.Occurrence], inMonth: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(calendarView == .week ? ReconMath.formatDateShort(iso) : String(ReconMath.parseISO(iso)?.day ?? 0))
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(iso == ReconMath.todayISO() ? IronTheme.brass : (inMonth ? IronTheme.textSecondary : IronTheme.textTertiary))
            ForEach(occurrences) { occurrence in
                occurrenceButton(occurrence)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func occurrenceButton(_ occurrence: ReconMath.Occurrence) -> some View {
        let compound = ReconMath.compounds[occurrence.entry.compound]
        let taken = store.isTaken(occurrence)
        let person = ReconMath.peopleNames[occurrence.entry.person] ?? occurrence.entry.person
        return Button {
            store.toggleTaken(occurrence)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(person.prefix(1)) · \(compound?.abbreviation ?? compound?.name ?? "") · D\(occurrence.dayNumber)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                Text("\(occurrence.info.doseText) · \(occurrence.info.unitsText == "—" ? "units —" : occurrence.info.unitsText + " u")")
                    .font(.system(size: 12, design: .monospaced))
                    .monospacedDigit()
                if let components = occurrence.info.components, !components.isEmpty {
                    Text(components.map { $0.name + " " + ReconMath.fmtAmountN($0.deliveredN, "mass") }.joined(separator: " · "))
                        .font(.system(size: 11, design: .monospaced))
                }
                if !occurrence.flags.isEmpty {
                    Text("! " + occurrence.flags.joined(separator: "; "))
                        .font(.system(size: 11))
                }
                if taken {
                    Text("taken")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(IronTheme.olive)
                }
            }
            .foregroundStyle(occurrence.status == "short" ? IronTheme.bloodText : IronTheme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(taken ? IronTheme.surfaceRaised : IronTheme.surface)
            .overlay(RoundedRectangle(cornerRadius: IronTheme.cardRadius, style: .continuous).stroke(occurrence.duplicate ? IronTheme.rust : IronTheme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(taken ? "Taken — tap to undo" : "Tap to log as taken")
    }

    private func entryList(_ simulation: ReconMath.SupplySimulation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !store.entries.isEmpty {
                fieldLabel("Entries (\(store.entries.count))")
            }
            ForEach(store.entries) { entry in
                let info = ReconMath.entryDoseInfo(entry: entry, config: store.config(person: entry.person, key: entry.compound))
                let count = ReconMath.expandEntry(entry).count
                let compound = ReconMath.compounds[entry.compound]
                let dose = compound?.blend.isEmpty == false ? ReconMath.fmtUnits(entry.draw ?? .nan) + " unit draw" : ReconMath.fmtTrim(entry.dose ?? .nan, 3) + " " + (entry.doseUnit ?? "")
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(ReconMath.peopleNames[entry.person] ?? entry.person) · \(compound?.name ?? entry.compound)")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(IronTheme.textPrimary)
                        Text("\(dose) → \(info.ok ? info.unitsText + " units" : "units —") · \(ReconMath.frequencyText(entry.freq)) · from \(ReconMath.formatDate(entry.start)) · \(ReconMath.fmtTrim(entry.weeks, 2)) wk · \(count) \(count == 1 ? "dose" : "doses")")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(IronTheme.textSecondary)
                            .monospacedDigit()
                    }
                    Spacer()
                    Button("Delete") { store.delete(id: entry.id) }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(IronTheme.bloodText)
                }
                _ = simulation
            }
        }
    }

    private func loadCalculatorPreset(_ key: String) {
        calculatorTipOpen = false
        reverseText = ""
        frequencyText = ""
        guard let compound = ReconMath.compounds[key] else {
            return
        }
        vialText = ReconMath.jsNumber(compound.vial)
        vialUnit = compound.vialUnit
        waterText = compound.water.map(ReconMath.jsNumber) ?? ""
        if let preset = ReconMath.defaultPreset(for: key), let draw = preset.draw {
            doseText = ReconMath.blendDoseField(vial: compound.vial, vialUnit: compound.vialUnit, water: compound.water ?? .nan, draw: draw)
            doseUnit = "mg"
            reverseText = ReconMath.jsNumber(draw)
        } else if let preset = ReconMath.defaultPreset(for: key), let dose = preset.dose, let unit = preset.unit {
            doseText = ReconMath.jsNumber(dose)
            doseUnit = unit
            if let perWeek = preset.perWeek { frequencyText = ReconMath.jsNumber(perWeek) }
        } else {
            doseText = ""
            doseUnit = compound.vialUnit == "IU" ? "IU" : "mg"
        }
    }

    private func calculatorPresetTitle(_ compound: ReconMath.Compound) -> String {
        let name = compound.name + (compound.sub.map { " (\($0))" } ?? "")
        return name + " · " + ReconMath.fmtTrim(compound.vial, 3) + " " + compound.vialUnit
    }

    private func syncCalendarUnits() {
        let compound = ReconMath.compounds[calendarCompound]
        if compound?.vialUnit == "IU" { calendarDoseUnit = "IU" }
        else if calendarDoseUnit == "IU" { calendarDoseUnit = "mg" }
    }

    private func cardHeader(key: String) -> some View {
        let compound = ReconMath.compounds[key]
        return VStack(alignment: .leading, spacing: 4) {
            Text(compound?.name ?? key)
                .font(.system(size: 20, weight: .black))
                .fontWidth(.condensed)
                .foregroundStyle(IronTheme.textPrimary)
            Text(((compound?.sub).map { $0 + " · " } ?? "") + ReconMath.fmtTrim(compound?.vial ?? .nan, 3) + " " + (compound?.vialUnit ?? "") + " vial" + (compound?.diluent == "saline" ? " · saline" : ""))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(IronTheme.textSecondary)
            provenanceRow(key: key, dose: .nan, unit: "", tipOpen: tipBinding(person: drawPerson, key: key), showCustom: false)
        }
    }

    private func provenanceRow(key: String, dose: Double, unit: String, tipOpen: Binding<Bool>, showCustom: Bool = true) -> some View {
        let compound = ReconMath.compounds[key]
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let provenance = compound?.provenance {
                    chip(provenance)
                } else if compound != nil {
                    chip("NO PRESET")
                }
                if showCustom && ReconMath.showsCustomDose(key: key, dose: dose, unit: unit) {
                    chip("CUSTOM")
                }
                if let tip = compound?.tip, !tip.isEmpty {
                    Button("i") { tipOpen.wrappedValue.toggle() }
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(tipOpen.wrappedValue ? IronTheme.canvas : IronTheme.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(tipOpen.wrappedValue ? IronTheme.textPrimary : IronTheme.surfaceRaised)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(IronTheme.hairline, lineWidth: 1))
                        .accessibilityLabel("About this default")
                }
            }
            if tipOpen.wrappedValue, let compound, let tip = compound.tip {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tip)
                        .font(.system(size: 13))
                        .foregroundStyle(IronTheme.textPrimary)
                    Text("Operator-supplied note · " + (compound.provenance.map { $0 + " = " + (ReconMath.provenanceDescription[$0] ?? "") } ?? ""))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(IronTheme.textTertiary)
                }
                .padding(8)
                .background(IronTheme.surfaceRaised)
                .overlay(alignment: .leading) { Rectangle().fill(IronTheme.hairline).frame(width: 3) }
            }
        }
    }

    private func chip(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundStyle(chipColor(label))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(chipColor(label), style: StrokeStyle(lineWidth: 1, dash: label == "CUSTOM" || label == "NO PRESET" ? [3, 2] : [])))
            .accessibilityLabel(ReconMath.provenanceDescription[label] ?? label)
    }

    private func chipColor(_ label: String) -> Color {
        switch label {
        case "LABEL": return IronTheme.olive
        case "TRIAL": return IronTheme.textPrimary
        case "USER": return IronTheme.textSecondary
        case "NONE": return IronTheme.rust
        default: return IronTheme.textSecondary
        }
    }

    private func hero(result: ReconMath.ComputeResult, key: String, doseText: String, large: Bool) -> some View {
        let compound = ReconMath.compounds[key]
        return Group {
            if result.ok {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(ReconMath.fmtUnits(result.units))
                        .font(.system(size: large ? 64 : 40, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(heroColor(ReconMath.worstLevel(result.flags)))
                    Text("units")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(IronTheme.textSecondary)
                }
            } else if compound?.provenance == "NONE" && !(ReconMath.toNumber(doseText) > 0), let tip = compound?.tip {
                VStack(alignment: .leading, spacing: 6) {
                    chip("NONE")
                    Text(tip)
                        .font(.system(size: 14))
                        .foregroundStyle(IronTheme.textPrimary)
                }
                .padding(10)
                .overlay(RoundedRectangle(cornerRadius: IronTheme.cardRadius).stroke(IronTheme.rust, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("—")
                        .font(.system(size: large ? 64 : 40, weight: .bold, design: .monospaced))
                        .foregroundStyle(IronTheme.textTertiary)
                    Text(ReconMath.whyText(result.error))
                        .font(.system(size: 14))
                        .foregroundStyle(IronTheme.textSecondary)
                }
            }
        }
    }

    private func heroColor(_ level: String?) -> Color {
        switch level {
        case "red": return IronTheme.bloodText
        case "amber": return IronTheme.rust
        default: return IronTheme.brass
        }
    }

    private func flagList(_ flags: [ReconMath.Flag]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(ReconMath.sortedFlags(flags)) { flag in
                HStack(alignment: .top, spacing: 8) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(flagColor(flag.level))
                        .frame(width: 9, height: 9)
                        .padding(.top, 4)
                    Text(flag.text)
                        .font(.system(size: 13))
                        .foregroundStyle(IronTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(IronTheme.surfaceRaised)
                .overlay(RoundedRectangle(cornerRadius: IronTheme.buttonRadius).stroke(flagColor(flag.level), lineWidth: 1))
            }
        }
    }

    private func flagColor(_ level: String) -> Color {
        switch level {
        case "red": return IronTheme.bloodText
        case "amber": return IronTheme.rust
        case "green": return IronTheme.olive
        default: return IronTheme.textSecondary
        }
    }

    private func statGrid(_ rows: [(String, String, Bool)]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.0)
                        .font(.system(size: 11, weight: .heavy))
                        .fontWidth(.condensed)
                        .foregroundStyle(IronTheme.textSecondary)
                    Text(row.1)
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(statColor(row.1, plain: row.2))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func statColor(_ text: String, plain: Bool) -> Color {
        if text == "—" || text.hasPrefix("set ") { return IronTheme.textTertiary }
        return plain ? IronTheme.textPrimary : IronTheme.brass
    }

    private func blendTable(_ breakdown: ReconMath.BlendResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(breakdown.components) { component in
                VStack(alignment: .leading, spacing: 2) {
                    Text(component.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(component.over ? IronTheme.bloodText : IronTheme.textPrimary)
                    Text("In vial \(ReconMath.fmtTrim(component.vialAmount, 3)) \(component.unit)")
                        .font(.system(size: 12, design: .monospaced)).monospacedDigit()
                    Text("Conc. \(ReconMath.fmtTrim(component.concentration, 3)) \(component.concentrationUnit)")
                        .font(.system(size: 12, design: .monospaced)).monospacedDigit()
                    Text("Per unit \(ReconMath.fmtTrim(component.perUnit, 3)) \(component.perUnitUnit)")
                        .font(.system(size: 12, design: .monospaced)).monospacedDigit()
                    Text("Delivered \(ReconMath.fmtAmountN(component.deliveredN, "mass"))")
                        .font(.system(size: 12, weight: .bold, design: .monospaced)).monospacedDigit()
                        .foregroundStyle(component.over ? IronTheme.bloodText : IronTheme.brass)
                }
                .foregroundStyle(IronTheme.textSecondary)
            }
        }
    }

    private func reverseRow(result: ReconMath.ComputeResult) -> some View {
        let reversed = ReconMath.reverseCompute(vialAmount: ReconMath.toNumber(vialText), vialUnit: vialUnit, waterML: ReconMath.toNumber(waterText), units: ReconMath.toNumber(reverseText))
        let match = ReconMath.reverseMatchText(reverse: reversed, result: result, unitsText: ReconMath.fmtTrim(result.units, 2))
        return VStack(alignment: .leading, spacing: 6) {
            Text("If I draw")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(IronTheme.textSecondary)
            numberField("units", text: $reverseText)
            Text(ReconMath.toNumber(reverseText) >= 0 && reversed.ok ? ReconMath.reverseCheckText(reverse: reversed, doseUnit: doseUnit) : "—")
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(IronTheme.brass)
            if !match.text.isEmpty {
                Text(match.text)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(match.matched ? IronTheme.olive : IronTheme.bloodText)
            }
        }
    }

    private func banner(_ text: String, level: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(IronTheme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(IronTheme.surfaceRaised)
            .overlay(RoundedRectangle(cornerRadius: IronTheme.cardRadius).stroke(level == "red" ? IronTheme.bloodText : (level == "info" ? IronTheme.hairline : IronTheme.rust), lineWidth: 1))
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .heavy))
            .fontWidth(.condensed)
            .tracking(0.6)
            .foregroundStyle(IronTheme.textSecondary)
    }

    private func numberField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            fieldLabel(title)
            TextField(title, text: text)
                .keyboardType(.decimalPad)
                .font(.system(size: 18, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(IronTheme.textPrimary)
                .padding(10)
                .background(IronTheme.surfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: IronTheme.buttonRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: IronTheme.buttonRadius, style: .continuous).stroke(IronTheme.hairline, lineWidth: 1))
        }
    }

    private func unitPicker(selection: Binding<String>, options: [String]) -> some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                Button(option) { selection.wrappedValue = option }
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(selection.wrappedValue == option ? IronTheme.textPrimary : IronTheme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(selection.wrappedValue == option ? IronTheme.blood : IronTheme.surfaceRaised)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: IronTheme.buttonRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: IronTheme.buttonRadius, style: .continuous).stroke(IronTheme.hairline, lineWidth: 1))
    }

    private func presetMenu(key: String, apply: @escaping (ReconMath.Preset) -> Void) -> some View {
        let presets = (ReconMath.compounds[key]?.presets ?? []).filter { $0.dose != nil }
        return VStack(alignment: .leading, spacing: 4) {
            fieldLabel("Dose preset")
            if presets.isEmpty {
                Text("No preset dose supplied")
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(IronTheme.textTertiary)
            } else {
                Menu("Choose a preset…") {
                    ForEach(presets) { preset in
                        Button(ReconMath.presetLabel(preset)) { apply(preset) }
                    }
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(IronTheme.textPrimary)
            }
        }
    }

    private func draftBinding(person: String, key: String, field: String, value: Double?, commit: @escaping (Double?) -> Void) -> Binding<String> {
        let id = person + "|" + key + "|" + field
        return Binding(
            get: { drafts[id] ?? value.map(ReconMath.jsNumber) ?? "" },
            set: { text in
                drafts[id] = text
                let parsed = ReconMath.toNumber(text)
                commit(parsed.isFinite ? parsed : nil)
            }
        )
    }

    private func clearDraft(person: String, key: String, fields: [String]) {
        for field in fields {
            drafts[person + "|" + key + "|" + field] = nil
        }
    }

    private func tipBinding(person: String, key: String) -> Binding<Bool> {
        let id = person + "|" + key
        return Binding(get: { openTips.contains(id) }, set: { open in
            if open { openTips.insert(id) } else { openTips.remove(id) }
        })
    }

    private func finite(_ value: Double) -> Bool { value.isFinite }
}
