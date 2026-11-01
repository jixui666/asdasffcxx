//
//  File.swift
//  SFI
//
//  Created by Mac on 2024/10/21.
//

import Foundation

struct OrderInfoReponse: Codable {
    let status, message: String?
    let data: [OrderInfoDatum]?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ResponseCodingKeys.self)
        status = container.decodeOrderStringIfPresent(forKey: .status)
        message = container.decodeOrderStringIfPresent(forKey: .message)
        data = try container.decodeIfPresent([OrderInfoDatum].self, forKey: .data)
    }
}

struct OrderInfoSingleReponse: Codable {
    let status, message: String?
    let data: OrderInfoDatum?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ResponseCodingKeys.self)
        status = container.decodeOrderStringIfPresent(forKey: .status)
        message = container.decodeOrderStringIfPresent(forKey: .message)
        data = try container.decodeIfPresent(OrderInfoDatum.self, forKey: .data)
    }
}

private enum ResponseCodingKeys: String, CodingKey {
    case status, message, data
}

struct OrderInfoDatum: Codable, Identifiable {
    var id = UUID().uuidString
    let inviteUserID: String?
    let planID: Int?
    let siteID, couponID: String?
    let type: Int
    let period: String
    let couponCode: String?
    let tradeNo: String
    let callbackNo: String?
    let totalAmount: Double
    let handlingAmount, discountAmount, surplusAmount, refundAmount: Double?
    let balanceAmount: Double?
    let paymentID: Int?
    let status: Int
    let createdAt, updatedAt: Int
    let commissionStatus, commissionBalance: Int?
    let tixianstatus: String?
    let plan: PlanOrder

    var status_zh: String {
        switch status {
        case 0: return "待支付"
        case 1, 3: return "已支付"
        case 2: return "已取消"
        default: return "未知"
        }
    }

    var period_zh: String {
        switch period {
        case "month_price": return "月付"
        case "quarter_price": return "季付"
        case "half_year_price": return "半年付"
        case "year_price": return "年付"
        case "two_year_price": return "两年付"
        case "three_year_price": return "三年付"
        case "onetime_price": return "一次性付"
        default: return period.isEmpty ? "月付" : period
        }
    }

    private enum CodingKeys: String, CodingKey {
        case inviteUserID = "invite_user_id"
        case planID = "plan_id"
        case siteID = "site_id"
        case couponID = "coupon_id"
        case paymentID = "payment_id"
        case type, period
        case couponCode = "coupon_code"
        case tradeNo = "trade_no"
        case callbackNo = "callback_no"
        case totalAmount = "total_amount"
        case handlingAmount = "handling_amount"
        case discountAmount = "discount_amount"
        case surplusAmount = "surplus_amount"
        case refundAmount = "refund_amount"
        case balanceAmount = "balance_amount"
        case status
        case commissionStatus = "commission_status"
        case commissionBalance = "commission_balance"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case tixianstatus, plan
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = UUID().uuidString
        inviteUserID = container.decodeOrderStringIfPresent(forKey: .inviteUserID)
        planID = container.decodeOrderIntIfPresent(forKey: .planID)
        siteID = container.decodeOrderStringIfPresent(forKey: .siteID)
        couponID = container.decodeOrderStringIfPresent(forKey: .couponID)
        type = container.decodeOrderIntIfPresent(forKey: .type) ?? 0
        period = container.decodeOrderStringIfPresent(forKey: .period) ?? ""
        couponCode = container.decodeOrderStringIfPresent(forKey: .couponCode)
        tradeNo = container.decodeOrderStringIfPresent(forKey: .tradeNo) ?? ""
        callbackNo = container.decodeOrderStringIfPresent(forKey: .callbackNo)
        totalAmount = container.decodeOrderDoubleIfPresent(forKey: .totalAmount) ?? 0
        handlingAmount = container.decodeOrderDoubleIfPresent(forKey: .handlingAmount)
        discountAmount = container.decodeOrderDoubleIfPresent(forKey: .discountAmount)
        surplusAmount = container.decodeOrderDoubleIfPresent(forKey: .surplusAmount)
        refundAmount = container.decodeOrderDoubleIfPresent(forKey: .refundAmount)
        balanceAmount = container.decodeOrderDoubleIfPresent(forKey: .balanceAmount)
        paymentID = container.decodeOrderIntIfPresent(forKey: .paymentID)
        // A missing or malformed status is unknown, not pending payment.
        status = container.decodeOrderIntIfPresent(forKey: .status) ?? -1
        createdAt = container.decodeOrderIntIfPresent(forKey: .createdAt) ?? 0
        updatedAt = container.decodeOrderIntIfPresent(forKey: .updatedAt) ?? 0
        commissionStatus = container.decodeOrderIntIfPresent(forKey: .commissionStatus)
        commissionBalance = container.decodeOrderIntIfPresent(forKey: .commissionBalance)
        tixianstatus = container.decodeOrderStringIfPresent(forKey: .tixianstatus)
        // Some server responses omit the plan or return it as null. A malformed
        // plan should not make the whole order list fail to decode.
        plan = (try? container.decodeIfPresent(PlanOrder.self, forKey: .plan)) ?? .empty
    }
}

