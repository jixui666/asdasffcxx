//
//  PlanResponse.swift
//  SFI
//
//  Created by Mac on 2024/10/12.
//

import Foundation



// MARK: - Welcome
struct PlanResponse: Codable {
    let data: [DatuPlanResponse]?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case data, message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // A malformed item should not prevent the response message from being shown.
        data = try? container.decodeIfPresent([DatuPlanResponse].self, forKey: .data)
        message = container.decodeFlexibleStringIfPresent(forKey: .message)
    }
}

// MARK: - Datum
struct DatuPlanResponse: Codable,Identifiable {
    var id  = UUID()    
    let idOLD, groupID, transferEnable: Int?
    let name: String
    let deviceLimit: Int?
    let show: Int?
    let renew: Int?
    let content: String?
    let monthPrice, quarterPrice, halfYearPrice, yearPrice: Int?
    let onetimePrice: Int?
    let createdAt, updatedAt: Int?

    enum CodingKeys: String, CodingKey {
        case idOLD = "id"
        case groupID = "group_id"
        case transferEnable = "transfer_enable"
        case name
        case deviceLimit = "device_limit"
        case show,  renew, content
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

        id = UUID()
        idOLD = container.decodeFlexibleIntIfPresent(forKey: .idOLD)
        groupID = container.decodeFlexibleIntIfPresent(forKey: .groupID)
        transferEnable = container.decodeFlexibleIntIfPresent(forKey: .transferEnable)
        name = container.decodeFlexibleStringIfPresent(forKey: .name) ?? ""
        deviceLimit = container.decodeFlexibleIntIfPresent(forKey: .deviceLimit)
        show = container.decodeIntOrBoolIfPresent(forKey: .show)
        renew = container.decodeIntOrBoolIfPresent(forKey: .renew)
        content = container.decodeFlexibleStringIfPresent(forKey: .content)
        monthPrice = container.decodeFlexibleIntIfPresent(forKey: .monthPrice)
        quarterPrice = container.decodeFlexibleIntIfPresent(forKey: .quarterPrice)
        halfYearPrice = container.decodeFlexibleIntIfPresent(forKey: .halfYearPrice)
        yearPrice = container.decodeFlexibleIntIfPresent(forKey: .yearPrice)
        onetimePrice = container.decodeFlexibleIntIfPresent(forKey: .onetimePrice)
        createdAt = container.decodeFlexibleIntIfPresent(forKey: .createdAt)
        updatedAt = container.decodeFlexibleIntIfPresent(forKey: .updatedAt)
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleIntIfPresent(forKey key: Key) -> Int? {
        guard contains(key), (try? decodeNil(forKey: key)) != true else { return nil }

        if let value = try? decode(Int.self, forKey: key) {
            return value
        }
        if let value = try? decode(Bool.self, forKey: key) {
            return value ? 1 : 0
        }
        if let value = try? decode(String.self, forKey: key) {
            if let integer = Int(value) {
                return integer
            }
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

    func decodeIntOrBoolIfPresent(forKey key: Key) -> Int? {
        decodeFlexibleIntIfPresent(forKey: key)
    }
}
