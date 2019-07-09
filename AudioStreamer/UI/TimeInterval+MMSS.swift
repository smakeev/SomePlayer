//
//  TimeInterval+MMSS.swift
//  AudioStreamer
//
//  Created by Syed Haris Ali on 6/5/18.
//

import Foundation

extension TimeInterval {
	
	/// Converts a `TimeInterval` into a MM:SS formatted string.
	///
	/// - Returns: A `String` representing the MM:SS formatted representation of the time interval.
	public func toMMSS() -> String {
		if self >= 60 * 60 {
			return toHHMMSS()
		}
		let ts = Int(self)
		let s  = ts % 60
		let m  = (ts / 60) % 60
		return String(format: "%02d:%02d", m, s)
	}
	
	public func toHHMMSS() -> String {
		let ts = Int(self)
		
		let s  = ts % 60
		let m  = (ts / 60) % 60
		let h  = (ts / 60) / 60
		return String(format: "%02d:%02d:%02d", h, m, s)
	}
	
}
