import Crypto
import Foundation

/// Checked array-based perfect binary-tree arithmetic from RFC 9420 Appendix C.
/// Node indices are distinct from leaf indices: leaf `i` occupies node `2*i`.
public enum MLSTreeMath {
    /// Returns the height of a node above leaves without consulting a tree.
    /// - Parameter node: Unsigned array index; even values identify leaves.
    /// - Returns: The number of consecutive low one bits, from zero through 32.
    public static func level(_ node: UInt32) -> Int { (~node).trailingZeroBitCount }

    /// Finds the root of a bounded perfect tree.
    /// - Parameter leafCount: Power-of-two capacity from one through 65,536.
    /// - Returns: Array index of its root.
    /// - Throws: `invalidTree` for an unsupported or non-perfect capacity.
    public static func root(leafCount: Int) throws -> UInt32 {
        guard leafCount > 0, leafCount <= 65_536, leafCount.nonzeroBitCount == 1 else { throw MLSError.invalidTree }
        return UInt32(leafCount - 1)
    }

    /// Finds a parent's left child.
    /// - Parameter node: Parent index below the maximum supported tree width.
    /// - Returns: Child array index.
    /// - Throws: `invalidTree` if the index is a leaf or outside supported bounds.
    public static func left(_ node: UInt32) throws -> UInt32 {
        let height = level(node)
        guard height > 0, node < 131_071 else { throw MLSError.invalidTree }
        return node ^ (1 << (height - 1))
    }

    /// Finds a parent's right child in a perfect tree.
    /// - Parameter node: Parent index below the maximum supported tree width.
    /// - Returns: Child array index.
    /// - Throws: `invalidTree` if the index is a leaf or outside supported bounds.
    public static func right(_ node: UInt32) throws -> UInt32 {
        let height = level(node)
        guard height > 0, node < 131_071 else { throw MLSError.invalidTree }
        return node ^ (3 << (height - 1))
    }

    /// Finds a node's parent, rejecting root and out-of-tree indices.
    /// - Parameters:
    ///   - node: Array index within the specified tree.
    ///   - leafCount: Supported power-of-two leaf capacity.
    /// - Returns: Parent array index.
    /// - Throws: `invalidTree` for invalid capacity/index or the root node.
    public static func parent(_ node: UInt32, leafCount: Int) throws -> UInt32 {
        let root = try root(leafCount: leafCount)
        guard node < UInt32(2 * leafCount - 1), node != root else { throw MLSError.invalidTree }
        let height = level(node)
        return (node | (1 << height)) ^ (((node >> (height + 1)) & 1) << (height + 1))
    }

    /// Finds the other child of a node's parent.
    /// - Parameters:
    ///   - node: Non-root array index in the specified tree.
    ///   - leafCount: Supported power-of-two leaf capacity.
    /// - Returns: Sibling array index.
    /// - Throws: `invalidTree` for invalid input or the root node.
    public static func sibling(_ node: UInt32, leafCount: Int) throws -> UInt32 {
        let ancestor = try parent(node, leafCount: leafCount)
        return try node < ancestor ? right(ancestor) : left(ancestor)
    }

    /// Enumerates ancestors from the immediate parent to the root.
    /// - Parameters:
    ///   - node: Any array index within the tree, including its root.
    ///   - leafCount: Supported power-of-two leaf capacity.
    /// - Returns: At most sixteen ancestors; the root's path is empty.
    /// - Throws: `invalidTree` for an invalid capacity or node index.
    public static func directPath(_ node: UInt32, leafCount: Int) throws -> [UInt32] {
        let root = try root(leafCount: leafCount)
        guard node < UInt32(2 * leafCount - 1) else { throw MLSError.invalidTree }
        var cursor = node; var result: [UInt32] = []
        while cursor != root { cursor = try parent(cursor, leafCount: leafCount); result.append(cursor) }
        return result
    }

    /// Enumerates the siblings encountered from a node toward the root.
    /// - Parameters:
    ///   - node: Any array index within the tree.
    ///   - leafCount: Supported power-of-two leaf capacity.
    /// - Returns: Copath in the same bottom-up order as the direct path.
    /// - Throws: `invalidTree` for invalid input.
    public static func copath(_ node: UInt32, leafCount: Int) throws -> [UInt32] {
        let path = try directPath(node, leafCount: leafCount)
        return try ([node] + path.dropLast()).prefix(path.count).map { try sibling($0, leafCount: leafCount) }
    }

    /// Tests subtree membership using the interval represented by a perfect-tree node.
    /// - Parameters:
    ///   - node: Candidate node index.
    ///   - ancestor: Subtree root; both indices must be below the supported width.
    /// - Returns: Whether `node` is `ancestor` or one of its descendants.
    public static func contains(_ node: UInt32, under ancestor: UInt32) -> Bool {
        guard node < 131_071, ancestor < 131_071 else { return false }
        let height = level(ancestor)
        return (node >> (height + 1)) == (ancestor >> (height + 1)) && level(node) <= height
    }
}

/// RFC 9420 ParentNode, with strictly increasing unmerged leaf indices.
public struct MLSParentNode: Sendable, Equatable {
    public let encryptionKey: Data
    public let parentHash: Data
    public let unmergedLeaves: [UInt32]

