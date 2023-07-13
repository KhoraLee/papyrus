@testable import PapyrusCore
import XCTest

final class RequestBuilderTests: XCTestCase {
    func testPath() throws {
        let req = RequestBuilder(baseURL: "foo/", method: "bar", path: "baz")
        XCTAssertEqual(try req.fullURL().absoluteString, "foo/baz")
    }
}
