import XCTest
@testable import StreamLogic

final class StreamFilterTests: XCTestCase {
    private func stream(_ name: String, categories: [String] = [], country: String? = nil) -> IPTVStream {
        IPTVStream(
            name: name,
            url: URL(string: "https://e.test/\(name.hashValue).m3u8")!,
            channelID: nil,
            categories: categories,
            country: country,
            logoURL: nil
        )
    }

    func testEmptyAndWhitespaceQueryReturnsEverything() {
        let all = [stream("A"), stream("B")]
        XCTAssertEqual(StreamFilter.apply(all, query: "", category: nil, country: nil), all)
        XCTAssertEqual(StreamFilter.apply(all, query: "   ", category: nil, country: nil), all)
    }

    func testQueryIgnoresCaseAndDiacritics() {
        let all = [stream("Télévision Française"), stream("Other")]
        let result = StreamFilter.apply(all, query: "television", category: nil, country: nil)
        XCTAssertEqual(result.map(\.name), ["Télévision Française"])
    }

    func testCategoryFilterMatchesAnyOfMultipleCategories() {
        let all = [stream("A", categories: ["News", "Sports"]), stream("B", categories: ["Kids"])]
        XCTAssertEqual(StreamFilter.apply(all, query: "", category: "Sports", country: nil).map(\.name), ["A"])
    }

    func testCountryFilterAndCombinedFilters() {
        let all = [
            stream("A", categories: ["News"], country: "US"),
            stream("B", categories: ["News"], country: "UK"),
        ]
        XCTAssertEqual(StreamFilter.apply(all, query: "", category: nil, country: "UK").map(\.name), ["B"])
        XCTAssertEqual(StreamFilter.apply(all, query: "a", category: "News", country: "US").map(\.name), ["A"])
        XCTAssertEqual(StreamFilter.apply(all, query: "a", category: "News", country: "UK"), [])
    }

    func testCategoriesAndCountriesAreSortedAndUnique() {
        let all = [
            stream("A", categories: ["News", "Kids"], country: "US"),
            stream("B", categories: ["News"], country: "UK"),
            stream("C", country: nil),
        ]
        XCTAssertEqual(StreamFilter.categories(in: all), ["Kids", "News"])
        XCTAssertEqual(StreamFilter.countries(in: all), ["UK", "US"])
    }
}
