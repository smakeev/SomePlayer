//
//  ViewController.swift
//  TimePitchStreamer
//
//  Created by Syed Haris Ali on 1/7/18.
//  Copyright © 2018 Ausome Apps LLC. All rights reserved.
//

import UIKit
import AVFoundation
import AudioStreamer
import os.log

class ViewController: UIViewController {
	static let logger = OSLog(subsystem: "com.fastlearner.streamer", category: "ViewController")
	
	// UI props
	@IBOutlet weak var smartSpeedBtn: SomePlayerActionView!
	@IBOutlet weak var speedUpBtn: SomePlayerActionView!
	
	@IBOutlet weak var smartSpeedLabel: UILabel!
	@IBOutlet weak var speedUpLabel: UILabel!
	@IBOutlet weak var smartSpeedMainLabel: UILabel!
	@IBOutlet weak var speedUpMainLabel: UILabel!
	@IBOutlet weak var currentTimeLabel: UILabel!
	@IBOutlet weak var durationTimeLabel: UILabel!
	@IBOutlet weak var rateLabel: UILabel!
	@IBOutlet weak var rateSlider: UISlider!
	@IBOutlet weak var pitchLabel: UILabel!
	@IBOutlet weak var pitchSlider: UISlider!
	@IBOutlet weak var playButton: UIButton!
	@IBOutlet weak var progressSlider: ProgressSlider!
	
	var savedSeconds: Double = 0 {
		didSet {
			let formatted = String(format: "saved: %.2f seconds", savedSeconds)
			speedUpLabel.text = formatted
		}
	}
	// Streamer props
	lazy var player: SomePlayer = {
		let player = SomePlayer()
		player.delegate = self
		return player
	}()
	
	// Used so we can use the current time slider continuously, but only seek when the user touches up
	var isSeeking = false
	
	// MARK: - View Lifecycle
	
	override func viewDidLoad() {
		super.viewDidLoad()
		
		// Setup the AVAudioSession and AVAudioEngine
		setupAudioSession()
		
		// Reset the pitch and rate
		resetPitch(self)
		resetRate(self)
		
		/// Download
		//let url = URL(string: "https://cdn.fastlearner.media/bensound-rumble.mp3")!
		let url = URL(string: "https://traffic.megaphone.fm/GLT1846252911.mp3")!
		//let url = URL(string: "https://play.podtrac.com/npr-510289/edge1.pod.npr.org/anon.npr-podcasts/podcast/npr/pmoney/2019/05/20190529_pmoney_pmpod916-3c38222a-1786-4732-8199-2055f4ecdbe8.mp3?awCollectionId=510289&awEpisodeId=728001911&orgId=1&d=1395&p=510289&story=728001911&t=podcast&e=728001911&size=22279265&ft=pod&f=510289")!
		
		//  let url = URL(string: "http://qthttp.apple.com.edgesuite.net/1010qwoeiuryfg/sl.m3u8")!
		player.url = url
		player.addRateObserver(withId: "controller") { value in
			self.smartSpeedLabel.text = "\(value)"
		}
		smartSpeedBtn.action = { [unowned self] btn in
			if self.player.silenceHandlingType == .smart {
				self.player.silenceHandlingType = .none
				btn.backgroundColor = .lightGray
				self.smartSpeedLabel.textColor = .black
				self.speedUpLabel.textColor = .black
				self.smartSpeedMainLabel.textColor = .black
				self.speedUpMainLabel.textColor = .black
				return
			}
			self.player.silenceHandlingType = .smart
			btn.backgroundColor = #colorLiteral(red: 0.182216078, green: 0.2415350676, blue: 0.3457649052, alpha: 1)
			self.smartSpeedLabel.textColor = .white
			self.speedUpLabel.textColor = .black
			self.speedUpBtn.backgroundColor = .lightGray
			self.smartSpeedLabel.textColor = .white
			self.speedUpLabel.textColor = .black
			self.smartSpeedMainLabel.textColor = .white
			self.speedUpMainLabel.textColor = .black
		}
		
		speedUpBtn.action = { btn in
			if self.player.silenceHandlingType == .speedUp {
				self.player.silenceHandlingType = .none
				btn.backgroundColor = .lightGray
				self.smartSpeedLabel.textColor = .black
				self.speedUpLabel.textColor = .black
				self.smartSpeedMainLabel.textColor = .black
				self.speedUpMainLabel.textColor = .black
				return
			}
			self.player.silenceHandlingType = .speedUp
			btn.backgroundColor = #colorLiteral(red: 0.182216078, green: 0.2415350676, blue: 0.3457649052, alpha: 1)
			self.smartSpeedBtn.backgroundColor = .lightGray
			self.smartSpeedLabel.textColor = .black
			self.speedUpLabel.textColor = .white
			self.smartSpeedMainLabel.textColor = .black
			self.speedUpMainLabel.textColor = .white
		}
	}
	
