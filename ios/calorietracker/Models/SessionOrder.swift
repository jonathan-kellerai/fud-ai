import Foundation

/// Performed order is independent of the planned day. Supersets remain atomic.
struct SessionOrder {
    enum Direction { case up, down }

    struct Position: Equatable {
        let performed: Int
        let planned: Int
    }

    let plannedBlocks: [ExerciseBlock]
    private(set) var blocks: [ExerciseBlock]

    init(plannedBlocks: [ExerciseBlock], exerciseOrder: [String]? = nil) {
        self.plannedBlocks = plannedBlocks
        var indices: [Int] = []
        for name in exerciseOrder ?? [] {
            guard let index = plannedBlocks.firstIndex(where: { block in
                block.exercises.contains { $0.name == name }
            }), !indices.contains(index) else { continue }
            indices.append(index)
        }
        // Missing/new exercises follow in planned order; unknown saved names
        // cannot remove an exercise from a session.
        indices.append(contentsOf: plannedBlocks.indices.filter { !indices.contains($0) })
        blocks = indices.map { plannedBlocks[$0] }
    }

    var exerciseOrder: [String] { blocks.flatMap(\.exercises).map(\.name) }

    mutating func move(blockAt index: Int, direction: Direction) {
        guard blocks.indices.contains(index) else { return }
        let destination: Int
        switch direction {
        case .up: destination = index - 1
        case .down: destination = index + 1
        }
        guard blocks.indices.contains(destination) else { return }
        blocks.swapAt(index, destination)
    }

    func position(for name: String) -> Position? {
        let planned = plannedBlocks.flatMap(\.exercises).map(\.name)
        guard let plannedIndex = planned.firstIndex(of: name),
              let performedIndex = exerciseOrder.firstIndex(of: name) else { return nil }
        return Position(performed: performedIndex + 1, planned: plannedIndex + 1)
    }

    func isDoneLaterThanPlanned(_ name: String) -> Bool {
        guard let position = position(for: name) else { return false }
        return position.performed > position.planned
    }
}