    /// Validates a ciphersuite-2 parent representation without authenticating its tree.
    /// - Parameters:
    ///   - encryptionKey: Valid uncompressed 65-byte NIST P-256 public key.
    ///   - parentHash: Empty at generation's root or a 32-byte SHA-256 digest.
    ///   - unmergedLeaves: Strictly increasing leaf indices, at most 65,536 entries.
    /// - Throws: `invalidTree` for invalid keys, hashes, ordering, or repeated indices.
    public init(encryptionKey: Data, parentHash: Data = Data(), unmergedLeaves: [UInt32] = []) throws {
        guard encryptionKey.count == 65, (parentHash.isEmpty || parentHash.count == 32),
              unmergedLeaves.count <= 65_536,
              zip(unmergedLeaves, unmergedLeaves.dropFirst()).allSatisfy({ $0 < $1 }),
              (try? P256.KeyAgreement.PublicKey(x963Representation: encryptionKey)) != nil else { throw MLSError.invalidTree }
        self.encryptionKey = encryptionKey; self.parentHash = parentHash; self.unmergedLeaves = unmergedLeaves
    }

    /// Serializes this parent using RFC 9420 vectors and network-order leaf indices.
    /// - Returns: ParentNode bytes without a NodeType discriminator.
    /// - Throws: `capacityExceeded` if aggregate serialization exceeds one MiB.
    public func encoded() throws -> Data {
        var writer = MLSWriter(); try writer.writeVector(encryptionKey); try writer.writeVector(parentHash)
        var leaves = MLSWriter(); for leaf in unmergedLeaves { leaves.write(leaf) }
        try writer.writeVector(leaves.data); return writer.data
    }

    /// Reads a single parent from an enclosing cursor.
    /// - Parameter reader: Cursor advanced past its fields on success.
    /// - Returns: Size-, key-, and order-validated parent.
    /// - Throws: Wire errors or `invalidTree` for invalid parent contents.
    public static func decode(_ reader: inout MLSReader) throws -> Self {
        let key = try reader.readVector(); let hash = try reader.readVector()
        var vector = try MLSReader(reader.readVector()); var leaves: [UInt32] = []
        while !vector.isAtEnd { leaves.append(try vector.readUInt32()) }
        return try Self(encryptionKey: key, parentHash: hash, unmergedLeaves: leaves)
    }
}

/// Tagged public ratchet-tree node. Blank nodes are represented by `nil` separately.
public enum MLSNode: Sendable, Equatable {
    case leaf(MLSLeafNode)
    case parent(MLSParentNode)
}

/// One RFC 9420 UpdatePathNode, ordered by the sender's filtered direct path.
public struct MLSUpdatePathNode: Sendable, Equatable {
    public let encryptionKey: Data
    public let encryptedPathSecrets: [MLSHPKECiphertext]

    /// Creates a wire node; tree merging additionally validates key and recipient counts.
    /// - Parameters:
    ///   - encryptionKey: Parent's suite-2 HPKE public key.
    ///   - encryptedPathSecrets: One ciphertext per copath resolution entry, in order.
    public init(encryptionKey: Data, encryptedPathSecrets: [MLSHPKECiphertext]) {
        self.encryptionKey = encryptionKey; self.encryptedPathSecrets = encryptedPathSecrets
    }
}

/// Signed replacement leaf plus encrypted path nodes from RFC 9420 section 7.6.
public struct MLSUpdatePath: Sendable, Equatable {
    public let leafNode: MLSLeafNode
    public let nodes: [MLSUpdatePathNode]

    /// Creates a path for subsequent bounded encoding and authenticated tree processing.
    /// - Parameters:
    ///   - leafNode: Source-commit leaf signed with the group ID and sender leaf index.
    ///   - nodes: Bottom-up filtered direct-path nodes, at most sixteen for this profile.
    public init(leafNode: MLSLeafNode, nodes: [MLSUpdatePathNode]) { self.leafNode = leafNode; self.nodes = nodes }

    /// Serializes a complete UpdatePath without an enclosing optional discriminator.
    /// - Returns: RFC 9420 UpdatePath bytes.
    /// - Throws: Capacity errors for an excessive node or ciphertext list.
    public func encoded() throws -> Data { var writer = MLSWriter(); try write(to: &writer); return writer.data }

    /// Decodes a complete path, rejecting extra input and excessive vectors.
    /// - Parameter data: At most one MiB of UpdatePath bytes.
    /// - Returns: The decoded path; signature and TreeKEM validation remain separate.
    /// - Throws: Wire errors and `capacityExceeded` for excessive nodes or recipients.
    public static func decode(_ data: Data) throws -> Self {
        var reader = try MLSReader(data); let result = try read(from: &reader); try reader.requireEnd(); return result
    }

    /// Appends the path to a surrounding Commit encoder.
    /// - Parameter writer: Bounded destination updated with raw LeafNode and node vector.
    /// - Throws: Capacity errors for more than sixteen nodes or excessive aggregate bytes.
    public func write(to writer: inout MLSWriter) throws {
        guard nodes.count <= 16 else { throw MLSError.capacityExceeded }
        try writer.writeRaw(leafNode.encoded()); var body = MLSWriter()
        for node in nodes {
            try body.writeVector(node.encryptionKey); var encrypted = MLSWriter()
            guard node.encryptedPathSecrets.count <= 65_536 else { throw MLSError.capacityExceeded }
            for value in node.encryptedPathSecrets {
                try encrypted.writeVector(value.kemOutput); try encrypted.writeVector(value.ciphertext)
            }
            try body.writeVector(encrypted.data)
        }
        try writer.writeVector(body.data)
    }

