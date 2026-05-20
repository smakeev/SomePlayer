//
//  ResumableData.swift
//  AudioStreamer-iOS
//
//  Created by Sergey Makeev on 01/06/2019.
//

import Foundation

public struct ResumableData {
	let readyData: Int64
	let offset:    Int64
	let validator: String
	
	init(offset: Int64) {
		self.offset    = offset
		self.readyData = 0
		self.validator = "Nothing"
	}
	
	init?(offset: Int64, response: URLResponse, readyData: Int64) {
		guard let response = response as? HTTPURLResponse,
			  let acceptRanges = response.allHeaderFields["Accept-Ranges"] as? String,
			  acceptRanges.lowercased() == "bytes" else { return nil }
		
		let validator = ResumableData.validator(from: response)
		self.readyData = readyData
		self.validator = validator ?? ""
		self.offset    = offset
	}
	
	private static func validator(from response: HTTPURLResponse) -> String? {
		if let entityTag = response.allHeaderFields["ETag"] as? String {
			return entityTag
		}
		// There seems to be a bug with ETag where HTTPURLResponse would canonicalize
		// it to Etag instead of ETag
		// https://bugs.swift.org/browse/SR-2429
		if let entityTag = response.allHeaderFields["Etag"] as? String {
			return entityTag
		}
		if let lastModified = response.allHeaderFields["Last-Modified"] as? String {
			return lastModified
		}
		return nil
	}
}
