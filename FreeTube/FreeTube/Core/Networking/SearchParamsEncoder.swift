import Foundation

/// InnerTube search `params` protobuf (sort + nested filters). Nil when all defaults.
enum SearchParamsEncoder {
    static func encode(
        sort: SearchVideoFilters.Sort,
        resultType: SearchVideoFilters.ResultType,
        uploaded: SearchVideoFilters.Uploaded,
        length: SearchVideoFilters.Length
    ) -> String? {
        var nested = Data()
        if let uploadedValue = uploaded.serverValue {
            nested.append(varintField: 1, value: uploadedValue)
        }
        if let typeValue = resultType.serverValue {
            nested.append(varintField: 2, value: typeValue)
        }
        if let lengthValue = length.serverValue {
            nested.append(varintField: 3, value: lengthValue)
        }

        var message = Data()
        if let sortValue = sort.serverValue {
            message.append(varintField: 1, value: sortValue)
        }
        if !nested.isEmpty {
            message.append(lengthDelimitedField: 2, value: nested)
        }
        guard !message.isEmpty else { return nil }
        return message.base64EncodedString()
    }
}

private extension Data {
    mutating func append(varintField fieldNumber: Int, value: Int) {
        append(protobufKey(fieldNumber: fieldNumber, wireType: 0))
        append(varint: UInt64(value))
    }

    mutating func append(lengthDelimitedField fieldNumber: Int, value: Data) {
        append(protobufKey(fieldNumber: fieldNumber, wireType: 2))
        append(varint: UInt64(value.count))
        append(value)
    }

    mutating func append(varint value: UInt64) {
        var current = value
        repeat {
            var byte = UInt8(current & 0x7F)
            current >>= 7
            if current != 0 { byte |= 0x80 }
            append(byte)
        } while current != 0
    }

    func protobufKey(fieldNumber: Int, wireType: Int) -> UInt8 {
        UInt8((fieldNumber << 3) | wireType)
    }
}
