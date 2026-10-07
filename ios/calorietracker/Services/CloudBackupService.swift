import CloudKit
import Foundation
import Observation
import os

/// What a store gives the iCloud backup: its bytes, or why it can't give them.
enum CloudBackupPart: Equatable {
    case include(Data)
    /// The store's data couldn't be read in full here (or packed), so the
    /// backup can't carry it and a restore can't replace it. `reason` is a
    /// clause, e.g. "Peptides couldn't be read on this phone".
    case blocked(reason: String)

    var data: Data? {
        if case .include(let data) = self { data } else { nil }
    }
}

/// Peptides live in their own file, not UserDefaults. The backup carries
/// them as one peptides archive (the same format as export/import).
@MainActor
protocol CloudBackupPeptides: AnyObject {
    func backupArchiveData() -> CloudBackupPart
    /// Validates before replacing anything. An error message, or nil when restored.
    func restoreArchiveData(_ data: Data) -> String?
}

/// Workouts live in their own file on this phone. The backup carries the
/// whole workout log (the saved file's format).
@MainActor
protocol CloudBackupWorkouts: AnyObject {
    func backupData() -> CloudBackupPart
    /// Validates before replacing anything. An error message, or nil when restored.
    func restoreBackupData(_ data: Data) -> String?
}

@Observable
final class CloudBackupService {
    static let enabledKey = "cloudBackupEnabled"
    static let lastAtKey = "cloudBackupLastAt"
    static let lastHashKey = "cloudBackupLastHash"
    /// Backup value holding the peptides archive. Never a UserDefaults key.
    static let peptidesKey = "peptides.archive.v1"
    /// Backup value holding the workout log. Never a UserDefaults key.
    static let workoutsKey = "workouts.log.v1"
    static let smokeTestLaunchArgument = "-fudai.cloudBackup.smokeTest"
    static let smokeTestRecordName = "smoke-test"

    private static var didRunSmokeTestThisLaunch = false
    private static let smokeLogger = Logger(subsystem: "com.apoorvdarshan.calorietracker", category: "CloudBackupSmoke")

    private let recordType = "FudAIBackup"
    private let recordName = "current"
    private let assetField = "backupAsset"
    private let shaField = "contentSha256"

