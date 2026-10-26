import XCTest
@testable import EmperorCore

/// Cross-tab navigation added for the parity work: a matter opened from another tab, and a
/// document opened on a cited page.
final class AppNavigatorParityTests: XCTestCase {

    /// Asking for a matter switches to Matters and leaves the request, section and all.
    func testOpeningAMatterSwitchesToMattersAndLeavesTheRequest() async {
        await onMain {
            let navigator = AppNavigator(selectedTab: .more)
            navigator.openMatter("prj-1", section: "court")

            XCTAssertEqual(navigator.selectedTab, .matters)
            XCTAssertEqual(navigator.pendingMatter?.projectID, "prj-1")
            XCTAssertEqual(navigator.pendingMatter?.section, "court")
        }
    }

    /// Taken once, so coming back to the tab later does not open the matter again.
    func testTheMatterIsTakenOnce() async {
        await onMain {
            let navigator = AppNavigator()
            navigator.openMatter("prj-1")

            let route = navigator.takePendingMatter()
            XCTAssertEqual(route?.projectID, "prj-1")
            XCTAssertNil(route?.section)
            XCTAssertNil(navigator.pendingMatter)
            XCTAssertNil(navigator.takePendingMatter(), "already applied")
        }
    }

    /// The latest request wins, and asking twice for the same matter is still two routes.
    func testTheLatestMatterRequestWinsAndEachIsDistinct() async {
        await onMain {
            let navigator = AppNavigator()
            navigator.openMatter("prj-1")
            let first = navigator.takePendingMatter()
            navigator.openMatter("prj-1")
            let second = navigator.takePendingMatter()
            XCTAssertNotEqual(first, second)
            XCTAssertNotEqual(second?.request, 0, "0 is a row tapped in Matters itself")

            navigator.openMatter("prj-1")
            navigator.openMatter("prj-2")
            XCTAssertEqual(navigator.takePendingMatter()?.projectID, "prj-2")
        }
    }

    /// A blank id goes nowhere and leaves the tab alone.
    func testABlankMatterIdIsIgnored() async {
        await onMain {
            let navigator = AppNavigator(selectedTab: .home)
            navigator.openMatter("  ")

            XCTAssertEqual(navigator.selectedTab, .home)
            XCTAssertNil(navigator.pendingMatter)
        }
    }

    /// A citation's page and quote travel with the document.
    func testTheDocumentRouteCarriesPageAndQuote() async {
        await onMain {
            let navigator = AppNavigator(selectedTab: .ask)
            navigator.openDocument(path: "Bakshi//Lease.pdf", page: 2, quote: " the lessee shall pay ")

            let route = navigator.takePendingDocument()
            XCTAssertEqual(route?.path, "Bakshi/Lease.pdf")
            XCTAssertEqual(route?.page, 2)
            XCTAssertEqual(route?.quote, "the lessee shall pay")
            XCTAssertEqual(navigator.selectedTab, .ask, "My Files is presented, not a tab")
        }
    }

    /// The old way in still opens the document, on no particular page.
    func testThePlainDocumentRequestHasNoPageOrQuote() async {
        await onMain {
            let navigator = AppNavigator()
            navigator.openDocument(path: "Bakshi/Lease.pdf")

            let route = navigator.takePendingDocument()
            XCTAssertEqual(route?.path, "Bakshi/Lease.pdf")
            XCTAssertNil(route?.page)
            XCTAssertNil(route?.quote)
        }
    }

    /// A page below 1 and a blank quote are dropped rather than carried.
    func testAMeaninglessPageAndQuoteAreDropped() async {
        await onMain {
            let navigator = AppNavigator()
            navigator.openDocument(path: "Lease.pdf", page: 0, quote: "  ")

            let route = navigator.takePendingDocument()
            XCTAssertNil(route?.page)
            XCTAssertNil(route?.quote)
        }
    }
}

/// Linux XCTest cannot call a `@MainActor` test method, so each test hops here instead.
@MainActor
private func onMain(_ body: @MainActor () async -> Void) async {
    await body()
}