    /// Reads one path from an enclosing Commit without consuming subsequent fields.
    /// - Parameter reader: Cursor advanced through LeafNode and node-vector bytes.
    /// - Returns: A bounded syntactic path requiring tree and signature authentication.
    /// - Throws: Wire errors or `capacityExceeded` for more than sixteen path nodes.
    public static func read(from reader: inout MLSReader) throws -> Self {
        let leaf = try MLSLeafNode.decode(&reader); var vector = try MLSReader(reader.readVector())
        var nodes: [MLSUpdatePathNode] = []
        while !vector.isAtEnd {
            guard nodes.count < 16 else { throw MLSError.capacityExceeded }
            let key = try vector.readVector(); var encrypted = try MLSReader(vector.readVector())
            var secrets: [MLSHPKECiphertext] = []
            while !encrypted.isAtEnd {
                guard secrets.count < 65_536 else { throw MLSError.capacityExceeded }
                secrets.append(MLSHPKECiphertext(kemOutput: try encrypted.readVector(), ciphertext: try encrypted.readVector()))
            }
            nodes.append(MLSUpdatePathNode(encryptionKey: key, encryptedPathSecrets: secrets))
        }
        return Self(leafNode: leaf, nodes: nodes)
    }
}

/// Temporary TreeKEM derivation output. Owners must discard intermediate path secrets
/// after Welcome creation and retain only the private keys for their own direct path.
/// Swift value copies do not provide guaranteed physical memory erasure.
public struct MLSPathSecrets: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let privateKeys: [UInt32: Data]
    public let pathSecrets: [UInt32: Data]
    public let commitSecret: Data
    /// Redacts every secret and key from ordinary diagnostic interpolation.
    public var description: String { "MLSPathSecrets(<redacted>)" }
    /// Uses the same redacted representation in debug output.
    public var debugDescription: String { description }
    /// Replaces reflected key and secret dictionaries with a fixed redacted marker.
    public var customMirror: Mirror { Mirror(self, children: ["secret": "<redacted>"]) }
}

/// Sender's staged update, before HPKE binds the provisional GroupContext.
public struct MLSGeneratedUpdate: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let leafNode: MLSLeafNode
    public let encryptionKeys: [Data]
    public let pathSecrets: [UInt32: Data]
    public let privateKeys: [UInt32: Data]
    public let commitSecret: Data
    /// Redacts every secret and key from ordinary diagnostic interpolation.
    public var description: String { "MLSGeneratedUpdate(<redacted>)" }
    /// Uses the same redacted representation in debug output.
    public var debugDescription: String { description }
    /// Replaces reflected key and secret dictionaries with a fixed redacted marker.
    public var customMirror: Mirror { Mirror(self, children: ["secret": "<redacted>"]) }
}

/// Bounded public RFC 9420 ratchet tree with explicit, transactional TreeKEM updates.
///
/// The stored tree is always perfect, padding omitted wire blanks. Construction and
/// mutation perform no I/O, tasks, randomness, credential authorization, or clocks.
/// Group owners must authenticate leaves and proposals before membership changes.
public struct MLSRatchetTree: Sendable, Equatable {
    public private(set) var nodes: [MLSNode?]
    public let maximumMembers: Int
    /// Power-of-two leaf capacity, including blank positions.
    public var leafCount: Int { (nodes.count + 1) / 2 }
    /// Number of populated leaf positions, bounded independently of capacity.
    public var memberCount: Int { nodes.enumerated().filter { $0.offset & 1 == 0 && $0.element != nil }.count }

    /// Pads an array representation to the smallest perfect tree and checks structure.
    /// - Parameters:
    ///   - nodes: Nonempty node list, optionally omitting trailing blank nodes.
    ///   - maximumMembers: Positive member limit, at most 65,536; defaults to 1,024.
    /// - Throws: `invalidConfiguration` for invalid limits, `capacityExceeded` for
    ///   excessive storage/members, or `invalidTree` for malformed node placement,
    ///   repeated keys, or inconsistent unmerged leaves. Parent hashes/signatures
    ///   are authenticated separately after decoding the enclosing group context.
    public init(nodes: [MLSNode?], maximumMembers: Int = 1_024) throws {
        guard maximumMembers > 0, maximumMembers <= 65_536 else { throw MLSError.invalidConfiguration }
        guard !nodes.isEmpty else { throw MLSError.invalidTree }
        var capacity = 1
        while capacity < (nodes.count + 2) / 2 { capacity *= 2; guard capacity <= 65_536 else { throw MLSError.capacityExceeded } }
        var maximumCapacity = 1; while maximumCapacity < maximumMembers { maximumCapacity *= 2 }
        guard capacity <= maximumCapacity else { throw MLSError.capacityExceeded }
        self.nodes = nodes + Array(repeating: nil, count: 2 * capacity - 1 - nodes.count)
        self.maximumMembers = maximumMembers
        try validateStructure()
    }

    /// Creates a one-member tree without authenticating its supplied leaf signature.
    /// - Parameters:
    ///   - leaf: Creator's signed leaf, generally sourced from its KeyPackage.
    ///   - maximumMembers: Future live-member budget, one through 65,536.
    /// - Throws: Configuration, capacity, or structural tree errors.
    public init(leaf: MLSLeafNode, maximumMembers: Int = 1_024) throws {
        try self.init(nodes: [.leaf(leaf)], maximumMembers: maximumMembers)
    }

