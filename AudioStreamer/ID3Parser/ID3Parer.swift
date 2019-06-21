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

	public static func isGoodForStream(_ url: URL, handler: @escaping (Bool) -> Void) {
		let parser = ID3Parser(url, quickTest: true)
		parser.quickTest(handler)
	}

	var avassetGet: Bool = false {
		didSet {
			if !inParsing {
				handler?(asset, headerSize)
				handler = nil
			}
		}
	}

	var inParsing:  Bool = true {
		didSet {
			if avassetGet {
				handler?(asset, headerSize)
				handler = nil
			}
		}
	}

	var url: URL!
	var isID3: Bool? {
		didSet {
			if isQuick {
				self.quickHandler?(self.isID3 ?? false)
			}
		}
	}
	
	var asset: AVAsset?

	var version: UInt8?
	var getVersion: String? { return version == nil ? nil : String("2.\(version)") }
	var headerSize: Int64?
	var isQuick   : Bool = false

	init(_ url: URL, quickTest isQuick: Bool = false) {
		super.init()
		self.url = url
		self.isQuick = isQuick
	}

	private var handler:      ((AVAsset?, Int64?) -> Void)?
	private var quickHandler: ((Bool) -> Void)?

	func quickTest(_ handler: @escaping (Bool) -> Void) {
		self.quickHandler = handler
		DispatchQueue.global().async {
			self.prepare()
			self.start()
		}
	}

	func parse( handler: @escaping (AVAsset?, Int64?) -> Void) {
		self.handler = handler
		DispatchQueue.global().async {
			self.asset = AVURLAsset(url: self.url)
			DispatchQueue.main.async {
				self.avassetGet = true
			}
		}
		DispatchQueue.global().async {
			self.prepare()
			self.start()
		}
	}

	func cancel() {
		DispatchQueue.main.async {
			self.avassetGet = true
			self.inParsing  = false
		}
		task?.cancel()
	}

	private func start() {
		guard let task = task else {
			return
		}

		task.resume()
	}

	deinit {
		print("!!! DEINIT PARSERID3")
	}

	fileprivate var task: URLSessionDataTask?
	fileprivate lazy var session: URLSession = {
		return URLSession(configuration: .default, delegate: self, delegateQueue: nil)
	}()

	fileprivate var dataLimit = 1000 //how many bytes get to check if this is a ID3
}

extension ID3Parser {
	fileprivate func prepare() {
		guard let url = url else { return }
		if isQuick {
			dataLimit = 3
		}
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
	}

	public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {

		guard data.count > 3 else {
			DispatchQueue.main.async {
				self.isID3     = false
				self.inParsing = false
			}
			return
		}

		//String(data: data)
		if !String(decoding:data[0...3], as: UTF8.self).hasPrefix("ID3") {
			DispatchQueue.main.async {
				self.isID3     = false
				self.inParsing = false
			}
			return
		} else if isQuick {
			DispatchQueue.main.async {
				self.isID3 = true
			}
			return
		}

		//get version
		let tagVersion = data[3]

		if tagVersion > 4 || tagVersion < 0 {
			DispatchQueue.main.async {
				self.isID3     = false
				self.inParsing = false
			}
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

		headerSize = Int64(unsynchsafe(num)) + 10

		//not needed for now. For now we only need to get the size of ID3
//		let uses_synch = (data[5] & 0x80) != 0 ? true : false;
//		let has_extended_hdr = (data[5] & 0x40) != 0 ? true : false;
//
//		if has_extended_hdr {
//			//get it's size
//		}
		DispatchQueue.main.async {
			self.inParsing = false
		}
	}

	public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
		session.invalidateAndCancel()
	}
}
