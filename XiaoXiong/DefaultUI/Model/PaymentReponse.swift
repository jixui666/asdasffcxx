//
//  PaymentReponse.swift
//  SFI
//
//  Created by Mac on 2024/10/21.
//

import Foundation

// MARK: - PaymentReponse
struct PaymentReponse: Codable {
    let status, message: String?
    let data: [PaymentReponseDatum]?

    private enum CodingKeys: String, CodingKey {
        case status, message, data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = container.decodePaymentStringIfPresent(forKey: .status)
        message = container.decodePaymentStringIfPresent(forKey: .message)
        data = try? container.decodeIfPresent([PaymentReponseDatum].self, forKey: .data)
    }
}

// MARK: - Datum
struct PaymentReponseDatum: Codable {
    let id: Int
    let name, payment: String
    let icon,handlingFeePercent,handlingFeeFixed: String?

    enum CodingKeys: String, CodingKey {
        case id, name, payment, icon
        case handlingFeeFixed = "handling_fee_fixed"
        case handlingFeePercent = "handling_fee_percent"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodePaymentIntIfPresent(forKey: .id) ?? 0
        name = container.decodePaymentStringIfPresent(forKey: .name) ?? ""
        payment = container.decodePaymentStringIfPresent(forKey: .payment) ?? ""
        icon = container.decodePaymentStringIfPresent(forKey: .icon)
        handlingFeePercent = container.decodePaymentStringIfPresent(forKey: .handlingFeePercent)
        handlingFeeFixed = container.decodePaymentStringIfPresent(forKey: .handlingFeeFixed)
    }
}

private extension KeyedDecodingContainer {
    func decodePaymentIntIfPresent(forKey key: Key) -> Int? {
        guard contains(key), (try? decodeNil(forKey: key)) != true else { return nil }
        if let value = try? decode(Int.self, forKey: key) { return value }
        if let value = try? decode(String.self, forKey: key) {
            return Int(value) ?? (Double(value).flatMap(Int.init(exactly:)))
        }
        if let value = try? decode(Double.self, forKey: key), value.isFinite {
            return Int(exactly: value)
        }
        if let value = try? decode(Bool.self, forKey: key) { return value ? 1 : 0 }
        return nil
    }

    func decodePaymentStringIfPresent(forKey key: Key) -> String? {
        guard contains(key), (try? decodeNil(forKey: key)) != true else { return nil }
        if let value = try? decode(String.self, forKey: key) { return value }
        if let value = try? decode(Int.self, forKey: key) { return String(value) }
        if let value = try? decode(Double.self, forKey: key) { return String(value) }
        if let value = try? decode(Bool.self, forKey: key) { return value ? "true" : "false" }
        return nil
    }
}