    /// Reads a leaf without conflating its index with a node index.
    /// - Parameter index: Leaf position within the current capacity.
    /// - Returns: Its LeafNode, or nil for a blank/out-of-range position.
    public func leaf(at index: UInt32) -> MLSLeafNode? {
        guard index < leafCount, case .leaf(let value) = nodes[Int(index) * 2] else { return nil }; return value
    }

    /// Encodes the ratchet_tree extension value, omitting all trailing blank nodes.
    /// - Returns: A canonical vector of optional tagged nodes.
    /// - Throws: `invalidTree` for an entirely blank tree or encoder capacity errors.
    public func encoded() throws -> Data {
        guard let last = nodes.lastIndex(where: { $0 != nil }) else { throw MLSError.invalidTree }
        var body = MLSWriter()
        for node in nodes[...last] {
            guard let node else { body.write(UInt8(0)); continue }
            body.write(UInt8(1))
            switch node {
            case .leaf(let leaf): body.write(UInt8(1)); try body.writeRaw(leaf.encoded())
            case .parent(let parent): body.write(UInt8(2)); try body.writeRaw(parent.encoded())
            }
        }
        var outer = MLSWriter(); try outer.writeVector(body.data); return outer.data
    }

    /// Decodes a bounded ratchet_tree extension, padding its omitted trailing blanks.
    /// - Parameters:
    ///   - data: Complete extension value, at most one MiB.
    ///   - maximumMembers: Future member budget; defaults to 1,024.
    /// - Returns: Structurally valid public tree; call leaf and parent authentication
    ///   before admitting it into trusted group state.
    /// - Throws: Wire, capacity, configuration, or structural tree errors.
    public static func decode(_ data: Data, maximumMembers: Int = 1_024) throws -> Self {
        var outer = try MLSReader(data); var body = try MLSReader(outer.readVector()); try outer.requireEnd()
        var nodes: [MLSNode?] = []
        while !body.isAtEnd {
            guard nodes.count < 131_071 else { throw MLSError.capacityExceeded }
            switch try body.readUInt8() {
            case 0: nodes.append(nil)
            case 1:
                switch try body.readUInt8() {
                case 1: nodes.append(.leaf(try MLSLeafNode.decode(&body)))
                case 2: nodes.append(.parent(try MLSParentNode.decode(&body)))
                default: throw MLSError.malformedEncoding
                }
            default: throw MLSError.malformedEncoding
            }
        }
        guard nodes.last.flatMap({ $0 }) != nil else { throw MLSError.invalidTree }
        return try Self(nodes: nodes, maximumMembers: maximumMembers)
    }

    /// Computes the ordered resolution of a subtree per RFC 9420 section 4.1.1.
    /// - Parameter node: Array index within the current perfect tree.
    /// - Returns: Nearest populated descendants, then each populated parent's
    ///   unmerged leaf nodes in increasing leaf-index order; blank leaves yield empty.
    /// - Throws: `invalidTree` for an out-of-tree node.
    public func resolution(_ node: UInt32) throws -> [UInt32] {
        guard node < nodes.count else { throw MLSError.invalidTree }
        switch nodes[Int(node)] {
        case .leaf: return [node]
        case .parent(let parent): return [node] + parent.unmergedLeaves.map { $0 * 2 }
        case nil:
            guard node & 1 != 0 else { return [] }
            return try resolution(MLSTreeMath.left(node)) + resolution(MLSTreeMath.right(node))
        }
    }

    /// Filters a leaf's direct path by removing parents with empty copath resolutions.
    /// - Parameter leafIndex: Leaf index within capacity, including blank leaves.
    /// - Returns: Bottom-up parent node indices used by UpdatePath derivation.
    /// - Throws: `invalidTree` for an out-of-capacity leaf.
    public func filteredDirectPath(for leafIndex: UInt32) throws -> [UInt32] {
        guard leafIndex < leafCount else { throw MLSError.invalidTree }
        let direct = try MLSTreeMath.directPath(leafIndex * 2, leafCount: leafCount)
        let copath = try MLSTreeMath.copath(leafIndex * 2, leafCount: leafCount)
        return try zip(direct, copath).compactMap { try resolution($1).isEmpty ? nil : $0 }
    }

    /// Hashes an entire public tree or a selected subtree using SHA-256.
    /// - Parameter node: Optional subtree node; nil selects the root.
    /// - Returns: RFC 9420 section 7.8 TreeHash, exactly 32 bytes.
    /// - Throws: `invalidTree` for an invalid index or encoding capacity errors.
    public func treeHash(at node: UInt32? = nil) throws -> Data {
        try hash(node ?? MLSTreeMath.root(leafCount: leafCount), excluding: [])
    }

