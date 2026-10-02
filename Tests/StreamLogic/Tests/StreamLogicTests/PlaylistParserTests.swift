import XCTest
@testable import StreamLogic

final class PlaylistParserTests: XCTestCase {
    func testParsesBasicEntry() {
        let m3u = """
        #EXTM3U
        #EXTINF:-1 tvg-id="BBCOne.uk@SD" tvg-logo="https://x.test/logo.png" group-title="General;News",BBC One (576p)
        https://example.com/bbc.m3u8
        """
        let streams = PlaylistParser.parse(m3u)
        XCTAssertEqual(streams.count, 1)
        XCTAssertEqual(streams[0].name, "BBC One (576p)")
        XCTAssertEqual(streams[0].url.absoluteString, "https://example.com/bbc.m3u8")
        XCTAssertEqual(streams[0].id, "https://example.com/bbc.m3u8")
        XCTAssertEqual(streams[0].channelID, "BBCOne.uk@SD")
        XCTAssertEqual(streams[0].categories, ["General", "News"])
        XCTAssertEqual(streams[0].country, "UK")
        XCTAssertEqual(streams[0].logoURL?.absoluteString, "https://x.test/logo.png")
    }

    func testCommaInsideQuotedAttributeDoesNotTruncateName() {
        let m3u = """
        #EXTINF:-1 tvg-id="A.us" group-title="News, Weather",Channel A
        https://example.com/a.m3u8
        """
        let streams = PlaylistParser.parse(m3u)
        XCTAssertEqual(streams.first?.name, "Channel A")
        XCTAssertEqual(streams.first?.categories, ["News, Weather"])
    }

    func testDuplicateChannelIDsGetDistinctStreamIDs() {
        let m3u = """
        #EXTINF:-1 tvg-id="Same.us@SD",Same (480p)
        https://example.com/one.m3u8
        #EXTINF:-1 tvg-id="Same.us@SD",Same (720p)
        https://example.com/two.m3u8
        """
        let streams = PlaylistParser.parse(m3u)
        XCTAssertEqual(streams.count, 2)
        XCTAssertEqual(Set(streams.map(\.id)).count, 2)
    }

    func testSkipsNonHTTPSchemes() {
        let m3u = """
        #EXTINF:-1,Radio
        rtmp://example.com/live
        #EXTINF:-1,Good
        http://example.com/good.m3u8
        """
        let streams = PlaylistParser.parse(m3u)
        XCTAssertEqual(streams.map(\.name), ["Good"])
    }

    func testSkipsEntryWithoutURL() {
        let m3u = """
        #EXTINF:-1,Orphan
        #EXTINF:-1,Real
        https://example.com/real.m3u8
        """
        XCTAssertEqual(PlaylistParser.parse(m3u).map(\.name), ["Real"])
    }

    func testIgnoresUnknownDirectivesBetweenInfoAndURL() {
        let m3u = """
        #EXTINF:-1,Chan
        #EXTVLCOPT:http-referrer=https://ref.test/
        https://example.com/chan.m3u8
        """
        XCTAssertEqual(PlaylistParser.parse(m3u).map(\.name), ["Chan"])
    }

    func testHandlesWindowsLineEndings() {
        let m3u = "#EXTM3U\r\n#EXTINF:-1 tvg-id=\"A.us\",Chan A\r\nhttps://example.com/a.m3u8\r\n"
        let streams = PlaylistParser.parse(m3u)
        XCTAssertEqual(streams.count, 1)
        XCTAssertEqual(streams[0].url.absoluteString, "https://example.com/a.m3u8")
    }

    func testMissingAttributesYieldNilsAndEmptyCategories() {
        let streams = PlaylistParser.parse("#EXTINF:-1,Plain\nhttps://example.com/p.m3u8")
        XCTAssertEqual(streams.count, 1)
        XCTAssertNil(streams[0].channelID)
        XCTAssertNil(streams[0].country)
        XCTAssertNil(streams[0].logoURL)
        XCTAssertEqual(streams[0].categories, [])
    }

    func testCountryDerivation() {
        func country(_ tvgID: String) -> String? {
            PlaylistParser.parse("#EXTINF:-1 tvg-id=\"\(tvgID)\",X\nhttps://e.test/\(tvgID).m3u8").first?.country
        }
        XCTAssertEqual(country("Foo.us"), "US")
        XCTAssertEqual(country("Foo.us@HD"), "US")
        XCTAssertNil(country("Foo"))
        XCTAssertNil(country("Foo.com"))
    }

    func testEmptyAndGarbageInputReturnEmpty() {
        XCTAssertEqual(PlaylistParser.parse(""), [])
        XCTAssertEqual(PlaylistParser.parse("<html>not a playlist</html>"), [])
    }
}
