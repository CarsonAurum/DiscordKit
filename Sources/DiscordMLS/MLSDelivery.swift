import Foundation

extension MLSProposal {
    /// Splits the self-delimiting external public messages in a DAVE append vector.
    /// Signatures and membership are deliberately authenticated later by `MLSGroup`.
    /// - Parameters:
    ///   - data: Concatenated MLSMessages without individual length prefixes, at most one MiB.
    ///   - maximumMessages: Maximum parsed proposals, 1...1024; empty vectors are allowed.
    /// - Returns: Canonical complete message bytes in delivery order; no input is retained.
    /// - Throws: `invalidConfiguration`, capacity/framing errors, or `invalidProposal`
    ///   for a member sender, commit, or unsupported proposal. No partial result escapes.
    public static func splitExternalMessages(_ data: Data, maximumMessages: Int = 256) throws -> [Data] {
        guard (1...1024).contains(maximumMessages) else { throw MLSError.invalidConfiguration }
        var reader = try MLSReader(data)
        var messages: [Data] = []
        while !reader.isAtEnd {
            guard messages.count < maximumMessages else { throw MLSError.capacityExceeded }
            let message = try MLSPublicMessage.decode(&reader)
            guard message.sender == .external(0), case .proposal = message.body else { throw MLSError.invalidProposal }
            messages.append(try message.encoded())
        }
        return messages
    }
}
