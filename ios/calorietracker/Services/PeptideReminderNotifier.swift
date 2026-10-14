//
//  PeptideReminderNotifier.swift
//  calorietracker
//
//  Local notifications for peptide reminders (the lab draw). Only requests
//  on this phone: no network. Never asks for permission; it schedules only
//  when notifications are already allowed.
//

import Foundation
import UserNotifications

enum PeptideReminderNotifier {
    /// Replaces every pending peptide reminder request with one per reminder
    /// that isn't dismissed and is still ahead (`PeptideReminder.notificationPlans`).
    static func sync(_ reminders: [PeptideReminder], now: Date = Date()) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(PeptideReminderNotificationPlan.idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            break
        default:
            return
        }
        for plan in PeptideReminder.notificationPlans(reminders, now: now) {
            let content = UNMutableNotificationContent()
            content.title = plan.title
            content.body = plan.body
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: plan.fireAt, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: plan.id, content: content, trigger: trigger))
        }
    }
}
