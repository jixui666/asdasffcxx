//
//  File.swift
//  SFI
//
//  Created by Mac on 2024/10/12.
//

import Foundation

struct SubscribeReponse: Codable {
    let data: SubscribeReponseClass?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case data, message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try? container.decode(SubscribeReponseClass.self, forKey: .data) {
            data = value
        } else {
            data = nil
        }
        message = container.decodeFlexibleStringIfPresent(forKey: .message)
    }
}

struct SubscribeReponseClass: Codable {
    let planID: Int?
    let token: String
    let u, d, transferEnable: Int
    let email, uuid: String
    let plan: Plan?
    let subscribeURL: String

    enum CodingKeys: String, CodingKey {
        case planID = "plan_id"
        case token, u, d
        case transferEnable = "transfer_enable"
        case email, uuid, plan
        case subscribeURL = "subscribe_url"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        planID = container.decodeFlexibleIntIfPresent(forKey: .planID)
        token = container.decodeFlexibleStringIfPresent(forKey: .token) ?? ""
        u = container.decodeFlexibleIntIfPresent(forKey: .u) ?? 0
        d = container.decodeFlexibleIntIfPresent(forKey: .d) ?? 0
        transferEnable = container.decodeFlexibleIntIfPresent(forKey: .transferEnable) ?? 0
        email = container.decodeFlexibleStringIfPresent(forKey: .email) ?? ""
        uuid = container.decodeFlexibleStringIfPresent(forKey: .uuid) ?? ""
        if let decodedPlan = try? container.decode(Plan.self, forKey: .plan) {
            plan = decodedPlan
        } else {
            plan = nil
        }
        subscribeURL = container.decodeFlexibleStringIfPresent(forKey: .subscribeURL) ?? ""
    }
}

struct Plan: Codable {
    let id, groupID: Int
    let name: String
    let show, renew: Int
    let content: String?
    let monthPrice, quarterPrice, halfYearPrice, yearPrice: Int?
    let onetimePrice: Int?
    let createdAt, updatedAt: Int

    enum CodingKeys: String, CodingKey {
        case id
        case groupID = "group_id"
        case name, show, renew, content
        case monthPrice = "month_price"
        case quarterPrice = "quarter_price"
        case halfYearPrice = "half_year_price"
        case yearPrice = "year_price"
        case onetimePrice = "onetime_price"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeFlexibleIntIfPresent(forKey: .id) ?? 0
        groupID = container.decodeFlexibleIntIfPresent(forKey: .groupID) ?? 0
        name = container.decodeFlexibleStringIfPresent(forKey: .name) ?? ""
        show = container.decodeFlexibleIntIfPresent(forKey: .show) ?? 0
        renew = container.decodeFlexibleIntIfPresent(forKey: .renew) ?? 0
        content = container.decodeFlexibleStringIfPresent(forKey: .content)
        monthPrice = container.decodeFlexibleIntIfPresent(forKey: .monthPrice)
        quarterPrice = container.decodeFlexibleIntIfPresent(forKey: .quarterPrice)
        halfYearPrice = container.decodeFlexibleIntIfPresent(forKey: .halfYearPrice)
        yearPrice = container.decodeFlexibleIntIfPresent(forKey: .yearPrice)
        onetimePrice = container.decodeFlexibleIntIfPresent(forKey: .onetimePrice)
        createdAt = container.decodeFlexibleIntIfPresent(forKey: .createdAt) ?? 0
        updatedAt = container.decodeFlexibleIntIfPresent(forKey: .updatedAt) ?? 0
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleIntIfPresent(forKey key: Key) -> Int? {
        guard contains(key), (try? decodeNil(forKey: key)) != true else { return nil }
        if let value = try? decode(Int.self, forKey: key) { return value }
        if let value = try? decode(Bool.self, forKey: key) { return value ? 1 : 0 }
        if let value = try? decode(String.self, forKey: key) {
            if let integer = Int(value) { return integer }
            if let double = Double(value), double.isFinite, double.rounded(.towardZero) == double {
                return Int(exactly: double)
            }
        }
        if let value = try? decode(Double.self, forKey: key), value.isFinite, value.rounded(.towardZero) == value {
            return Int(exactly: value)
        }
        return nil
    }

    func decodeFlexibleStringIfPresent(forKey key: Key) -> String? {
        guard contains(key), (try? decodeNil(forKey: key)) != true else { return nil }
        if let value = try? decode(String.self, forKey: key) { return value }
        if let value = try? decode(Int.self, forKey: key) { return String(value) }
        if let value = try? decode(Double.self, forKey: key) { return String(value) }
        if let value = try? decode(Bool.self, forKey: key) { return value ? "true" : "false" }
        return nil
    }
}
