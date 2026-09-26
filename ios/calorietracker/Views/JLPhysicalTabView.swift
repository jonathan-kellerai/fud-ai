//
//  JLPhysicalTabView.swift
//  calorietracker
//
//  JL Physical features integration
//

import SwiftUI

struct JLPhysicalTabView: View {
    @State private var selection = 0
    
    var body: some View {
        TabView(selection: $selection) {
            StepsView()
                .tabItem {
                    Label("Steps", systemImage: "figure.walk")
                }
                .tag(0)
            
            NavigationView {
                BridgeSettingsView()
            }
            .tabItem {
                Label("Bridge", systemImage: "server.rack")
            }
            .tag(1)
        }
    }
}

struct ProgramV2NavigationLink: View {
    @State private var showingTemplatePicker = false
    @State private var showingDayDetail: ProgramV2Day?
    
    var body: some View {
        Button {
            showingTemplatePicker = true
        } label: {
            HStack {
                Image(systemName: "list.bullet.rectangle")
                Text("Program V2 Templates")
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showingTemplatePicker) {
            ProgramV2TemplatePickerView { day in
                showingDayDetail = day
            }
        }
        .sheet(item: $showingDayDetail) { day in
            NavigationView {
                ProgramV2DayDetailView(day: day)
            }
        }
    }
}
