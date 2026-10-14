import Foundation

/// The bridge's workout export used as the import fixture (11 workouts, 87 sets).
enum WorkoutImportFixture {
    /// The test bundle's copy (Fixtures/ is a synchronized folder, so the file
    /// is a bundle resource), else the checkout next to the tests.
    static var url: URL {
        Bundle(for: BundleToken.self).url(forResource: "jl-workouts-import", withExtension: "json")
            ?? URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent() // Support
                .deletingLastPathComponent() // calorietrackerTests
                .appendingPathComponent("Fixtures", isDirectory: true)
                .appendingPathComponent("jl-workouts-import.json")
    }

    private final class BundleToken {}
}
