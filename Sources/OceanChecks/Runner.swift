import Foundation

struct CheckFailure: Error { let detail: String }

final class Runner {
    nonisolated(unsafe) static var failed = 0
    nonisolated(unsafe) static var passed = 0
    nonisolated(unsafe) static var filter: String? = nil
}

func check(_ name: String, _ body: () throws -> Void) {
    if let f = Runner.filter, !name.contains(f) { return }
    do {
        try body()
        Runner.passed += 1
        print("PASS \(name)")
    } catch let e as CheckFailure {
        Runner.failed += 1
        print("FAIL \(name): \(e.detail)")
    } catch {
        Runner.failed += 1
        print("FAIL \(name): threw \(error)")
    }
}

func expect(_ cond: Bool, _ detail: @autoclosure () -> String) throws {
    if !cond { throw CheckFailure(detail: detail()) }
}

func expectClose(_ a: Double, _ b: Double, tol: Double, _ detail: String) throws {
    if abs(a - b) > tol { throw CheckFailure(detail: "\(detail): \(a) vs \(b) (tol \(tol))") }
}
