import Foundation

@MainActor
enum ColourCommitRegressionTests {
    static func run(expect: (Bool, String) -> Void) {
        let committer = DiscreteColourCommitter()
        var events: [Bool] = []
        committer.update { events.append($0) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        expect(events == [true, false],
               "keyboard/AX wheel edits finalize while the editor stays open")

        events = []
        committer.update { events.append($0) }
        committer.update { events.append($0) }
        committer.update { events.append($0) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        expect(events == [true, true, true, false],
               "repeated discrete wheel edits produce only one idle commit")

        events = []
        committer.update { events.append($0) }
        committer.cancel()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        expect(events == [true], "a pointer drag or disappearing control cancels a stale idle commit")
    }
}
