//
//  ProgramV2TemplatePickerView.swift
//  calorietracker
//
//  Program V2 day template selection
//

import SwiftUI

struct ProgramV2TemplatePickerView: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (ProgramV2Day) -> Void
    
    var body: some View {
        NavigationStack {
            List(ProgramV2Templates.allDays) { day in
                Button {
                    onSelect(day)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(day.title)
                            .font(.headline)
                        
                        Text("Conditioning: \(day.conditioning)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        
                        HStack {
                            Label("\(day.exercises.count) exercises", systemImage: "figure.strengthtraining.traditional")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Select Program Day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct ProgramV2DayDetailView: View {
    let day: ProgramV2Day
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Conditioning Section
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "figure.run")
                            .foregroundStyle(.blue)
                        Text("Conditioning (First!)")
                            .font(.headline)
                    }
                    
                    Text(day.conditioning)
                        .font(.subheadline)
                    
                    Text("Minimum if short on time: \(day.conditioningMinimum)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)
                
                // Exercises
                VStack(alignment: .leading, spacing: 12) {
                    Text("Exercises")
                        .font(.headline)
                    
                    ForEach(Array(day.exercises.enumerated()), id: \.element.id) { index, exercise in
                        exerciseCard(exercise, index: index + 1)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(day.title)
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func exerciseCard(_ exercise: ProgramV2Exercise, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(index).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                
                Text(exercise.name)
                    .font(.subheadline.weight(.semibold))
            }
            
            HStack(spacing: 16) {
                Label("\(exercise.sets) sets", systemImage: "repeat")
                Label(exercise.reps, systemImage: "number")
                if let load = exercise.startLoadLb {
                    Label("\(Int(load)) lb", systemImage: "scalemass")
                } else {
                    Label("Select load", systemImage: "questionmark")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            
            Text("RIR: \(exercise.rirTarget)")
                .font(.caption)
                .foregroundStyle(.orange)
            
            let restMin = exercise.restSeconds.lowerBound
            let restMax = exercise.restSeconds.upperBound
            Text("Rest: \(restMin)–\(restMax)s")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            if !exercise.notes.isEmpty {
                Text(exercise.notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }
}
