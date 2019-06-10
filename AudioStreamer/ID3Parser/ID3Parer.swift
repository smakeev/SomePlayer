//
//  File.swift
//  AudioStreamer-iOS
//
//  Created by Sergey Makeev on 10/06/2019.
//  Copyright © 2019 Ausome Apps LLC. All rights reserved.
//

import Foundation

public class ID3Parser: NSObject {
	var inParsing: Bool = false
	var url: URL!
	var isID3: Bool? {
		didSet {
			//inform with result
		}
	}

	var version: UInt8?
	var getVersion: String? { return version == nil ? nil : String("2.\(version)") }
	var headerSize: Int64?

	init(_ url: URL) {
		super.init()
		self.url = url
	}

	func parse() {
		guard inParsing == false else { return }
		prepare()
		start()
	}

	func cancel() {
		inParsing = false
		task?.cancel()
	}

	private func start() {
		guard inParsing == false else { return }
		inParsing = true
		guard let task = task else {
			return
		}

		task.resume()
	}

	fileprivate var task: URLSessionDataTask?
	fileprivate lazy var session: URLSession = {
		return URLSession(configuration: .default, delegate: self, delegateQueue: nil)
	}()

	fileprivate let dataLimit = 1000 //how many bytes get to check if this is a ID3
}

extension ID3Parser {
	fileprivate func prepare() {
		guard let url = url else { return }

		var request = URLRequest(url: url)
		var headers = request.allHTTPHeaderFields ?? [:]
		headers["Range"] = "bytes=0-\(dataLimit)"

		request.allHTTPHeaderFields = headers
		task = session.dataTask(with: request)
	}

	fileprivate func readSynchsafeInt(synch:Int32) -> Int32
{
	return (synch & 127) + 128 * ((synch >> 8) & 127) + 16384 * ((synch >> 16) & 127) + 2097152 * ((synch >> 24) & 127)
	}

}

extension ID3Parser: URLSessionDataDelegate {

	public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
		completionHandler(.allow)
		print("!!! \(response)")
	}

	public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
		print("!!! data: \(data)")
		//String(data: data)
		if !String(decoding:data[0...3], as: UTF8.self).hasPrefix("ID3") {
			isID3 = false
			inParsing = false
			return
		}
		print("!! ID3")
		//get version
		let tagVersion = data[3]
		print("!!! Version: \(tagVersion)")
		if tagVersion > 4 || tagVersion < 0 {
			isID3 = false
			inParsing = false
			return
		}
		version = tagVersion
		// Get the ID3 tag size and flags
		let sizeData = data[6...9]
		let number = sizeData.withUnsafeBytes {
			(pointer: UnsafePointer<Int32>) -> Int32 in
			return pointer.pointee
		}
		headerSize = Int64(readSynchsafeInt(synch: number))
		print("!!! \(headerSize)")

		var uses_synch = (data[5] & 0x80) != 0 ? true : false;
		var has_extended_hdr = (data[5] & 0x40) != 0 ? true : false;
		print("!!! \(uses_synch)  \(has_extended_hdr)")
	}

	public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
		print("!!! completed: \(error)")
	}
}