	// MARK: - Setting Up The Engine
	
	func setupAudioSession() {
		let session = AVAudioSession.sharedInstance()
		do {
			try session.setCategory(.playback, mode: .default, policy: .default, options: [.allowBluetoothA2DP,.defaultToSpeaker])
			try session.setActive(true)
		} catch {
			os_log("Failed to activate audio session: %@", log: ViewController.logger, type: .default, #function, #line, error.localizedDescription)
		}
	}
	
	// MARK: - Playback
	
	@IBAction func togglePlayback(_ sender: UIButton) {
		os_log("%@ - %d", log: ViewController.logger, type: .debug, #function, #line)
		
		if player.state == .playing {
			player.pause()
			
		} else {
			player.play()
		}
	}
	
	/// MARK: - Handle Seeking
	
	@IBAction func seek(_ sender: UISlider) {
		os_log("%@ - %d [%.1f]", log: ViewController.logger, type: .debug, #function, #line, progressSlider.value)
		if !player.rangeHeader {
			let time = TimeInterval(progressSlider.value)
			player.seek(to: time)
		} else {
			let percent = progressSlider.value / progressSlider.maximumValue
			player.seekPercently(to: percent)
		}
	}
	
	@IBAction func progressSliderTouchedDown(_ sender: UISlider) {
		os_log("%@ - %d", log: ViewController.logger, type: .debug, #function, #line)
		
		isSeeking = true
	}
	
	@IBAction func progressSliderValueChanged(_ sender: UISlider) {
		os_log("%@ - %d", log: ViewController.logger, type: .debug, #function, #line)
		if player.fileDownloaded {
			let currentTime = TimeInterval(progressSlider.value / progressSlider.maximumValue) * player.hasDuration
			currentTimeLabel.text = currentTime.toMMSS()
		}
	}
	
	@IBAction func progressSliderTouchedUp(_ sender: UISlider) {
		os_log("%@ - %d", log: ViewController.logger, type: .debug, #function, #line)
		
		seek(sender)
		isSeeking = false
	}
	
	/// MARK: - Change Pitch
	
	@IBAction func changePitch(_ sender: UISlider) {
		os_log("%@ - %d [%.1f]", log: ViewController.logger, type: .debug, #function, #line, sender.value)
		
		let step: Float = 100
		var pitch = roundf(pitchSlider.value)
		let newStep = roundf(pitch / step)
		pitch = newStep * step
		player.pitch = pitch
		pitchSlider.value = pitch
		pitchLabel.text = String(format: "%i cents", Int(pitch))
	}
	
	@IBAction func resetPitch(_ sender: Any) {
		os_log("%@ - %d [%.1f]", log: ViewController.logger, type: .debug, #function, #line)
		
		let pitch: Float = 0
		player.pitch = pitch
		pitchLabel.text = String(format: "%i cents", Int(pitch))
		pitchSlider.value = pitch
	}
	
	/// MARK: - Change Rate
	
	@IBAction func changeRate(_ sender: UISlider) {
		os_log("%@ - %d [%.1f]", log: ViewController.logger, type: .debug, #function, #line, sender.value)
		
		let step: Float = 0.1
		var rate = rateSlider.value
		let newStep = roundf(rate / step)
		rate = newStep * step
		player.baseRate = rate
		rateSlider.value = rate
		rateLabel.text = String(format: "%.2fx", rate)
	}
	
	@IBAction func resetRate(_ sender: Any) {
		os_log("%@ - %d [%.1f]", log: ViewController.logger, type: .debug, #function, #line)
		
		let rate: Float = 1
		player.baseRate = rate
		rateLabel.text = String(format: "%.2fx", rate)
		rateSlider.value = rate
	}
	
}

