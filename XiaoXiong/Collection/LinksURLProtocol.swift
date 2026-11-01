import Foundation

/// 进程内 links 供应器 —— 替代原来的 `LocalLinksServer`（127.0.0.1:8888 回环 socket 服务器）。
///
/// apptrace 二进制的请求地址仍是 `http://127.0.0.1:8888`；这里注册一个自定义
/// `NSURLProtocol`，在 `NSURLConnection` 层直接拦下这个 host:port 的请求，返回
/// `links.txt` 的原始密文（base64 串）。
///
/// 整个过程不建 socket、不 bind/listen、不 accept、不走任何回环网络，因此不会被
/// 端口占用、沙盒网络限制、bind 失败、TCP RST 等因素卡住 —— 也就是「内部不自身访问」。
///
/// 为什么可靠：apptrace 用的是 `sendSynchronousRequest:returningResponse:error:`
/// （NSURLConnection），它一定会经过全局已注册的 `NSURLProtocol`，拦截不会被绕过。
final class LinksURLProtocol: URLProtocol {
    private static let host = "127.0.0.1"
    private static let port = 8888

    /// 在 apptrace 被 dlopen 之前调用一次即可。
    static func register() {
        URLProtocol.registerClass(LinksURLProtocol.self)
        log("LinksURLProtocol: registered — intercepting http://\(host):\(port)")
    }

    /// links.txt 的原始内容（base64 密文），与之前回环服务器返回的 body 完全一致。
    /// 延迟加载：第一次真正被请求时才读 bundle，避免启动时多余 IO。
    static let body: Data? = {
        guard let url = Bundle.main.url(forResource: "links", withExtension: "txt"),
              let data = try? Data(contentsOf: url),
              !data.isEmpty else {
            log("LinksURLProtocol: links.txt missing/empty from bundle")
            return nil
        }
        log("LinksURLProtocol: loaded \(data.count) bytes from links.txt")
        return data
    }()

    override class func canInit(with request: URLRequest) -> Bool {
        guard let url = request.url,
              url.scheme?.lowercased() == "http",
              url.host == host,
              url.port == port else { return false }
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let client = client else { return }

        guard let body = Self.body,
              let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": "text/plain",
                    "Content-Length": "\(body.count)",
                ]
              ) else {
            let error = NSError(
                domain: NSURLErrorDomain,
                code: NSURLErrorCannotConnectToHost,
                userInfo: [NSLocalizedDescriptionKey: "links.txt unavailable"]
            )
            client.urlProtocol(self, didFailWithError: error)
            return
        }

        log("LinksURLProtocol: serving \(body.count) bytes for \(url.absoluteString)")
        client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client.urlProtocol(self, didLoad: body)
        client.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        // 同步一次性返回，没有需要取消的后台任务。
    }
}