struct PlanOrder: Codable {
    let id: Int
    let name: String
    let speedLimit: Int?
    let show, sort, renew, groupID, transferEnable: Int?
    let content: String
    let monthPrice, quarterPrice, halfYearPrice, yearPrice: Int?
    let twoYearPrice, threeYearPrice, onetimePrice, resetPrice: Double?
    let resetTrafficMethod: String?
    let capacityLimit: Int?
    let createdAt, updatedAt: Int

    static let empty = PlanOrder()

    private init() {
        id = 0
        name = ""
        speedLimit = nil
        show = nil
        sort = nil
        renew = nil
        groupID = nil
        transferEnable = nil
        content = ""
        monthPrice = nil
        quarterPrice = nil
        halfYearPrice = nil
        yearPrice = nil
        twoYearPrice = nil
        threeYearPrice = nil
        onetimePrice = nil
        resetPrice = nil
        resetTrafficMethod = nil
        capacityLimit = nil
        createdAt = 0
        updatedAt = 0
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case groupID = "group_id"
        case transferEnable = "transfer_enable"
        case name
        case speedLimit = "speed_limit"
        case show, sort, renew, content
        case monthPrice = "month_price"
        case quarterPrice = "quarter_price"
        case halfYearPrice = "half_year_price"
        case yearPrice = "year_price"
        case twoYearPrice = "two_year_price"
        case threeYearPrice = "three_year_price"
        case onetimePrice = "onetime_price"
        case resetPrice = "reset_price"
        case resetTrafficMethod = "reset_traffic_method"
        case capacityLimit = "capacity_limit"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeOrderIntIfPresent(forKey: .id) ?? 0
        name = container.decodeOrderStringIfPresent(forKey: .name) ?? ""
        speedLimit = container.decodeOrderIntIfPresent(forKey: .speedLimit)
        show = container.decodeOrderIntIfPresent(forKey: .show)
        sort = container.decodeOrderIntIfPresent(forKey: .sort)
        renew = container.decodeOrderIntIfPresent(forKey: .renew)
        groupID = container.decodeOrderIntIfPresent(forKey: .groupID)
        transferEnable = container.decodeOrderIntIfPresent(forKey: .transferEnable)
        content = container.decodeOrderStringIfPresent(forKey: .content) ?? ""
        monthPrice = container.decodeOrderIntIfPresent(forKey: .monthPrice)
        quarterPrice = container.decodeOrderIntIfPresent(forKey: .quarterPrice)
        halfYearPrice = container.decodeOrderIntIfPresent(forKey: .halfYearPrice)
        yearPrice = container.decodeOrderIntIfPresent(forKey: .yearPrice)
        twoYearPrice = container.decodeOrderDoubleIfPresent(forKey: .twoYearPrice)
        threeYearPrice = container.decodeOrderDoubleIfPresent(forKey: .threeYearPrice)
        onetimePrice = container.decodeOrderDoubleIfPresent(forKey: .onetimePrice)
        resetPrice = container.decodeOrderDoubleIfPresent(forKey: .resetPrice)
        resetTrafficMethod = container.decodeOrderStringIfPresent(forKey: .resetTrafficMethod)
        capacityLimit = container.decodeOrderIntIfPresent(forKey: .capacityLimit)
        createdAt = container.decodeOrderIntIfPresent(forKey: .createdAt) ?? 0
        updatedAt = container.decodeOrderIntIfPresent(forKey: .updatedAt) ?? 0
    }
}

private extension KeyedDecodingContainer {
    func decodeOrderIntIfPresent(forKey key: Key) -> Int? {
        guard contains(key), (try? decodeNil(forKey: key)) != true else { return nil }
        if let value = try? decode(Int.self, forKey: key) { return value }
        if let value = try? decode(Bool.self, forKey: key) { return value ? 1 : 0 }
        if let value = try? decode(String.self, forKey: key) {
            if let integer = Int(value) { return integer }
            if let number = Double(value), number.isFinite, number.rounded(.towardZero) == number {
                return Int(exactly: number)
            }
        }
        if let value = try? decode(Double.self, forKey: key), value.isFinite, value.rounded(.towardZero) == value {
            return Int(exactly: value)
        }
        return nil
    }

    func decodeOrderDoubleIfPresent(forKey key: Key) -> Double? {
        guard contains(key), (try? decodeNil(forKey: key)) != true else { return nil }
        if let value = try? decode(Double.self, forKey: key) { return value }
        if let value = try? decode(Int.self, forKey: key) { return Double(value) }
        if let value = try? decode(String.self, forKey: key) { return Double(value) }
        if let value = try? decode(Bool.self, forKey: key) { return value ? 1 : 0 }
        return nil
    }

    func decodeOrderStringIfPresent(forKey key: Key) -> String? {
        guard contains(key), (try? decodeNil(forKey: key)) != true else { return nil }
        if let value = try? decode(String.self, forKey: key) { return value }
        if let value = try? decode(Int.self, forKey: key) { return String(value) }
        if let value = try? decode(Double.self, forKey: key) { return String(value) }
        if let value = try? decode(Bool.self, forKey: key) { return value ? "true" : "false" }
        return nil
    }
}