    /// Adds an authenticated KeyPackage leaf at the first blank leaf, extending as needed.
    /// - Parameter leaf: Source-keyPackage leaf already authorized by the group owner.
    /// - Returns: Its new leaf index.
    /// - Throws: `invalidTree` for duplicate keys/source, or `capacityExceeded` at
    ///   the member budget. Failed operations preserve the original tree.
    @discardableResult public mutating func add(_ leaf: MLSLeafNode) throws -> UInt32 {
        guard leaf.source == .keyPackage else { throw MLSError.invalidTree }
        guard memberCount < maximumMembers else { throw MLSError.capacityExceeded }
        var candidate = self
        var index = (0..<leafCount).first { candidate.nodes[$0 * 2] == nil }
        if index == nil {
            index = leafCount
            candidate.nodes.append(contentsOf: Array(repeating: nil, count: nodes.count + 1))
        }
        let position = UInt32(index!)
        candidate.nodes[Int(position) * 2] = .leaf(leaf)
        for node in try MLSTreeMath.directPath(position * 2, leafCount: candidate.leafCount) {
            if case .parent(let parent) = candidate.nodes[Int(node)] {
                candidate.nodes[Int(node)] = .parent(try MLSParentNode(encryptionKey: parent.encryptionKey, parentHash: parent.parentHash,
                    unmergedLeaves: (parent.unmergedLeaves + [position]).sorted()))
            }
        }
        try candidate.validateStructure(); self = candidate; return position
    }

    /// Applies an authorized Update proposal and blanks all ancestors of its leaf.
    /// - Parameters:
    ///   - leafIndex: Existing populated member's leaf index.
    ///   - leaf: Source-update replacement with a changed encryption key and valid signature.
    /// - Throws: `invalidTree` for absent member, duplicate/unchanged keys, or wrong
    ///   source. Authorization and leaf signature verification belong to the owner.
    public mutating func update(at leafIndex: UInt32, leaf: MLSLeafNode) throws {
        guard let old = self.leaf(at: leafIndex), leaf.source == .update, old.encryptionKey != leaf.encryptionKey else { throw MLSError.invalidTree }
        var candidate = self; try candidate.blankPath(leafIndex)
        candidate.nodes[Int(leafIndex) * 2] = .leaf(leaf)
        try candidate.validateStructure(); self = candidate
    }

    /// Removes a member, blanks its ancestors, and discards all-blank right subtrees.
    /// - Parameter leafIndex: Populated member's leaf index.
    /// - Throws: `invalidTree` for an absent leaf or removal of the final member.
    ///   Group owners represent their own removal with a separate terminal state.
    public mutating func remove(at leafIndex: UInt32) throws {
        guard leaf(at: leafIndex) != nil, memberCount > 1 else { throw MLSError.invalidTree }
        var candidate = self; try candidate.blankPath(leafIndex); candidate.nodes[Int(leafIndex) * 2] = nil
        while candidate.nodes.count > 1 {
            let root = candidate.leafCount - 1
            guard candidate.nodes[(root + 1)...].allSatisfy({ $0 == nil }) else { break }
            candidate.nodes = Array(candidate.nodes[..<root])
        }
        try candidate.validateStructure(); self = candidate
    }

    /// Authenticates every parent through exactly one signed descendant chain.
    /// - Throws: `invalidTree` for missing/ambiguous chains, incorrect parent hashes,
    ///   or unmerged-leaf inconsistencies. Leaf signatures must also be validated
    ///   independently with their group ID and leaf index before trusting the tree.
    public func validateParentHashes() throws {
        try validateStructure(); var authenticated: Set<UInt32> = []
        for index in nodes.indices where index & 1 == 0 {
            if case .leaf(let leaf) = nodes[index], leaf.source == .commit { authenticated.insert(UInt32(index)) }
        }
        let parents = nodes.indices.filter { $0 & 1 == 1 && nodes[$0] != nil }.sorted { MLSTreeMath.level(UInt32($0)) < MLSTreeMath.level(UInt32($1)) }
        for index in parents {
            guard case .parent(let parent) = nodes[index] else { throw MLSError.invalidTree }
            var count = 0
            for child in [try MLSTreeMath.left(UInt32(index)), try MLSTreeMath.right(UInt32(index))] {
                let sibling = try MLSTreeMath.sibling(child, leafCount: leafCount)
                let expected = try parentHash(parent, sibling: sibling)
                let resolved = try resolution(child)
                let unmerged = Set(parent.unmergedLeaves.filter { MLSTreeMath.contains($0 * 2, under: child) }.map { $0 * 2 })
                for descendant in resolved where authenticated.contains(descendant) {
                    let hash: Data?
                    switch nodes[Int(descendant)] {
                    case .leaf(let leaf): hash = leaf.parentHash
                    case .parent(let ancestor): hash = ancestor.parentHash
                    case nil: hash = nil
                    }
                    if hash == expected, Set(resolved.filter { $0 != descendant }) == unmerged { count += 1 }
                }
            }
            guard count == 1 else { throw MLSError.invalidTree }; authenticated.insert(UInt32(index))
        }
    }

