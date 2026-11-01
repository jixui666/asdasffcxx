//
//  File.swift
//  LoginKit
//
//  Created by Mac on 2024/10/12.
//

import Foundation
import UIKit

private func validatedAPIBaseURL(_ rawValue: String?) -> String? {
    guard let rawValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
          !rawValue.isEmpty,
          var components = URLComponents(string: rawValue),
          components.scheme?.lowercased() == "https",
          let host = components.host, !host.isEmpty,
          components.user == nil, components.password == nil,
          components.query == nil, components.fragment == nil,
          components.path.hasSuffix("/api/v1") || components.path.hasSuffix("/api/v1/") else {
        return nil
    }
    if !components.path.hasSuffix("/") {
        components.path += "/"
    }
    return components.url?.absoluteString
}


class UserManager {
    static let shared = UserManager()  
    
//    public let configURL = "https://upload.fengche.im/jsonvpn.php"
    public let configURL = "http://download.uuvpn2026.top/vpn.php"
        
    public let appversion = Bundle.main.infoDictionary?["CFBundleShortVersionString"]  as? String ?? "1.0.0"
    
    // UserDefaults keys
    private let loginStatusKey = "isLoggedIn"
    private let userEmailKey = "userEmail"
    private let avatarurlKey = "avatar_url"
    private let autodataKey = "autodata"
    private let subURLDataKey = "subURLData"
    private let baseURLKey = "baseURLKey"
    private let configSourceKey = "serverDataSourceURL"
    private let crisptoken = "crisptoken"
     
    /// UserDefaults实例
    private let defaults = UserDefaults.standard

    
    func crispTokenData()-> String{
        configurationURL(forKey: crisptoken)
    }
    
    func baseURL()-> String{
        guard defaults.string(forKey: configSourceKey) == configURL else { return "" }
        return validatedAPIBaseURL(defaults.string(forKey: baseURLKey)) ?? ""
    }
    
    func baseDYURL()-> String{
        configurationURL(forKey: "baseDYURL")
    }
    
    func mainregisterURL()-> String{
        configurationURL(forKey: "mainregisterURLKey")
    }
    func paymentURL()-> String{
        configurationURL(forKey: "paymentURLKey")
    }
    func telegramUrl()-> String{
        configurationURL(forKey: "telegramUrlKey")
    }
    func kefuUrl()-> String{
        configurationURL(forKey: "kefuUrlKey")
    }
    func websiteURL()-> String{
        configurationURL(forKey: "websiteURLKey")
    }
    
    
    
    /// Returns a cache-busting URL for the remote configuration document.
    private func configRequestURL() -> URL? {
        guard var components = URLComponents(string: configURL) else { return nil }
        components.queryItems = (components.queryItems ?? []) + [
            URLQueryItem(name: "v", value: String(Int(Date().timeIntervalSince1970)))
        ]
        return components.url
    }

    @MainActor
    func refreshRemoteConfig() async throws -> RemoteConfigResponse {
        guard let url = configRequestURL() else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.addValue(Bundle.main.bundleIdentifier ?? "", forHTTPHeaderField: "bid")
        request.addValue(appversion, forHTTPHeaderField: "appver")
        request.addValue(UIDevice.current.model, forHTTPHeaderField: "model")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let configuration = try? JSONDecoder().decode(RemoteConfigResponse.self, from: data),
              applyRemoteConfig(configuration, rawData: data) else {
            throw URLError(.cannotParseResponse)
        }
        defaults.set(configURL, forKey: configSourceKey)
        defaults.set(Date().timeIntervalSince1970, forKey: "lastFetchTime")
        return configuration
    }

