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

extension ViewController: SomeplayerEngineDelegate {
	
	func playerEngine(_ playerEngine: SomePlayerEngine, isBuffering: Bool) {
		//to show that we are in buffering
		UIApplication.shared.isNetworkActivityIndicatorVisible = isBuffering
	}
	
	func playerEngine(_ playerEngine: SomePlayerEngine, changedImage image: UIImage) {
		imageView.image = image
	}
	
	func playerEngine(_ playerEngine: SomePlayerEngine, changedTitle title: String) {
		//do nothing
	}
	
	func playerEngine(_ playerEngine: SomePlayerEngine, changedArtist artist: String) {
		artistLabel.text = artist
	}
	
	func playerEngine(_ playerEngine: SomePlayerEngine, changedAlbum album: String) {
		//do nothing
	}
	

	func playerEngine(_ playerEngine: SomePlayerEngine, offsetChanged offset: Int64) {
		progressSlider.offset = Float(offset) / Float(playerEngine.totalSize)
	}

	func playerEngine(_ playerEngine: SomePlayerEngine, failedDownloadWithError error: Error, forURL url: URL) {
		// os_log("%@ - %d [%@]", log: ViewController.logger, type: .debug, #function, #line, error.localizedDescription)

		let alert = UIAlertController(title: "Download Failed", message: error.localizedDescription, preferredStyle: .alert)
		alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { _ in
			alert.dismiss(animated: true, completion: nil)
		}))
		show(alert, sender: self)
	}

	func playerEngine(_ playerEngine: SomePlayerEngine, updatedDownloadProgress progress: Float, currentTaskProgress currentProgress: Float, forURL url: URL) {
		//  os_log("%@ - %d [%.2f]", log: ViewController.logger, type: .debug, #function, #line, progress)
		progressSlider.progress = progress
	}

	func playerEngine(_ playerEngine: SomePlayerEngine, changedState state: SomePlayerEngine.playerEngineState) {
		//  os_log("%@ - %d [%@]", log: ViewController.logger, type: .debug, #function, #line, String(describing: state))

		switch state {
		case .playing:
			progressSlider.isEnabled = true
			playButton.setImage(#imageLiteral(resourceName: "pause"), for: .normal)
		case .paused, .ended:
			progressSlider.isEnabled = true
			playButton.setImage(#imageLiteral(resourceName: "play"), for: .normal)
		case .ready:
			progressSlider.isEnabled = true
			playButton.isEnabled = true
			playButton.setImage(#imageLiteral(resourceName: "play"), for: .normal)
		default:
			progressSlider.isEnabled = false
			playButton.setImage(#imageLiteral(resourceName: "play"), for: .normal)
			playButton.isEnabled = false
		}
	}

	func playerEngine(_ playerEngine: SomePlayerEngine, updatedCurrentTime currentTime: TimeInterval) {
		//  os_log("%@ - %d [%@]", log: ViewController.logger, type: .debug, #function, #line, currentTime.toMMSS())

		if !isSeeking {
			if !playerEngine.rangeHeader {
				progressSlider.value = Float(currentTime)
			}
			currentTimeLabel.text = (playerEngine.timeOffset + currentTime).toMMSS()
			if playerEngine.fileDownloaded {
				if playerEngine.rangeHeader {
					progressSlider.value = Float(currentTime / playerEngine.hasDuration) * Float(playerEngine.totalSize)
				} else {
					progressSlider.value = Float(currentTime)
				}
			} else {
				let currentPercentOfDownloadedData = Float(currentTime / playerEngine.hasDuration)
				let currentByte = Float(playerEngine.hasBytes) * currentPercentOfDownloadedData
				progressSlider.value = Float(playerEngine.offset) + currentByte
			}
		}
	}

	func playerEngine(_ playerEngine: SomePlayerEngine, updatedDuration duration: TimeInterval) {
		let formattedDuration = duration.toMMSS()
		// os_log("%@ - %d [%@]", log: ViewController.logger, type: .debug, #function, #line, formattedDuration)
		durationTimeLabel.text = formattedDuration
		if playerEngine.fileDownloaded {
			if !playerEngine.rangeHeader {
				progressSlider.minimumValue = 0.0
				progressSlider.maximumValue = Float(duration)
			}
		} else {
			if !playerEngine.rangeHeader {
				progressSlider.maximumValue = Float(playerEngine.hasDuration)
			} else {
				progressSlider.maximumValue = Float(playerEngine.totalSize)
			}
		}

		durationTimeLabel.isEnabled = true
	}
	
	func playerEngine(_ playerEngine: SomePlayerEngine, savedSeconds: TimeInterval) {
		self.savedSeconds += savedSeconds
	}
}
