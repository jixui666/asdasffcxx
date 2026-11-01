import Foundation
import Libbox

public class HTTPClient {
    private static var userAgent: String {
        var userAgent = Variant.applicationName
        userAgent += "/"
        userAgent += Bundle.main.version
        userAgent += " (Build "
        userAgent += Bundle.main.versionNumber
        userAgent += "; sing-box "
        userAgent += LibboxVersion()
        userAgent += ")"
        return userAgent
    }

    private let client: any LibboxHTTPClientProtocol

    public init() {
        client = LibboxNewHTTPClient()!
        client.modernTLS()
    }

    public func getString(_ url: String?) throws -> String {
        let request = client.newRequest()!
        request.setUserAgent(HTTPClient.userAgent)
        try request.setURL(url)
        let response = try request.execute()
        var error: NSError?
        let contentString = response.getContentString(&error)
        if let error {
            throw error
        }
        return contentString
    }

    public static func getStringAsync(_ url: String?) async throws -> String {
        guard let url, let requestURL = URL(string: url) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: requestURL)
        request.setValue(HTTPClient.userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard let content = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        return content
    }

    deinit {
        client.close()
    }
}