    /// Generates fresh direct-path keys and signs the new leaf, staging the public tree.
    /// - Parameters:
    ///   - leafIndex: Existing committer's leaf index.
    ///   - leafEncryptionKey: Fresh HPKE public key; its private key is retained by the owner.
    ///   - signaturePrivateKey: Signing key matching the current leaf's signature key.
    ///   - groupID: Exact group identifier bound into the leaf signature.
    ///   - initialPathSecret: Fresh unpredictable 32-byte first path secret supplied by the owner.
    /// - Returns: Temporary sender secrets for HPKE, Welcome and epoch derivation.
    /// - Throws: Invalid tree/key/secret or signing errors. On any failure the tree
    ///   remains unchanged. No randomness or I/O is performed here.
    public mutating func prepareUpdate(leafIndex: UInt32, leafEncryptionKey: Data, signaturePrivateKey: Data,
                                      groupID: Data, initialPathSecret: Data) throws -> MLSGeneratedUpdate {
        guard let old = leaf(at: leafIndex), old.encryptionKey != leafEncryptionKey, initialPathSecret.count == 32 else { throw MLSError.invalidTree }
        let previousKeys = Set(nodes.indices.compactMap { encryptionKey(at: UInt32($0)) })
        guard !previousKeys.contains(leafEncryptionKey) else { throw MLSError.invalidTree }
        var candidate = self; let direct = try filteredDirectPath(for: leafIndex); try candidate.blankPath(leafIndex)
        var secret = initialPathSecret; var pathSecrets: [UInt32: Data] = [:]; var privateKeys: [UInt32: Data] = [:]; var publicKeys: [Data] = []
        for node in direct {
            let pair = try MLSCipherSuite2.deriveHPKEKeyPair(MLSCipherSuite2.deriveSecret(secret, label: "node"))
            guard !previousKeys.contains(pair.publicKey) else { throw MLSError.invalidTree }
            candidate.nodes[Int(node)] = .parent(try MLSParentNode(encryptionKey: pair.publicKey))
            pathSecrets[node] = secret; privateKeys[node] = pair.privateKey; publicKeys.append(pair.publicKey)
            secret = try MLSCipherSuite2.deriveSecret(secret, label: "path")
        }
        let hash = try candidate.installParentHashes(for: leafIndex)
        let leaf = try MLSLeafNode(encryptionKey: leafEncryptionKey, signatureKey: old.signatureKey, credential: old.credential,
                                   capabilities: old.capabilities, source: .commit, parentHash: hash, extensions: old.extensions)
            .signed(privateKey: signaturePrivateKey, groupID: groupID, leafIndex: leafIndex)
        try leaf.validate(now: 0, groupID: groupID, leafIndex: leafIndex, validateLifetime: false)
        candidate.nodes[Int(leafIndex) * 2] = .leaf(leaf); try candidate.validateStructure(); self = candidate
        return MLSGeneratedUpdate(leafNode: leaf, encryptionKeys: publicKeys, pathSecrets: pathSecrets, privateKeys: privateKeys, commitSecret: secret)
    }

    /// Encrypts a staged sender update after its provisional context has been computed.
    /// - Parameters:
    ///   - generated: Output from `prepareUpdate` for this exact tree.
    ///   - sender: Committer's leaf index.
    ///   - groupContext: Encoded provisional GroupContext, including new epoch/tree hash.
    ///   - excluding: Newly added leaf indices excluded from path ciphertext recipients.
    /// - Returns: RFC UpdatePath with ciphertexts in exact copath-resolution order.
    /// - Throws: `invalidTree` for mismatched staging, or HPKE/encoding errors.
    public func encryptUpdatePath(_ generated: MLSGeneratedUpdate, sender: UInt32, groupContext: Data,
                                  excluding: Set<UInt32> = []) throws -> MLSUpdatePath {
        let direct = try filteredDirectPath(for: sender)
        guard leaf(at: sender) == generated.leafNode, direct.count == generated.encryptionKeys.count else { throw MLSError.invalidTree }
        var result: [MLSUpdatePathNode] = []
        for (offset, node) in direct.enumerated() {
            guard let secret = generated.pathSecrets[node], encryptionKey(at: node) == generated.encryptionKeys[offset] else { throw MLSError.invalidTree }
            let sibling = try copathNode(for: node, sender: sender)
            let recipients = try resolution(sibling).filter { !excluding.contains($0 / 2) || $0 & 1 != 0 }
            let encrypted = try recipients.map { recipient in
                guard let key = encryptionKey(at: recipient) else { throw MLSError.invalidTree }
                return try MLSCipherSuite2.encryptWithLabel(publicKey: key, label: "UpdatePathNode", context: groupContext, plaintext: secret)
            }
            result.append(MLSUpdatePathNode(encryptionKey: generated.encryptionKeys[offset], encryptedPathSecrets: encrypted))
        }
        return MLSUpdatePath(leafNode: generated.leafNode, nodes: result)
    }

    /// Merges an authenticated commit's public path and verifies its leaf parent hash.
    /// - Parameters:
    ///   - path: Signed source-commit leaf and path public keys/ciphertexts.
    ///   - sender: Existing committer's leaf index after applying proposals.
    ///   - excluding: New members omitted from ciphertext recipients in this commit.
    /// - Throws: `invalidTree` for invalid source, unchanged key, shape, recipient
    ///   count, keys, or parent hash. A failed operation preserves the tree. Leaf
    ///   signature and authorization must be verified separately by the group owner.
    public mutating func mergeUpdatePath(_ path: MLSUpdatePath, sender: UInt32, excluding: Set<UInt32> = []) throws {
        guard let old = leaf(at: sender), path.leafNode.source == .commit, old.encryptionKey != path.leafNode.encryptionKey else { throw MLSError.invalidTree }
        // RFC 9420 section 12.4.2 checks against the post-proposal tree before
        // blanking the old path; checking only the final tree misses reused keys.
        let previousKeys = Set(nodes.indices.compactMap { encryptionKey(at: UInt32($0)) })
        let replacementKeys = [path.leafNode.encryptionKey] + path.nodes.map(\.encryptionKey)
        guard Set(replacementKeys).count == replacementKeys.count,
              replacementKeys.allSatisfy({ !previousKeys.contains($0) }) else { throw MLSError.invalidTree }
        let direct = try filteredDirectPath(for: sender)
        guard direct.count == path.nodes.count else { throw MLSError.invalidTree }
        var candidate = self; try candidate.blankPath(sender)
        for (node, update) in zip(direct, path.nodes) {
            let sibling = try copathNode(for: node, sender: sender)
            let recipients = try resolution(sibling).filter { !excluding.contains($0 / 2) || $0 & 1 != 0 }
            guard update.encryptedPathSecrets.count == recipients.count else { throw MLSError.invalidTree }
            candidate.nodes[Int(node)] = .parent(try MLSParentNode(encryptionKey: update.encryptionKey))
        }
        let expected = try candidate.installParentHashes(for: sender)
        guard path.leafNode.parentHash == expected else { throw MLSError.invalidTree }
        candidate.nodes[Int(sender) * 2] = .leaf(path.leafNode)
        try candidate.validateStructure(); self = candidate
    }

