//
//  RestTimerService.swift
//  calorietracker
//
//  Rest timer with audio cues (boxing clack at 10s, bell at 0)
//

import Foundation
import UIKit
import AVFoundation
import UserNotifications

@Observable
final class RestTimerService: NSObject {
    var remainingSeconds: Int = 0
    var totalSeconds: Int = 90
    var isRunning = false
    var isPaused = false
    
    private var timer: Timer?
    private var audioPlayer: AVAudioPlayer?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private let notificationCenter = UNUserNotificationCenter.current()
    
    override init() {
        super.init()
        configureAudioSession()
    }
    
    // MARK: - Audio Session Configuration
    
    private func configureAudioSession() {
        do {
            // .ambient + .mixWithOthers: play over music without pausing it
            try AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
        }
    }
    
    // MARK: - Timer Control
    
    func start(seconds: Int) {
        stop()
        totalSeconds = seconds
        remainingSeconds = seconds
        isRunning = true
        isPaused = false
        
        // Request notification permission if needed
        requestNotificationPermission()
        
        // Schedule background notification
        scheduleBackgroundNotification()
        
        // Start foreground timer
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        
        // Keep running in background
        beginBackgroundTask()
    }
    
    func pause() {
        guard isRunning else { return }
        isPaused = true
        isRunning = false
        timer?.invalidate()
        timer = nil
        cancelBackgroundNotification()
        endBackgroundTask()
    }
    
    func resume() {
        guard isPaused else { return }
        isPaused = false
        isRunning = true
        
        scheduleBackgroundNotification()
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        
        beginBackgroundTask()
    }
    
    func stop() {
        isRunning = false
        isPaused = false
        remainingSeconds = 0
        timer?.invalidate()
        timer = nil
        cancelBackgroundNotification()
        endBackgroundTask()
    }
    
    func reset(to seconds: Int) {
        let wasRunning = isRunning
        stop()
        totalSeconds = seconds
        if wasRunning {
            start(seconds: seconds)
        }
    }
    
    // MARK: - Timer Tick
    
    private func tick() {
        guard remainingSeconds > 0 else {
            playCompletionSound()
            stop()
            return
        }
        
        remainingSeconds -= 1
        
        if remainingSeconds == 10 {
            playWarningSound()
        } else if remainingSeconds == 0 {
            playCompletionSound()
            stop()
        }
    }
    
    // MARK: - Audio Playback
    
    private func playWarningSound() {
        playSound(named: "boxing_clack")
    }
    
    private func playCompletionSound() {
        playSound(named: "gym_bell")
    }
    
    private func playSound(named name: String) {
        // Try to find sound in bundle
        guard let url = Bundle.main.url(forResource: name, withExtension: "mp3") ??
                        Bundle.main.url(forResource: name, withExtension: "wav") ??
                        Bundle.main.url(forResource: name, withExtension: "m4a") else {
            print("Sound file not found: \(name)")
            return
        }
        
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
        } catch {
            print("Failed to play sound: \(error)")
        }
    }
    
    // MARK: - Background Support
    
    private func beginBackgroundTask() {
        backgroundTaskID = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackgroundTask()
        }
    }
    
    private func endBackgroundTask() {
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
    }
    
    // MARK: - Notifications
    
    private func requestNotificationPermission() {
        notificationCenter.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
        }
    }
    
    private func scheduleBackgroundNotification() {
        cancelBackgroundNotification()
        
        let content = UNMutableNotificationContent()
        content.title = "Rest Timer Complete"
        content.body = "Time to start your next set!"
        content.sound = .default
        content.categoryIdentifier = "REST_TIMER"
        
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(remainingSeconds),
            repeats: false
        )
        
        let request = UNNotificationRequest(
            identifier: "rest_timer_completion",
            content: content,
            trigger: trigger
        )
        
        notificationCenter.add(request) { error in
            if let error = error {
                print("Failed to schedule notification: \(error)")
            }
        }
    }
    
    private func cancelBackgroundNotification() {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: ["rest_timer_completion"])
    }
    
    // MARK: - Time Formatting
    
    var formattedTime: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var progressFraction: Double {
        guard totalSeconds > 0 else { return 0 }
        return Double(totalSeconds - remainingSeconds) / Double(totalSeconds)
    }
}
