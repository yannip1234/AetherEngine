import AVFoundation
import Foundation

/// Synchronizes command admission receipts, with thread-local suppression for engine calls.
/// AVPlayer operations remain synchronous on their caller; no lock spans AVFoundation callbacks.
private final class NativeCommandGate: @unchecked Sendable {
    private let lock = NSLock()
    private let depthKey = "NativeCommandPlayer." + UUID().uuidString
    private var enabled = true
    private var revision: UInt64 = 0
    private var sequence: UInt64 = 0
    var acceptsCommands: Bool {
        get { lock.withLock { enabled } }
        set { lock.withLock { if enabled != newValue { revision &+= 1 }; enabled = newValue } }
    }
    func isCurrent(_ receipt: (sequence: UInt64, revision: UInt64)) -> Bool {
        lock.withLock { enabled && revision == receipt.revision }
    }
    func perform(internalCall: Bool, before: ((sequence: UInt64, revision: UInt64)) -> Void, operation: () -> Void) {
        let dictionary = Thread.current.threadDictionary
        let depth = dictionary[depthKey] as? Int ?? 0
        let external = depth == 0 && !internalCall
        var receipt: (sequence: UInt64, revision: UInt64)?
        if external {
            receipt = lock.withLock {
                guard enabled else { return nil }
                sequence &+= 1
                return (sequence, revision)
            }
            guard receipt != nil else { return }
        }
        dictionary[depthKey] = depth + 1
        defer { if depth == 0 { dictionary.removeObject(forKey: depthKey) } else { dictionary[depthKey] = depth } }
        if let receipt { before(receipt) }
        // Never hold the state lock while AVFoundation invokes synchronous KVO.
        operation()
    }
}

/// Reports public native transport commands, never inferred rate/KVO changes.
final class NativeCommandPlayer: AVPlayer, @unchecked Sendable {
    private nonisolated let commandGate = NativeCommandGate()
    private var lastDeliveredSequence: UInt64 = 0
    var onCommand: (@MainActor (NativeCommandPlayer, AVPlayerItem?, Float) -> Void)?
    nonisolated var acceptsExternalCommands: Bool {
        get { commandGate.acceptsCommands }
        set { commandGate.acceptsCommands = newValue }
    }
    func internally(_ operation: () -> Void) {
        commandGate.perform(internalCall: true, before: { _ in }, operation: operation)
    }
    private nonisolated func command(rate: Float, operation: () -> Void) {
        commandGate.perform(internalCall: false, before: { receipt in
            let item = currentItem
            Task { @MainActor [weak self, weak item] in
                guard let self, self.currentItem === item, self.commandGate.isCurrent(receipt),
                      receipt.sequence > self.lastDeliveredSequence else { return }
                self.lastDeliveredSequence = receipt.sequence
                self.onCommand?(self, item, rate)
            }
        }, operation: operation)
    }
    override func play() { command(rate: defaultRate) { super.play() } }
    override func pause() { command(rate: 0) { super.pause() } }
    override func playImmediately(atRate rate: Float) { command(rate: rate) { super.playImmediately(atRate: rate) } }
    override var rate: Float {
        get { super.rate }
        set { command(rate: newValue) { super.rate = newValue } }
    }
}