    /// Decrypts one copath ciphertext after public path merging, deriving/verifying ancestors.
    /// - Parameters:
    ///   - path: The same path already merged into this tree.
    ///   - sender: Committer's leaf index.
    ///   - groupContext: Exact provisional GroupContext encoded by the sender.
    ///   - privateKeys: Receiver-owned node-index to HPKE-private-key mapping from the
    ///     previous tree. Only matching resolution keys are attempted.
    ///   - excluding: New-member leaves excluded from ciphertext recipients.
    /// - Returns: Verified new ancestor keys, intermediate path secrets, and commit secret.
    /// - Throws: `invalidTree` for mismatched path/derived public keys, or
    ///   `authenticationFailed` when no receiver key decrypts. No state is changed;
    ///   owners must discard failed candidate trees and superseded private keys.
    public func decryptUpdatePath(_ path: MLSUpdatePath, sender: UInt32, groupContext: Data,
                                  privateKeys: [UInt32: Data], excluding: Set<UInt32> = []) throws -> MLSPathSecrets {
        let direct = try filteredDirectPath(for: sender)
        guard direct.count == path.nodes.count, leaf(at: sender) == path.leafNode else { throw MLSError.invalidTree }
        for (node, update) in zip(direct, path.nodes) {
            guard encryptionKey(at: node) == update.encryptionKey else { throw MLSError.invalidTree }
            let recipients = try resolution(copathNode(for: node, sender: sender)).filter { !excluding.contains($0 / 2) || $0 & 1 != 0 }
            guard recipients.count == update.encryptedPathSecrets.count else { throw MLSError.invalidTree }
            for (recipient, ciphertext) in zip(recipients, update.encryptedPathSecrets) {
                guard let key = privateKeys[recipient] else { continue }
                let secret = try MLSCipherSuite2.decryptWithLabel(privateKey: key, label: "UpdatePathNode", context: groupContext, encrypted: ciphertext)
                return try derivePathSecrets(secret, from: node, sender: sender)
            }
        }
        throw MLSError.authenticationFailed
    }

    /// Derives verified ancestor keys from a decrypted UpdatePath or Welcome path secret.
    /// - Parameters:
    ///   - secret: Exactly 32 bytes for the specified first shared path node.
    ///   - node: Node in the sender's filtered direct path, generally the joiner's
    ///     lowest common ancestor with the committer.
    ///   - sender: Committer's leaf index in this tree.
    /// - Returns: Keys/secrets for this node and higher filtered ancestors, plus commit secret.
    /// - Throws: `invalidTree` for invalid node/secret or any derived public-key mismatch.
    public func derivePathSecrets(_ secret: Data, from node: UInt32, sender: UInt32) throws -> MLSPathSecrets {
        let direct = try filteredDirectPath(for: sender)
        guard secret.count == 32, let start = direct.firstIndex(of: node) else { throw MLSError.invalidTree }
        var current = secret; var privateKeys: [UInt32: Data] = [:]; var secrets: [UInt32: Data] = [:]
        for parent in direct[start...] {
            let pair = try MLSCipherSuite2.deriveHPKEKeyPair(MLSCipherSuite2.deriveSecret(current, label: "node"))
            guard encryptionKey(at: parent) == pair.publicKey else { throw MLSError.invalidTree }
            privateKeys[parent] = pair.privateKey; secrets[parent] = current
            current = try MLSCipherSuite2.deriveSecret(current, label: "path")
        }
        return MLSPathSecrets(privateKeys: privateKeys, pathSecrets: secrets, commitSecret: current)
    }

    /// Retrieves public encryption bytes from an existing node without exposing private state.
    /// - Parameter node: Array index; out-of-tree or blank nodes return nil.
    /// - Returns: Leaf/parent HPKE public key, or nil.
    public func encryptionKey(at node: UInt32) -> Data? {
        guard node < nodes.count else { return nil }
        switch nodes[Int(node)] {
        case .leaf(let leaf): return leaf.encryptionKey
        case .parent(let parent): return parent.encryptionKey
        case nil: return nil
        }
    }

