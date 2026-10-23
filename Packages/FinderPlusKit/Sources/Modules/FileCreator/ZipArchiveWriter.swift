import Foundation

/// Minimal ZIP writer (stored entries, no compression) — enough for Office Open XML packages,
/// without pulling in a compression dependency.
struct ZipArchiveWriter {
    private struct Entry {
        var name: Data
        var crc: UInt32
        var size: UInt32
        var offset: UInt32
    }

    private var output = Data()
    private var entries: [Entry] = []
    private let dosTime: UInt16
    private let dosDate: UInt16

    init(date: Date = Date()) {
        let components = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = max((components.year ?? 1980) - 1980, 0)
        dosDate = UInt16(truncatingIfNeeded: (year << 9) | ((components.month ?? 1) << 5) | (components.day ?? 1))
        dosTime = UInt16(truncatingIfNeeded: ((components.hour ?? 0) << 11) | ((components.minute ?? 0) << 5) | ((components.second ?? 0) / 2))
    }

    mutating func add(_ path: String, _ contents: String) {
        add(path, Data(contents.utf8))
    }

    mutating func add(_ path: String, _ data: Data) {
        let name = Data(path.utf8)
        let crc = CRC32.checksum(data)
        let entry = Entry(name: name, crc: crc, size: UInt32(data.count), offset: UInt32(output.count))

        output.append(uint32: 0x0403_4B50)   // local file header signature
        output.append(uint16: 20)            // version needed to extract
        output.append(uint16: 0x0800)        // flags: UTF-8 file names
        output.append(uint16: 0)             // method: stored
        output.append(uint16: dosTime)
        output.append(uint16: dosDate)
        output.append(uint32: crc)
        output.append(uint32: entry.size)    // compressed size
        output.append(uint32: entry.size)    // uncompressed size
        output.append(uint16: UInt16(name.count))
        output.append(uint16: 0)             // extra field length
        output.append(name)
        output.append(data)

        entries.append(entry)
    }

    func finalized() -> Data {
        var archive = output
        let directoryOffset = UInt32(archive.count)
        for entry in entries {
            archive.append(uint32: 0x0201_4B50)  // central directory header signature
            archive.append(uint16: 20)           // version made by
            archive.append(uint16: 20)           // version needed
            archive.append(uint16: 0x0800)
            archive.append(uint16: 0)
            archive.append(uint16: dosTime)
            archive.append(uint16: dosDate)
            archive.append(uint32: entry.crc)
            archive.append(uint32: entry.size)
            archive.append(uint32: entry.size)
            archive.append(uint16: UInt16(entry.name.count))
            archive.append(uint16: 0)            // extra
            archive.append(uint16: 0)            // comment
            archive.append(uint16: 0)            // disk number start
            archive.append(uint16: 0)            // internal attributes
            archive.append(uint32: 0)            // external attributes
            archive.append(uint32: entry.offset)
            archive.append(entry.name)
        }
        let directorySize = UInt32(archive.count) - directoryOffset
        archive.append(uint32: 0x0605_4B50)      // end of central directory
        archive.append(uint16: 0)
        archive.append(uint16: 0)
        archive.append(uint16: UInt16(entries.count))
        archive.append(uint16: UInt16(entries.count))
        archive.append(uint32: directorySize)
        archive.append(uint32: directoryOffset)
        archive.append(uint16: 0)
        return archive
    }
}

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { index -> UInt32 in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = (value & 1) == 1 ? (0xEDB8_8320 ^ (value >> 1)) : (value >> 1)
        }
        return value
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}

extension Data {
    mutating func append(uint16 value: UInt16) {
        append(contentsOf: [UInt8(value & 0xFF), UInt8(value >> 8)])
    }

    mutating func append(uint32 value: UInt32) {
        append(contentsOf: [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8(value >> 24)])
    }
}
