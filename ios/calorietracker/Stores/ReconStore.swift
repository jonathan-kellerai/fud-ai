import Foundation

/// What's left of Recon Bench, which build 68 folded into Reconstitute
/// (ReconView). Its old save is no longer read; Delete Everything still
/// removes it, along with the rest of the peptide data.
enum ReconBenchStore {
    static let defaultsKey = "recon.bench.v1"

    static var fileURL: URL? {
        guard let directory = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.appGroupID)?
            .appendingPathComponent("Library/Application Support/ReconBench", isDirectory: true) else { return nil }
        return directory.appendingPathComponent("recon_bench_v1.json")
    }

    /// Delete Everything: the saved bench file and its UserDefaults copy.
    static func deleteSavedData() {
        if let url = fileURL {
            try? FileManager.default.removeItem(at: url)
        }
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
}
