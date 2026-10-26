#if DEBUG
import Foundation

/// One canned answer from a feature's own stub file: a status, a body and its type.
///
/// Each feature answers its routes in a file of its own under `UITestStubs/`, so features built
/// side by side never edit the same switch in `UITestSupport`. `StubProtocol` asks
/// `UITestSupport.Fixtures.packageReply(for:path:)` first and falls back to its own fixtures
/// when every feature file returns `nil`.
struct StubReply {
    var status = 200
    var data: Data
    var contentType = "application/json"

    /// A JSON body, given as text exactly as the platform would send it.
    static func json(_ s: String, status: Int = 200) -> StubReply {
        StubReply(status: status, data: Data(s.utf8), contentType: "application/json")
    }

    /// Raw bytes — a PDF, an image, an archive — with their media type.
    static func bytes(_ data: Data, type: String, status: Int = 200) -> StubReply {
        StubReply(status: status, data: data, contentType: type)
    }
}

extension UITestSupport.Fixtures {

    /// The first feature stub that answers this request, or `nil` for `body(for:)` to answer.
    static func packageReply(for request: URLRequest, path: String) -> StubReply? {
        // One closure per feature, tried in turn. A single `??` chain of eleven calls is too
        // much for the type-checker to solve in reasonable time.
        let answers: [(URLRequest, String) -> StubReply?] = [
            { MattersStubs.reply($0, $1) },
            { CasesStubs.reply($0, $1) },
            { CitationStubs.reply($0, $1) },
            { OCRBillingStubs.reply($0, $1) },
            { LibraryStubs.reply($0, $1) },
            { RadarStubs.reply($0, $1) },
            { TeamStubs.reply($0, $1) },
            { AnalysisStubs.reply($0, $1) },
            { FilingStubs.reply($0, $1) },
            { FileRouteStubs.reply($0, $1) },
            { CloudStubs.reply($0, $1) },
        ]
        for answer in answers {
            if let reply = answer(request, path) { return reply }
        }
        return nil
    }

    /// The request's body. `httpBody` is moved into a stream on its way through `URLSession`,
    /// so both are read. A stream can be read once: call this once per request.
    static func bodyData(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        return drain(stream)
    }

    /// The request's body as a JSON object, or `nil` when it is not one.
    static func jsonBody(of request: URLRequest) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: bodyData(of: request)) as? [String: Any]
    }

    /// The first value of the query item `name`, or `nil`.
    static func query(_ request: URLRequest, _ name: String) -> String? {
        guard let url = request.url,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else { return nil }
        return items.first { $0.name == name }?.value
    }

    /// Everything left in a body stream.
    static func drain(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(contentsOf: buffer[0..<read])
        }
        return data
    }
}
#endif
