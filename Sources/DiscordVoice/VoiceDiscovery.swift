// File: Sources/DiscordVoice/VoiceDiscovery.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Foundation
import DiscordTransport

/// Stateless Voice Gateway v8 UDP address-discovery codec; sockets remain caller-owned.
public enum VoiceDiscovery {
    /// Encodes the current 74-byte IP-discovery request from Discord's voice reference.
    /// - Parameter ssrc: SSRC assigned by Voice Ready; copied into the response by the server.
    /// - Returns: Type 1, body length 70, SSRC, zero address field and zero port in network order.
    public static func request(ssrc: UInt32) -> Data {
        var bytes = [UInt8](repeating: 0, count: 74)
        bytes[1] = 1
        bytes[3] = 70
        for offset in 0..<4 { bytes[4 + offset] = UInt8(truncatingIfNeeded: ssrc >> ((3 - offset) * 8)) }
        return Data(bytes)
    }

    /// Parses a complete discovery response without trusting arbitrary hosts or trailing bytes.
    /// - Parameters:
    ///   - data: Exactly 74 bytes: type 2, length 70, matching SSRC, NUL-terminated
    ///     ASCII IP literal and nonzero network-order UDP port. IPv4 and IPv6 text are accepted.
    ///   - ssrc: Expected negotiated SSRC; a different SSRC is rejected.
    /// - Returns: External address advertised by the server. The caller must also
    ///   validate the UDP peer against its negotiated server before using this value.
    /// - Throws: `VoicePacketError.malformedPacket` for malformed framing, address or port;
    ///   `.wrongStream` for a response to another SSRC. No DNS or I/O is performed.
    public static func response(_ data: Data, ssrc: UInt32) throws -> DatagramAddress {
        guard data.count == 74 else { throw VoicePacketError.malformedPacket }
        let bytes = Array(data)
        guard bytes[0...3].elementsEqual([0, 2, 0, 70]) else { throw VoicePacketError.malformedPacket }
        let actual = bytes[4..<8].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        guard actual == ssrc else { throw VoicePacketError.wrongStream }
        let addressBytes = bytes[8..<72]
        guard let end = addressBytes.firstIndex(of: 0), end > 8,
              let address = String(bytes: bytes[8..<end], encoding: .ascii), isIPLiteral(address) else {
            throw VoicePacketError.malformedPacket
        }
        let port = UInt16(bytes[72]) << 8 | UInt16(bytes[73])
        guard port != 0 else { throw VoicePacketError.malformedPacket }
        return DatagramAddress(host: address, port: port)
    }

    /// Validates IP syntax without platform socket APIs or name resolution.
    /// - Parameter value: Nonempty ASCII text extracted from the fixed discovery address field.
    /// - Returns: True for dotted decimal IPv4 or RFC 4291 IPv6 (including embedded IPv4);
    ///   scope identifiers, hostnames and ambiguous leading-zero IPv4 octets are rejected.
    private static func isIPLiteral(_ value: String) -> Bool {
        if !value.contains(":") {
            let parts = value.split(separator: ".", omittingEmptySubsequences: false)
            return parts.count == 4 && parts.allSatisfy {
                !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } && ($0.count == 1 || $0.first != "0") && UInt8($0) != nil
            }
        }
        guard !value.contains("%"), !value.contains(":::"), value.filter({ $0 == ":" }).count >= 2,
              value.first != ":" || value.hasPrefix("::"),
              value.last != ":" || value.hasSuffix("::") else { return false }
        let compressed = value.components(separatedBy: "::")
        guard compressed.count <= 2 else { return false }
        let groups = value.split(separator: ":", omittingEmptySubsequences: true)
        var words = 0
        for (index, group) in groups.enumerated() {
            if group.contains(".") {
                guard index == groups.count - 1, value.hasSuffix(group), isIPLiteral(String(group)) else { return false }
                words += 2
            } else {
                guard (1...4).contains(group.count), group.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return false }
                words += 1
            }
        }
        if compressed.count == 2 { return words < 8 }
        return words == 8 && value.first != ":" && value.last != ":"
    }
}
