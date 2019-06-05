//
//  ViewController+Streamer.swift
//  TimePitchStreamer
//
//  Created by Syed Haris Ali on 6/5/18.
//  Copyright © 2018 Ausome Apps LLC. All rights reserved.
//

import Foundation
import AudioStreamer
import os.log
import UIKit

extension ViewController: SomePlayerDelegate {

	func player(_ player: SomePlayer, offsetChanged offset: Int64) {
		progressSlider.offset = Float(offset) / Float(player.totalSize)
	}

	func player(_ player: SomePlayer, failedDownloadWithError error: Error, forURL url: URL) {
		// os_log("%@ - %d [%@]", log: ViewController.logger, type: .debug, #function, #line, error.localizedDescription)

		let alert = UIAlertController(title: "Download Failed", message: error.localizedDescription, preferredStyle: .alert)
		alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { _ in
			alert.dismiss(animated: true, completion: nil)
		}))
		show(alert, sender: self)
	}

	func player(_ player: SomePlayer, updatedDownloadProgress progress: Float, currentTaskProgress currentProgress: Float, forURL url: URL) {
		//  os_log("%@ - %d [%.2f]", log: ViewController.logger, type: .debug, #function, #line, progress)
		//print("!!! total progress: \(progress), current: \(currentProgress)")
		progressSlider.progress = progress
	}

	func player(_ player: SomePlayer, changedState state: StreamingState) {
		//  os_log("%@ - %d [%@]", log: ViewController.logger, type: .debug, #function, #line, String(describing: state))

		switch state {
		case .playing:
			playButton.setImage(#imageLiteral(resourceName: "pause"), for: .normal)
		case .paused, .stopped:
			playButton.setImage(#imageLiteral(resourceName: "play"), for: .normal)
		}
	}

	func player(_ player: SomePlayer, updatedCurrentTime currentTime: TimeInterval) {
		//  os_log("%@ - %d [%@]", log: ViewController.logger, type: .debug, #function, #line, currentTime.toMMSS())

		if !isSeeking {
			if !player.rangeHeader {
				progressSlider.value = Float(currentTime)
			}
			currentTimeLabel.text = currentTime.toMMSS()
			if player.fileDownloaded {
				progressSlider.value = Float(currentTime / player.hasDuration) * Float(player.totalSize)
			} else {
				let currentPercentOfDownloadedData = Float(currentTime / player.hasDuration)
				let currentByte = Float(player.hasBytes) * currentPercentOfDownloadedData
				progressSlider.value = Float(player.offset) + currentByte
			}
		}
	}

	func player(_ player: SomePlayer, updatedDuration duration: TimeInterval) {
		let formattedDuration = duration.toMMSS()
		// os_log("%@ - %d [%@]", log: ViewController.logger, type: .debug, #function, #line, formattedDuration)
		if player.fileDownloaded {
			durationTimeLabel.text = formattedDuration
			if !player.rangeHeader {
				progressSlider.minimumValue = 0.0
				progressSlider.maximumValue = Float(duration)
			}
		} else {
			if !player.rangeHeader {
				progressSlider.maximumValue = Float(player.hasDuration)
			} else {
				progressSlider.maximumValue = Float(player.totalSize)
			}
		}

		durationTimeLabel.isEnabled = true
		playButton.isEnabled = true
		progressSlider.isEnabled = true
	}
	
	func player(_ player: SomePlayer, savedSeconds: TimeInterval) {
		self.savedSeconds += savedSeconds
	}
}
