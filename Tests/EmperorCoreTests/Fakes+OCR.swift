import Foundation
@testable import EmperorCore

// Moved out of `Fakes.swift` unchanged; each area's stand-ins live in a file of their own.

final class FakeOCR: OCRProviding, @unchecked Sendable {
    var job: OCRJob?
    var submitError: Error?
    var statusError: Error?
    var downloadData = Data("PK\u{03}\u{04} docx".utf8)
    private(set) var submitted: [(fileName: String, language: OCRLanguage)] = []

    func submit(data: Data, fileName: String, language: OCRLanguage) async throws -> String {
        if let submitError { throw submitError }
        submitted.append((fileName, language))
        return job?.id ?? "job_1"
    }

    func status(jobID: String) async throws -> OCRJob {
        if let statusError { throw statusError }
        guard let job else {
            throw APIError.server(status: 404, message: "That job could not be found.")
        }
        return job
    }

    func download(outputFile: String) async throws -> Data {
        if let downloadError { throw downloadError }
        downloaded.append(outputFile)
        return downloadData
    }

    var historyJobs: [OCRJob] = []
    var historyListedOthers = false
    var historyError: Error?
    var clearError: Error?
    var downloadError: Error?
    private(set) var downloaded: [String] = []
    private(set) var historyCalls = 0
    private(set) var clearCalls = 0

    func history() async throws -> OCRHistory {
        historyCalls += 1
        if let historyError { throw historyError }
        return OCRHistory(jobs: historyJobs, listedOtherJobs: historyListedOthers)
    }

    func clearHistory() async throws {
        clearCalls += 1
        if let clearError { throw clearError }
        historyJobs = []
    }
}