    /// Checks node placement, unique keys, member budgets and unmerged-leaf invariants.
    /// - Throws: `invalidTree` or `capacityExceeded`; does not verify signatures or hashes.
    private func validateStructure() throws {
        guard memberCount > 0 else { throw MLSError.invalidTree }
        guard memberCount <= maximumMembers else { throw MLSError.capacityExceeded }
        var encryptionKeys: Set<Data> = []; var signatures: Set<Data> = []
        for (index, node) in nodes.enumerated() {
            guard let node else { continue }
            switch node {
            case .leaf(let leaf):
                guard index & 1 == 0, encryptionKeys.insert(leaf.encryptionKey).inserted, signatures.insert(leaf.signatureKey).inserted else { throw MLSError.invalidTree }
            case .parent(let parent):
                guard index & 1 == 1, encryptionKeys.insert(parent.encryptionKey).inserted else { throw MLSError.invalidTree }
                for leaf in parent.unmergedLeaves {
                    guard self.leaf(at: leaf) != nil, MLSTreeMath.contains(leaf * 2, under: UInt32(index)) else { throw MLSError.invalidTree }
                    for ancestor in try MLSTreeMath.directPath(leaf * 2, leafCount: leafCount) {
                        if ancestor == index { break }
                        if case .parent(let value) = nodes[Int(ancestor)], !value.unmergedLeaves.contains(leaf) { throw MLSError.invalidTree }
                    }
                }
            }
        }
    }

    /// Blanks every parent on a leaf's direct path before proposal/path replacement.
    /// - Parameter leaf: Leaf index within capacity.
    /// - Throws: `invalidTree` for an out-of-capacity leaf.
    private mutating func blankPath(_ leaf: UInt32) throws {
        guard leaf < leafCount else { throw MLSError.invalidTree }
        for parent in try MLSTreeMath.directPath(leaf * 2, leafCount: leafCount) { nodes[Int(parent)] = nil }
    }

    /// Computes a subtree hash while virtually removing selected unmerged leaf positions.
    /// - Parameters:
    ///   - node: Valid subtree root.
    ///   - excluding: Leaves blanked and removed from parent unmerged lists for original-sibling hashes.
    /// - Returns: SHA-256 of the exact RFC TreeHashInput encoding.
    /// - Throws: Tree/encoding errors; recursion depth is at most sixteen.
    private func hash(_ node: UInt32, excluding: Set<UInt32>) throws -> Data {
        guard node < nodes.count else { throw MLSError.invalidTree }; var writer = MLSWriter()
        if node & 1 == 0 {
            writer.write(UInt8(1)); writer.write(node / 2)
            if case .leaf(let leaf) = nodes[Int(node)], !excluding.contains(node / 2) {
                writer.write(UInt8(1)); try writer.writeRaw(leaf.encoded())
            } else { writer.write(UInt8(0)) }
        } else {
            writer.write(UInt8(2))
            if case .parent(let parent) = nodes[Int(node)] {
                writer.write(UInt8(1))
                try writer.writeRaw(MLSParentNode(encryptionKey: parent.encryptionKey, parentHash: parent.parentHash,
                    unmergedLeaves: parent.unmergedLeaves.filter { !excluding.contains($0) }).encoded())
            } else { writer.write(UInt8(0)) }
            try writer.writeVector(hash(MLSTreeMath.left(node), excluding: excluding))
            try writer.writeVector(hash(MLSTreeMath.right(node), excluding: excluding))
        }
        return MLSCipherSuite2.hash(writer.data)
    }

    /// Computes the parent hash authenticated by a child in a selected orientation.
    /// - Parameters:
    ///   - parent: Populated parent whose encryption key and parent hash are included.
    ///   - sibling: Non-updated child subtree index.
    /// - Returns: SHA-256 ParentHashInput digest, including original sibling tree hash.
    /// - Throws: Tree/encoding errors for an invalid sibling or excessive input.
    private func parentHash(_ parent: MLSParentNode, sibling: UInt32) throws -> Data {
        var writer = MLSWriter(); try writer.writeVector(parent.encryptionKey); try writer.writeVector(parent.parentHash)
        try writer.writeVector(hash(sibling, excluding: Set(parent.unmergedLeaves))); return MLSCipherSuite2.hash(writer.data)
    }

    /// Finds the non-sender child at one ancestor of the sender.
    /// - Parameters:
    ///   - node: Parent on the sender's direct path.
    ///   - sender: Sender leaf index within capacity.
    /// - Returns: The child not containing the sender.
    /// - Throws: `invalidTree` when the supplied node does not contain the sender.
    private func copathNode(for node: UInt32, sender: UInt32) throws -> UInt32 {
        let left = try MLSTreeMath.left(node); let right = try MLSTreeMath.right(node)
        guard MLSTreeMath.contains(sender * 2, under: node) else { throw MLSError.invalidTree }
        return MLSTreeMath.contains(sender * 2, under: left) ? right : left
    }

    /// Chains freshly replaced parents from root to leaf and returns the leaf's parent hash.
    /// - Parameter leaf: Updating leaf whose ancestors were blanked/repopulated.
    /// - Returns: Hash for its signed commit leaf; empty for an empty filtered path.
    /// - Throws: Structural/encoding errors; only the candidate tree is mutated.
    private mutating func installParentHashes(for leaf: UInt32) throws -> Data {
        let direct = try filteredDirectPath(for: leaf); var hash = Data()
        for node in direct.reversed() {
            guard case .parent(let old) = nodes[Int(node)] else { throw MLSError.invalidTree }
            let parent = try MLSParentNode(encryptionKey: old.encryptionKey, parentHash: hash)
            nodes[Int(node)] = .parent(parent)
            hash = try parentHash(parent, sibling: copathNode(for: node, sender: leaf))
        }
        return hash
    }
}
