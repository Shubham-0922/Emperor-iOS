import XCTest
@testable import EmperorCore

final class CloudConnectionsModelTests: XCTestCase {

    // MARK: - Words

    func testDescriptionsAreTheWebsLines() {
        XCTAssertEqual(
            CloudConnectionsModel.description(for: .off, label: "Google Drive"),
            "Not configured on this server.")
        XCTAssertEqual(
            CloudConnectionsModel.description(for: .ready, label: "Google Drive"),
            "Save files to it, and import documents from it.")
        XCTAssertEqual(
            CloudConnectionsModel.description(for: .on("a@b.in"), label: "OneDrive"),
            "Connected as a@b.in")
        XCTAssertEqual(
            CloudConnectionsModel.description(for: .on(nil), label: "OneDrive"), "Connected")
        XCTAssertEqual(
            CloudConnectionsModel.description(for: CloudConnection(), label: "OneDrive"),
            "Not configured on this server.")
    }

    // MARK: - Load

    func testLoadReadsConnectionsAndDerives() async {
        let fake = FakeCloudDrive([.google: .on(), .microsoft: .off])
        await cloudConnections(fake) { model in
            await model.load()
            XCTAssertEqual(model.state, .loaded)
            XCTAssertTrue(model.anyConfigured)
            XCTAssertEqual(model.connectedProviders, [.google])
            XCTAssertEqual(model.description(of: .google), "Connected as a@example.com")
        }
    }

    func testNothingConfiguredIsNotAnyConfigured() async {
        let fake = FakeCloudDrive([.google: .off, .microsoft: .off])
        await cloudConnections(fake) { model in
            await model.load()
            XCTAssertFalse(model.anyConfigured)
            XCTAssertTrue(model.connectedProviders.isEmpty)
        }
    }

    func testLoadFailureIsAFailedState() async {
        let fake = FakeCloudDrive()
        fake.connectionsError = APIError.server(status: 500, message: "boom")
        await cloudConnections(fake) { model in
            await model.load()
            XCTAssertNotNil(model.state.failure)
        }
    }

    // MARK: - Connect

    func testConnectSetsThePageToShow() async {
        let fake = FakeCloudDrive([.google: .ready])
        await cloudConnections(fake) { model in
            await model.connect(.google)
            XCTAssertEqual(model.pendingURL?.provider, .google)
            XCTAssertEqual(model.pendingURL?.url.host, "accounts.google.com")
            XCTAssertNil(model.busy)
        }
    }

    func testConnectFailureIsSaid() async {
        let fake = FakeCloudDrive([.google: .ready])
        fake.connectError = APIError.server(status: 400, message: "Google Drive is not configured on this server")
        await cloudConnections(fake) { model in
            await model.connect(.google)
            XCTAssertNil(model.pendingURL)
            XCTAssertEqual(model.error, "Google Drive is not configured on this server")
        }
    }

    func testPollClosesThePageOnceConnected() async {
        let fake = FakeCloudDrive([.google: .ready])
        fake.connectOnRead = 3
        let clock = SteppedClock()
        await cloudConnections(fake, timing: clock.timing) { model in
            await model.connect(.google)
            await model.pollWhileConnecting(.google)
            XCTAssertNil(model.pendingURL)
            XCTAssertEqual(model.notice, "Google Drive connected")
            XCTAssertEqual(fake.connectionReads, 3)
            XCTAssertEqual(model.description(of: .google), "Connected as a@example.com")
        }
        XCTAssertEqual(clock.waits, [2_000, 2_000, 2_000])
    }

    func testPollStopsAfterTenMinutes() async {
        let fake = FakeCloudDrive([.google: .ready])
        let clock = SteppedClock()
        await cloudConnections(fake, timing: clock.timing) { model in
            await model.connect(.google)
            await model.pollWhileConnecting(.google)
            XCTAssertNotNil(model.pendingURL, "the page stays; only the reads stop")
            XCTAssertNil(model.notice)
        }
        XCTAssertEqual(clock.waits.count, 300)
    }

    func testPollStopsWhenThePageCloses() async {
        let fake = FakeCloudDrive([.google: .ready])
        let clock = SteppedClock()
        await cloudConnections(fake, timing: clock.timing) { model in
            await model.connect(.google)
            model.pendingURL = nil
            await model.pollWhileConnecting(.google)
            XCTAssertEqual(fake.connectionReads, 0)
        }
        XCTAssertTrue(clock.waits.isEmpty)
    }

    func testBrowserClosedRefetchesAndSaysConnected() async {
        let fake = FakeCloudDrive([.google: .ready])
        await cloudConnections(fake) { model in
            await model.load()
            await model.connect(.google)
            fake.connectOnRead = 1
            await model.browserClosed(.google)
            XCTAssertNil(model.pendingURL)
            XCTAssertEqual(model.notice, "Google Drive connected")
            XCTAssertNil(model.hint)
        }
    }

    func testBrowserClosedWithoutConnectingSaysTryAgain() async {
        let fake = FakeCloudDrive([.google: .ready])
        await cloudConnections(fake) { model in
            await model.load()
            await model.connect(.google)
            await model.browserClosed(.google)
            XCTAssertEqual(fake.connectionReads, 2)
            XCTAssertNil(model.notice)
            XCTAssertEqual(model.hint, "Not connected yet. Try again.")
        }
    }

    func testBrowserClosedAfterThePollDoesNotRepeatTheNotice() async {
        let fake = FakeCloudDrive([.google: .ready])
        fake.connectOnRead = 1
        let clock = SteppedClock()
        await cloudConnections(fake, timing: clock.timing) { model in
            await model.connect(.google)
            await model.pollWhileConnecting(.google)
            model.notice = nil
            await model.browserClosed(.google)
            XCTAssertNil(model.notice)
        }
    }

    // MARK: - Disconnect

    func testDisconnectRefetches() async {
        let fake = FakeCloudDrive([.google: .on()])
        await cloudConnections(fake) { model in
            await model.load()
            await model.disconnect(.google)
            XCTAssertEqual(fake.disconnected, [.google])
            XCTAssertEqual(model.notice, "Google Drive disconnected")
            XCTAssertTrue(model.connectedProviders.isEmpty)
        }
    }

    func testDisconnectFailureIsSaid() async {
        let fake = FakeCloudDrive([.google: .on()])
        fake.disconnectError = APIError.server(status: 400, message: "Unknown provider")
        await cloudConnections(fake) { model in
            await model.load()
            await model.disconnect(.google)
            XCTAssertEqual(model.error, "Unknown provider")
            XCTAssertNil(model.notice)
        }
    }
}

@MainActor
private func cloudConnections(
    _ fake: FakeCloudDrive, timing: FollowTiming = .live,
    _ body: @MainActor (CloudConnectionsModel) async -> Void
) async {
    await body(CloudConnectionsModel(service: fake, timing: timing))
}
