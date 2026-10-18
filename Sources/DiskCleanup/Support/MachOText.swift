//
//  MachOText.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//
//  Which CPUs a binary is built for, from its first bytes: a fat header
//  lists its slices, a thin one names its one CPU. No lipo needed.
//

import Foundation

enum MachOText {

    static func name(_ cpu: UInt32) -> String {
        switch cpu {
        case 0x0100_000C: return "arm64"
        case 0x0100_0007: return "x86_64"
        case 0x0000_0007: return "i386"
        case 0x0000_0012: return "ppc"
        case 0x0000_000C: return "arm"
        default: return String(format: "cpu-0x%x", cpu)
        }
    }

    /// The architectures, or `nil` when `data` is not a Mach-O binary.
    static func architectures(_ data: Data) -> [String]? {
        guard data.count >= 8 else { return nil }
        func big(_ offset: Int) -> UInt32 { data.withUnsafeBytes { UInt32(bigEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self)) } }
        func little(_ offset: Int) -> UInt32 { data.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self)) } }
        switch big(0) {
        case 0xCAFE_BABE, 0xCAFE_BABF:
            let count = Int(big(4))
            let stride = big(0) == 0xCAFE_BABF ? 32 : 20
            guard count > 0, count < 32, data.count >= 8 + count * stride else { return nil }
            return (0..<count).map { name(big(8 + $0 * stride)) }
        default:
            let magic = little(0)
            guard magic == 0xFEED_FACF || magic == 0xFEED_FACE else { return nil }
            return [name(little(4))]
        }
    }
}
