import Foundation

/// Pure-Swift JSPB-to-Protobuf encoder (exact port of internal/gemini/channel.go:encodeJSPB),
/// plus WebChannel incremental balanced-JSON frame splitter and batchexecute record scanner.
enum JSPBEncoder {
    enum Value {
        case null
        case int(Int64)
        case string(String)
        case packedInts([Int])
        case array([Value])
    }

    static func encode(_ values: [Value]) -> Data {
        var out = Data()
        for (index, val) in values.enumerated() {
            let fieldNumber = UInt64(index + 1)
            switch val {
            case .null:
                continue
            case .int(let n):
                appendTag(&out, field: fieldNumber, wireType: 0)
                appendVarint(&out, UInt64(bitPattern: n))
            case .string(let s):
                let bytes = Data(s.utf8)
                appendTag(&out, field: fieldNumber, wireType: 2)
                appendVarint(&out, UInt64(bytes.count))
                out.append(bytes)
            case .packedInts(let ints):
                var packed = Data()
                for n in ints {
                    appendVarint(&packed, UInt64(bitPattern: Int64(n)))
                }
                appendTag(&out, field: fieldNumber, wireType: 2)
                appendVarint(&out, UInt64(packed.count))
                out.append(packed)
            case .array(let nested):
                let nestedData = encode(nested)
                appendTag(&out, field: fieldNumber, wireType: 2)
                appendVarint(&out, UInt64(nestedData.count))
                out.append(nestedData)
            }
        }
        return out
    }

    private static func appendTag(_ out: inout Data, field: UInt64, wireType: UInt64) {
        appendVarint(&out, (field << 3) | wireType)
    }

    private static func appendVarint(_ out: inout Data, _ value: UInt64) {
        var v = value
        while true {
            var byte = UInt8(v & 0x7F)
            v >>= 7
            if v != 0 {
                byte |= 0x80
                out.append(byte)
            } else {
                out.append(byte)
                break
            }
        }
    }
}

/// Encodes JSON without escaping `/` (matches JS JSON.stringify) and URL-encodes like `encodeURIComponent`.
enum GeminiEncoding {
    private static let uriAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-_.!~*'()")
        return set
    }()

    static func encodeURIComponent(_ str: String) -> String {
        return str.addingPercentEncoding(withAllowedCharacters: uriAllowed) ?? str
    }

    static func pageJSON(_ obj: Any) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: []),
              var str = String(data: data, encoding: .utf8) else { return nil }
        // JSONSerialization escapes `/` as `\/`, revert to match JS JSON.stringify
        str = str.replacingOccurrences(of: "\\/", with: "/")
        return str
    }

    static func protocolForm(fReq: String, atToken: String) -> String {
        var form = "f.req=\(encodeURIComponent(fReq))&"
        if !atToken.isEmpty {
            form += "at=\(encodeURIComponent(atToken))&"
        }
        return form
    }

    static func randomZX() -> String {
        let a = UInt32.random(in: 0..<(1 << 31))
        let b = UInt32.random(in: 0..<(1 << 31))
        let ms = UInt32(truncatingIfNeeded: Int64(Date().timeIntervalSince1970 * 1000))
        let mixed = Int64(abs(Int32(bitPattern: b ^ ms)))
        return String(a, radix: 36) + String(mixed, radix: 36)
    }

    static func randomContextID() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<16 { bytes[i] = UInt8.random(in: 0...255) }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}

/// Incremental streaming parser for Google WebChannel `length\n[[id, payload],...]` frames.
/// Note: WebChannel concatenates the next decimal length immediately after `]` with NO separator newline.
/// This scanner extracts balanced JSON arrays `[...]` across arbitrary TCP/URLSession data chunks.
final class WebChannelFrameParser {
    private var buffer = Data()

    func append(_ data: Data) -> [Data] {
        buffer.append(data)
        var frames: [Data] = []
        let bytes = [UInt8](buffer)
        var pos = 0
        let count = bytes.count

        while pos < count {
            // Skip digits, whitespace, newlines until '['
            while pos < count && bytes[pos] != 0x5B /* '[' */ {
                pos += 1
            }
            if pos >= count { break }

            // Scan balanced JSON array from pos
            let start = pos
            var depth = 0
            var inString = false
            var escaped = false
            var end: Int? = nil

            var i = start
            while i < count {
                let c = bytes[i]
                if inString {
                    if escaped {
                        escaped = false
                    } else if c == 0x5C /* '\\' */ {
                        escaped = true
                    } else if c == 0x22 /* '"' */ {
                        inString = false
                    }
                } else {
                    if c == 0x22 /* '"' */ {
                        inString = true
                    } else if c == 0x5B /* '[' */ || c == 0x7B /* '{' */ {
                        depth += 1
                    } else if c == 0x5D /* ']' */ || c == 0x7D /* '}' */ {
                        depth -= 1
                        if depth == 0 {
                            end = i + 1
                            break
                        }
                    }
                }
                i += 1
            }

            if let e = end {
                frames.append(Data(bytes[start..<e]))
                pos = e
            } else {
                // Incomplete JSON frame; retain from `start` for next chunk
                buffer = Data(bytes[start..<count])
                return frames
            }
        }

        if pos > 0 {
            if pos >= count {
                buffer.removeAll(keepingCapacity: true)
            } else {
                buffer = Data(bytes[pos..<count])
            }
        }
        return frames
    }
}

/// Parses `)]}'` batchexecute / ProcessFile responses into `wrb.fr` records.
enum BatchExecuteParser {
    static func extractRecords(from data: Data) -> [[Any]] {
        guard var text = String(data: data, encoding: .utf8) else { return [] }
        if text.hasPrefix(")]}'") {
            text = String(text.dropFirst(4))
        }
        var results: [[Any]] = []
        let parser = WebChannelFrameParser()
        for frameData in parser.append(Data(text.utf8)) {
            guard let arr = (try? JSONSerialization.jsonObject(with: frameData)) as? [Any] else { continue }
            for item in arr {
                if let rec = item as? [Any] {
                    results.append(rec)
                }
            }
        }
        return results
    }
}
