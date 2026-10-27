import Foundation

func encodeToDict<T: Encodable>(_ value: T) throws -> [String: Any] {
    let data = try JSONEncoder().encode(value)
    return try JSONSerialization.jsonObject(with: data) as! [String: Any]
}

struct TestError: Error {}
