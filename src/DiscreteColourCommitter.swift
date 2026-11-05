import Foundation
import Combine

/// Keyboard and accessibility changes have no pointer-release event.
/// Their idle boundary must finalize the same edit that a drag finalizes on release.
@MainActor
final class DiscreteColourCommitter: ObservableObject {
    private var pending: DispatchWorkItem?

    func update(_ onEditingChanged: @escaping (Bool) -> Void) {
        cancel()
        onEditingChanged(true)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pending = nil
            onEditingChanged(false)
        }
        pending = work
        // Coalesce key-repeat and VoiceOver slider increments, rather than saving
        // a hardware frame for every increment. Pointer drags still commit on release.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    func cancel() {
        pending?.cancel()
        pending = nil
    }

    deinit { pending?.cancel() }
}
