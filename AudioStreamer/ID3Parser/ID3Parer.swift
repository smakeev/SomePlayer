//
//  File.swift
//  AudioStreamer-iOS
//
//  Created by Sergey Makeev on 10/06/2019.
//  Copyright © 2019 Ausome Apps LLC. All rights reserved.
//

import Foundation
import AVFoundation

public class ID3Parser: NSObject {
	var inParsing: Bool = false
	var url: URL!
	var isID3: Bool? {
		didSet {
			//inform with result
		}
	}
	
	var asset: AVAsset?

	var version: UInt8?
	var getVersion: String? { return version == nil ? nil : String("2.\(version)") }
	var headerSize: Int64?

	init(_ url: URL) {
		super.init()
		self.url = url
	}

	private var handler: ((AVAsset?) -> Void)?
	func parse( handler: @escaping (AVAsset?) -> Void) {
		guard inParsing == false else { return }
		self.handler = handler
		DispatchQueue.global().async {
			let asset = AVURLAsset(url: self.url)
			self.handler?(asset)
		}
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

	fileprivate func unsynchsafe(_ inP: Int32) -> Int32 {
		var outP: Int32 = 0
		var mask: Int32 = 0x7F000000

		while mask > 0 {
			outP >>= 1
			outP |= inP & mask
			mask >>= 8
		}

		return outP
	}

}


// biteOffset = <ID3V2 size> + (<seconds> * <bitrate> * 8)

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
		var sizeData = Data()
		sizeData.append(data[9])
		sizeData.append(data[8])
		sizeData.append(data[7])
		sizeData.append(data[6])

		let sData = sizeData as NSData
		var num: Int32 = 0
		sData.getBytes(&num, length: MemoryLayout<Int32>.size)
		print("!!! \(num)")

		headerSize = Int64(unsynchsafe(num))
		print("!!! \(unsynchsafe(num))")

		var uses_synch = (data[5] & 0x80) != 0 ? true : false;
		var has_extended_hdr = (data[5] & 0x40) != 0 ? true : false;
		print("!!! \(uses_synch)  \(has_extended_hdr)")
	}

	public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
		print("!!! completed: \(error)")
	}
}