    private func configurationURL(forKey key: String) -> String {
        guard defaults.string(forKey: configSourceKey) == configURL else { return "" }
        return defaults.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func storeRemoteValue(_ value: String?, forKey key: String) {
        let value = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value, !value.isEmpty {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    /// Apply one validated remote document as the source of all app URLs.
    @discardableResult
    private func applyRemoteConfig(_ response: RemoteConfigResponse, rawData: Data) -> Bool {
        guard response.isSuccessful,
              let baseURL = validatedAPIBaseURL(response.baseURL),
              let rawJSON = String(data: rawData, encoding: .utf8) else {
            return false
        }

        defaults.set(baseURL, forKey: baseURLKey)
        storeRemoteValue(response.mainregisterURL, forKey: "mainregisterURLKey")
        storeRemoteValue(response.paymentURL, forKey: "paymentURLKey")
        storeRemoteValue(response.telegramurl, forKey: "telegramUrlKey")
        storeRemoteValue(response.kefuurl, forKey: "kefuUrlKey")
        storeRemoteValue(response.websiteURL, forKey: "websiteURLKey")
        storeRemoteValue(response.baseDYURL, forKey: "baseDYURL")
        storeRemoteValue(response.crisptoken, forKey: crisptoken)
        defaults.set(rawJSON, forKey: "serverData")
        return true
    }

    func restoreCachedRemoteConfig() -> Bool {
        guard defaults.string(forKey: configSourceKey) == configURL,
              let rawJSON = defaults.string(forKey: "serverData"),
              let data = rawJSON.data(using: .utf8),
              let response = try? JSONDecoder().decode(RemoteConfigResponse.self, from: data) else {
            return false
        }
        return applyRemoteConfig(response, rawData: data)
    }
    
    /// 更新登录状态
    func updateLoginStatus(_ loggedIn: Bool) {
        defaults.set(loggedIn, forKey: loginStatusKey)
        defaults.synchronize()
    }
    
    func saveUserInfoToLocal(userInfo: UserInfo) {
        do {
            let data = try JSONEncoder().encode(userInfo)
            defaults.set(data, forKey: "userInfo")
            defaults.synchronize()
        } catch {
             
        }
    }
    
    /// 检查登录状态
    func isUserLoggedIn() -> Bool {
        return defaults.bool(forKey: loginStatusKey)
    }

    /// 存储用户信息
    func storeUserInfo(email: String, avator: String) {
        defaults.set(email, forKey: userEmailKey)
        defaults.set(avator, forKey: avatarurlKey)
        defaults.synchronize()
    }

    /// 获取用户信息
    func getUserInfo() -> (email: String, avator: String) {
        let email = defaults.string(forKey: userEmailKey) ?? ""
        let avator = defaults.string(forKey: avatarurlKey) ?? ""
        return (email, avator)
    }
    
    /// 存储认证数据
    func storeAutoData(data: String) {
        defaults.set(data, forKey: autodataKey)
        defaults.synchronize()
    }

    /// 获取订阅URL数据
    func getSuburlData() -> String {
          return defaults.string(forKey: subURLDataKey) ?? ""
    }    
    
    /// 存储订阅URL数据
    func storeSuburlData(data: String) {
        defaults.set(data, forKey: subURLDataKey)
        defaults.synchronize()
    }

    /// 获取认证数据
    func getAutoData() -> String {
        return defaults.string(forKey: autodataKey) ?? ""
    }
      
    /// 清除用户数据
    func clearUserData() {
        let cachedConfigSource = defaults.string(forKey: configSourceKey)
        let cachedFetchTime = defaults.double(forKey: "lastFetchTime")
        let cachedConfigData = defaults.string(forKey: "serverData")?.data(using: .utf8)
        let cachedConfig = cachedConfigData.flatMap {
            try? JSONDecoder().decode(RemoteConfigResponse.self, from: $0)
        }

        for key in defaults.dictionaryRepresentation().keys {
            defaults.removeObject(forKey: key)
        }

        if cachedConfigSource == configURL,
           let cachedConfigData, let cachedConfig,
           applyRemoteConfig(cachedConfig, rawData: cachedConfigData) {
            defaults.set(configURL, forKey: configSourceKey)
            if cachedFetchTime > 0 {
                defaults.set(cachedFetchTime, forKey: "lastFetchTime")
            }
        }
    }
}

/// Remote settings document served by configURL.
///
/// The document has changed shape over time (some values have been returned as
/// numbers or omitted altogether), so every field is optional and decoded
/// through the small compatibility helpers below. Callers must still require
/// `code == 1` before using or caching a response.
struct RemoteConfigResponse: Codable {
    let baseURL: String?
    let baseDYURL: String?
    let mainregisterURL: String?
    let paymentURL: String?
    let telegramurl: String?
    let kefuurl: String?
    let websiteURL: String?
    let crisptoken: String?
    let message: String?
    let code: Int?

    enum CodingKeys: String, CodingKey {
        case baseURL
        case baseDYURL
        case mainregisterURL
        case paymentURL
        case telegramurl
        case kefuurl
        case websiteURL
        case crisptoken
        case message
        case code
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        baseURL = container.decodeRemoteString(forKey: .baseURL)
        baseDYURL = container.decodeRemoteString(forKey: .baseDYURL)
        mainregisterURL = container.decodeRemoteString(forKey: .mainregisterURL)
        paymentURL = container.decodeRemoteString(forKey: .paymentURL)
        telegramurl = container.decodeRemoteString(forKey: .telegramurl)
        kefuurl = container.decodeRemoteString(forKey: .kefuurl)
        websiteURL = container.decodeRemoteString(forKey: .websiteURL)
        crisptoken = container.decodeRemoteString(forKey: .crisptoken)
        message = container.decodeRemoteString(forKey: .message)
        code = container.decodeRemoteInt(forKey: .code)
    }

    var isSuccessful: Bool {
        code == 1
    }

    var hasValidBaseURL: Bool {
        validatedAPIBaseURL(baseURL) != nil
    }
}

private extension KeyedDecodingContainer {
    func decodeRemoteString(forKey key: Key) -> String? {
        guard contains(key), (try? decodeNil(forKey: key)) != true else { return nil }
        if let value = try? decode(String.self, forKey: key) { return value }
        if let value = try? decode(Int.self, forKey: key) { return String(value) }
        if let value = try? decode(Double.self, forKey: key) { return String(value) }
        if let value = try? decode(Bool.self, forKey: key) { return value ? "true" : "false" }
        return nil
    }

    func decodeRemoteInt(forKey key: Key) -> Int? {
        guard contains(key), (try? decodeNil(forKey: key)) != true else { return nil }
        if let value = try? decode(Int.self, forKey: key) { return value }
        if let value = try? decode(Bool.self, forKey: key) { return value ? 1 : 0 }
        if let value = try? decode(String.self, forKey: key) {
            if let integer = Int(value) { return integer }
            if let double = Double(value), double.isFinite, double.rounded(.towardZero) == double {
                return Int(exactly: double)
            }
        }
        if let value = try? decode(Double.self, forKey: key), value.isFinite,
           value.rounded(.towardZero) == value {
            return Int(exactly: value)
        }
        return nil
    }
}

/// Helpers shared by API screens when handling the server's response envelope.
/// The panel API can return a JSON error envelope for both 2xx and non-2xx responses,
/// so callers must inspect the envelope before decoding endpoint-specific data.
enum APIResponseSupport {
    static func message(from data: Data) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let dictionary = object as? [String: Any]
        else {
            return nil
        }

        for key in ["message", "msg"] {
            if let value = dictionary[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }

        if let error = dictionary["error"] as? String, !error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return error
        }
        if let error = dictionary["error"] as? [String: Any],
           let value = error["message"] as? String,
           !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value
        }
        return nil
    }

    static func indicatesFailure(_ data: Data) -> Bool {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let dictionary = object as? [String: Any]
        else {
            return false
        }

        if let status = dictionary["status"] as? String {
            return ["fail", "failed", "error"].contains(status.lowercased())
        }
        if let status = dictionary["status"] as? Int {
            return status != 1 && status != 200
        }
        if let success = dictionary["success"] as? Bool {
            return !success
        }
        return false
    }

    static func failureMessage(statusCode: Int, data: Data, fallback: String) -> String {
        let serverMessage = message(from: data)
        if statusCode == 401 || statusCode == 403 {
            return "\(serverMessage ?? "登录状态已过期，请重新登录")（HTTP \(statusCode)）"
        }
        if let serverMessage = serverMessage {
            return "\(serverMessage)（HTTP \(statusCode)）"
        }
        return "\(fallback)（HTTP \(statusCode)）"
    }

    #if DEBUG
    static func logResponse(endpoint: String, response: URLResponse?, data: Data?) {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let contentType = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? "unknown"
        let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? "<empty>"
        let preview = String(body.prefix(500))
        print("API \(endpoint) HTTP \(status) \(contentType): \(preview)")
    }
    #endif
}
