//
//  DownloaderTests.swift
//  DownloaderTests
//
//  Created by Syed Haris Ali on 1/6/18.
//

import XCTest
@testable import SomePlayer

class DownloaderTests: XCTestCase {

    let downloader = Downloader()

    func testInitialState() {
        let url = RemoteFileURL.claire.mp3
        downloader.url = url
        XCTAssertEqual(downloader.url, url)
        XCTAssertEqual(downloader.progress, 0.0)
        XCTAssertEqual(downloader.totalBytesReceived, 0)
        XCTAssertEqual(downloader.totalBytesCount, 0)
        XCTAssertEqual(downloader.state, .notStarted)
    }

    func testDownloadMP3() {
        let expectation = XCTestExpectation(description: "Download MP3")

        let url = RemoteFileURL.theLastOnes.mp3
        downloader.url = url
        downloader.start()
        downloader.completionHandler = { [downloader] in
            XCTAssertEqual(downloader.state, .completed)
            XCTAssertNil($0)
            expectation.fulfill()
        }
        XCTAssertEqual(downloader.state, .started)

        self.wait(for: [expectation], timeout: 10)
    }

    func testDownloadAAC() {
        let expectation = XCTestExpectation(description: "Download AAC")

        let url = RemoteFileURL.theLastOnes.aac
        downloader.url = url
        downloader.start()
        downloader.completionHandler = { [downloader] in
            XCTAssertEqual(downloader.state, .completed)
            XCTAssertNil($0)
            expectation.fulfill()
        }
        XCTAssertEqual(downloader.state, .started)

        self.wait(for: [expectation], timeout: 10)
    }

    func testDownloadWAV() {
        let expectation = XCTestExpectation(description: "Download WAV")

        let url = RemoteFileURL.theLastOnes.wav
        downloader.url = url
        downloader.start()
        downloader.completionHandler = { [downloader] in
            XCTAssertEqual(downloader.state, .completed)
            XCTAssertNil($0)
            expectation.fulfill()
        }
        XCTAssertEqual(downloader.state, .started)

        self.wait(for: [expectation], timeout: 30)
    }
}