    var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: Self.enabledKey) }
    }
    var lastAt: String?
    var busy = false
    var hasCloudBackup = false
    var errorMessage: String?

    private let defaults: UserDefaults
    @ObservationIgnored private let peptides: (any CloudBackupPeptides)?
    @ObservationIgnored private let workouts: (any CloudBackupWorkouts)?
    private var container: CKContainer { CKContainer.default() }

    init(
        defaults: UserDefaults = .standard,
        peptides: (any CloudBackupPeptides)? = nil,
        workouts: (any CloudBackupWorkouts)? = nil
    ) {
        self.defaults = defaults
        self.peptides = peptides
        self.workouts = workouts
        self.enabled = defaults.bool(forKey: Self.enabledKey)
        self.lastAt = defaults.string(forKey: Self.lastAtKey)
    }

    /// Everything a backup uploads. Throws `.backupSkipped` when peptides or
    /// workouts can't be backed up: the upload replaces the last iCloud
    /// backup, so one without them would drop the copy it holds.
    func snapshotValues() throws -> [String: CloudBackupValue] {
        var out: [String: CloudBackupValue] = [:]
        for (key, raw) in defaults.dictionaryRepresentation() {
            guard CloudBackupPolicy.include(key) else { continue }
            if let data = raw as? Data {
                out[key] = .data(data)
            } else if let strings = raw as? [String] {
                out[key] = .stringArray(strings)
            } else if let string = raw as? String {
                out[key] = .string(string)
            } else if let number = raw as? NSNumber {
                if CFGetTypeID(number) == CFBooleanGetTypeID() {
                    out[key] = .bool(number.boolValue)
                } else {
                    out[key] = .int(number.intValue)
                }
            }
        }
        if let peptides {
            out[Self.peptidesKey] = .data(try Self.bytes(peptides.backupArchiveData()))
        }
        if let workouts {
            out[Self.workoutsKey] = .data(try Self.bytes(workouts.backupData()))
        }
        return out
    }

    private static func bytes(_ part: CloudBackupPart) throws -> Data {
        switch part {
        case .include(let data): return data
        case .blocked(let reason): throw CloudBackupError.backupSkipped(reason)
        }
    }

    /// Restores `values` over this phone. When the backup carries peptides or
    /// workouts this phone can't take now (its own couldn't be read), nothing
    /// changes, `errorMessage` says why and the result is false: half a
    /// restore would replace the diary and settings but not them.
    @discardableResult
    func applyValues(_ values: [String: CloudBackupValue]) -> Bool {
        if let reason = restoreBlock(for: values) {
            errorMessage = "\(reason), so nothing was restored and everything on this phone was kept."
            return false
        }
        let restoredKeys = Set(values.keys)
        for key in defaults.dictionaryRepresentation().keys
        where CloudBackupPolicy.include(key) && !restoredKeys.contains(key) {
            defaults.removeObject(forKey: key)
        }
        for (key, value) in values {
            guard CloudBackupPolicy.include(key) else { continue }
            if key == Self.peptidesKey {
                // A backup without this value (older builds) never gets here: peptides stay as they are.
                guard let peptides else { continue }
                if let encoded = value.d, let archive = Data(base64Encoded: encoded) {
                    if let problem = peptides.restoreArchiveData(archive) { errorMessage = problem }
                } else {
                    errorMessage = "Peptides weren't restored, so the ones on this phone were kept."
                }
                continue
            }
            if key == Self.workoutsKey {
                // A backup without this value (older builds) never gets here: workouts stay as they are.
                guard let workouts else { continue }
                if let encoded = value.d, let log = Data(base64Encoded: encoded) {
                    if let problem = workouts.restoreBackupData(log) { errorMessage = problem }
                } else {
                    errorMessage = "Workouts weren't restored, so the ones on this phone were kept."
                }
                continue
            }
            switch value.t {
            case "b":
                if let b = value.b { defaults.set(b, forKey: key) }
            case "i":
                if let i = value.i { defaults.set(i, forKey: key) }
            case "s":
                if let s = value.s { defaults.set(s, forKey: key) }
            case "d":
                if let d = value.d, let data = Data(base64Encoded: d) {
                    defaults.set(data, forKey: key)
                }
            case "ss":
                if let ss = value.ss { defaults.set(ss, forKey: key) }
            default:
                continue
            }
        }
        defaults.set(true, forKey: "healthKitFoodRecoveryDone")
        defaults.set(true, forKey: Self.enabledKey)
        enabled = true
        return true
    }

    /// Why a store can't take its part of `values`. A store that can't back
    /// up its part can't be restored over either: both need its log read in full.
    private func restoreBlock(for values: [String: CloudBackupValue]) -> String? {
        if values[Self.peptidesKey] != nil, case .blocked(let reason)? = peptides?.backupArchiveData() { return reason }
        if values[Self.workoutsKey] != nil, case .blocked(let reason)? = workouts?.backupData() { return reason }
        return nil
    }

    func snapshotPhotos() -> [String: Data] {
        var photos: [String: Data] = [:]
        for name in FoodImageStore.shared.filenames() {
            guard let safe = CloudBackupPolicy.safePhotoName(name),
                  let data = FoodImageStore.shared.load(filename: safe)
            else { continue }
            photos[safe] = data
        }
        return photos
    }

    func restorePhotos(_ photos: [String: Data]) {
        FoodImageStore.shared.deleteAll()
        for (name, data) in photos {
            _ = FoodImageStore.shared.restore(data: data, filename: name)
        }
    }

    func checkAccount() async throws {
        let status = try await container.accountStatus()
        guard status == .available else { throw CloudBackupError.iCloudUnavailable }
    }

    func refreshCloudPresence() async {
        do {
            try await checkAccount()
            hasCloudBackup = try await fetchRecord() != nil
        } catch {
            hasCloudBackup = false
        }
    }

    func backupNow(skipIfUnchanged: Bool = false) async throws {
        busy = true
        defer { busy = false }
        errorMessage = nil
        try await checkAccount()
        let values: [String: CloudBackupValue]
        do {
            values = try snapshotValues()
        } catch {
            // Nothing is uploaded, so the last iCloud backup keeps what this phone couldn't read.
            errorMessage = error.localizedDescription
            return
        }
        let photos = snapshotPhotos()
        let hash = CloudBackupArchive.contentHash(values: values, photos: photos)
        if skipIfUnchanged, hash == defaults.string(forKey: Self.lastHashKey) { return }
        let zip = try CloudBackupArchive.pack(
            values: values,
            photos: photos,
            exportedAt: ISO8601DateFormatter().string(from: Date()),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        )
        try await upload(zip: zip, hash: hash)
        let now = ISO8601DateFormatter().string(from: Date())
        defaults.set(now, forKey: Self.lastAtKey)
        defaults.set(hash, forKey: Self.lastHashKey)
        lastAt = now
        enabled = true
        hasCloudBackup = true
    }

    func restoreNow() async throws {
        busy = true
        defer { busy = false }
        errorMessage = nil
        try await checkAccount()
        guard let record = try await fetchRecord(),
              let asset = record[assetField] as? CKAsset,
              let url = asset.fileURL
        else { throw CloudBackupError.noBackup }
        let zip = try Data(contentsOf: url)
        let (document, photos) = try CloudBackupArchive.unpack(zip)
        guard applyValues(document.payload.values) else { return }
        restorePhotos(photos)
        defaults.set(document.contentSha256, forKey: Self.lastHashKey)
        defaults.set(document.exportedAt, forKey: Self.lastAtKey)
        lastAt = document.exportedAt
        NotificationCenter.default.post(name: .cloudBackupDidRestore, object: nil)
    }

    func deleteCloudBackup() async throws {
        busy = true
        defer { busy = false }
        try await deleteCloudRecord(named: recordName)
    }

    func autoBackupIfNeeded() async {
        guard enabled else { return }
        guard isUnmetered() else { return }
        if let last = lastAt,
           let date = ISO8601DateFormatter().date(from: last),
           Date().timeIntervalSince(date) < CloudBackupPolicy.minAutoBackupInterval {
            return
        }
        try? await backupNow(skipIfUnchanged: true)
    }

    /// Release-safe CloudKit integration check: upload → download → delete.
    /// Logs `FudAICloudBackupSmokeTest: PASS` or `FAIL: <reason>` to stdout and os_log.
    func runSmokeTestIfRequested() async {
        guard CommandLine.arguments.contains(Self.smokeTestLaunchArgument) else { return }
        guard !Self.didRunSmokeTestThisLaunch else { return }
        Self.didRunSmokeTestThisLaunch = true
        await runSmokeTest()
    }

    func runSmokeTest() async {
        var smokeUploaded = false

        do {
            try await checkAccount()
            let values = try snapshotValues()
            let photos = snapshotPhotos()
            let hash = CloudBackupArchive.contentHash(values: values, photos: photos)
            let zip = try CloudBackupArchive.pack(
                values: values,
                photos: photos,
                exportedAt: ISO8601DateFormatter().string(from: Date()),
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
            )
            try await upload(zip: zip, hash: hash, toRecord: Self.smokeTestRecordName)
            smokeUploaded = true

            guard let record = try await fetchRecord(named: Self.smokeTestRecordName) else {
                logSmokeTestFailure("backup record missing after upload")
                return
            }
            try validateDownloadedBackup(record: record, expectedHash: hash)

            try await deleteCloudRecord(named: Self.smokeTestRecordName)
            smokeUploaded = false

            guard try await fetchRecord(named: Self.smokeTestRecordName) == nil else {
                logSmokeTestFailure("record still present after delete")
                return
            }
            logSmokeTestPass()
        } catch {
            logSmokeTestFailure(error.localizedDescription)
        }

        if smokeUploaded {
            try? await deleteCloudRecord(named: Self.smokeTestRecordName)
        }
    }

    private func logSmokeTestPass() {
        let line = "FudAICloudBackupSmokeTest: PASS"
        print(line)
        Self.smokeLogger.info("\(line, privacy: .public)")
    }

    private func logSmokeTestFailure(_ reason: String) {
        let line = "FudAICloudBackupSmokeTest: FAIL: \(reason)"
        print(line)
        Self.smokeLogger.error("\(line, privacy: .public)")
    }

    private func upload(zip: Data, hash: String, toRecord named: String? = nil) async throws {
        let name = named ?? recordName
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("fudai-backup.zip")
        try zip.write(to: temp, options: .atomic)
        let id = CKRecord.ID(recordName: name)
        let record = (try? await fetchRecord(named: name)) ?? CKRecord(recordType: recordType, recordID: id)
        record[assetField] = CKAsset(fileURL: temp)
        record[shaField] = hash as CKRecordValue
        _ = try await container.privateCloudDatabase.save(record)
    }

    private func fetchRecord(named name: String? = nil) async throws -> CKRecord? {
        let id = CKRecord.ID(recordName: name ?? recordName)
        do {
            return try await container.privateCloudDatabase.record(for: id)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    private func deleteCloudRecord(named name: String) async throws {
        try await checkAccount()
        let id = CKRecord.ID(recordName: name)
        do {
            try await container.privateCloudDatabase.deleteRecord(withID: id)
        } catch let error as CKError where error.code == .unknownItem {
            // already gone
        }
        guard name == recordName else { return }
        hasCloudBackup = false
        defaults.removeObject(forKey: Self.lastAtKey)
        defaults.removeObject(forKey: Self.lastHashKey)
        lastAt = nil
    }

    private func validateDownloadedBackup(record: CKRecord, expectedHash: String) throws {
        guard let asset = record[assetField] as? CKAsset,
              let url = asset.fileURL
        else { throw CloudBackupError.noBackup }
        let zip = try Data(contentsOf: url)
        let (document, _) = try CloudBackupArchive.unpack(zip)
        guard document.contentSha256 == expectedHash else { throw CloudBackupError.invalidFormat }
        if let recordSha = record[shaField] as? String, recordSha != expectedHash {
            throw CloudBackupError.invalidFormat
        }
    }

    private func isUnmetered() -> Bool { true }
}

extension Notification.Name {
    static let cloudBackupDidRestore = Notification.Name("ai.fud.cloudBackupDidRestore")
}
