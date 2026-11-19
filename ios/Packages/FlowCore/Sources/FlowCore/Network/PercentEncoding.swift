import Foundation

/// Кодирование строк в `%XX` в произвольной кодировке.
/// Рутрекер принимает формы в windows-1251, поэтому стандартного `URLComponents` недостаточно.
enum PercentEncoding {
    private static let unreserved = Set(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~".utf8
    )

    static func encode(_ string: String, encoding: String.Encoding, spaceAsPlus: Bool) -> String {
        let data = string.data(using: encoding, allowLossyConversion: true) ?? Data(string.utf8)
        var out = ""
        out.reserveCapacity(data.count * 3)
        for byte in data {
            if unreserved.contains(byte) {
                out.unicodeScalars.append(UnicodeScalar(byte))
            } else if byte == 0x20 && spaceAsPlus {
                out.append("+")
            } else {
                out += String(format: "%%%02X", UInt32(byte))
            }
        }
        return out
    }

    /// Тело `application/x-www-form-urlencoded`.
    static func formBody(_ pairs: [(String, String)], encoding: String.Encoding = .windowsCP1251) -> Data {
        let body = pairs
            .map { pair in
                let key = encode(pair.0, encoding: encoding, spaceAsPlus: true)
                let value = encode(pair.1, encoding: encoding, spaceAsPlus: true)
                return "\(key)=\(value)"
            }
            .joined(separator: "&")
        return Data(body.utf8)
    }
}

enum TextDecoding {
    /// Рутрекер отдаёт страницы в windows-1251, если в заголовке не указано иное.
    static func decode(_ data: Data, contentType: String?) -> String {
        let declared = contentType?.lowercased() ?? ""
        if declared.contains("utf-8") || declared.contains("utf8") {
            return String(decoding: data, as: UTF8.self)
        }
        return String(data: data, encoding: .windowsCP1251) ?? String(decoding: data, as: UTF8.self)
    }
}
