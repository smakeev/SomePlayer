//
//  ViewController.swift
//  TimePitchStreamer
//
//  Created by Syed Haris Ali on 1/7/18.
//

import UIKit
import AVFoundation
import SomePlayer
import os.log

class ViewController: UIViewController {
	static let logger = OSLog(subsystem: "com.fastlearner.streamer", category: "ViewController")
	
	// UI props
	@IBOutlet weak var smartSpeedBtn: SomeplayerEngineActionView!
	@IBOutlet weak var speedUpBtn: SomeplayerEngineActionView!
	var adaptiveSpeedBtn: SomeplayerEngineActionView?
	
	@IBOutlet weak var smartSpeedLabel: UILabel!
	@IBOutlet weak var speedUpLabel: UILabel!
	var adaptiveSpeedLabel: UILabel?
	@IBOutlet weak var smartSpeedMainLabel: UILabel!
	@IBOutlet weak var speedUpMainLabel: UILabel!
	var adaptiveSpeedMainLabel: UILabel?
	@IBOutlet weak var currentTimeLabel: UILabel!
	@IBOutlet weak var durationTimeLabel: UILabel!
	@IBOutlet weak var rateLabel: UILabel!
	@IBOutlet weak var rateSlider: UISlider!
	@IBOutlet weak var pitchLabel: UILabel!
	@IBOutlet weak var pitchSlider: UISlider!
	@IBOutlet weak var playButton: UIButton!
	@IBOutlet weak var progressSlider: ProgressSlider!
	@IBOutlet weak var imageView: UIImageView!
	@IBOutlet weak var artistLabel: UILabel!
	@IBOutlet weak var voiceBoostSwitch: UISwitch!


	var savedSeconds: Double = 0 {
		didSet {
			let formatted = String(format: "saved: %.2f seconds", savedSeconds)
			speedUpLabel.text = formatted
		}
	}
	// Streamer props
	lazy var playerEngine: SomePlayerEngine = {
		let playerEngine = SomePlayerEngine(.progressiveDownload)
		playerEngine.delegate = self
		return playerEngine
	}()
	
	// Used so we can use the current time slider continuously, but only seek when the user touches up
	var isSeeking = false
	
	// MARK: - View Lifecycle

	deinit {
		removePlayerNotifications()
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		
		// Setup the AVAudioSession and AVAudioEngine
		setupAudioSession()
		configurePlayerNotifications()
		// Reset the pitch and rate
		resetPitch(self)
		resetRate(self)
		configureAdaptiveSpeedButton()

		/// Download
		//let url = URL(string: "https://cdn.fastlearner.media/bensound-rumble.mp3")!
		//let url = URL(string: "https://traffic.megaphone.fm/GLT1846252911.mp3")!
		//let url = URL(string: "https://play.podtrac.com/npr-510289/edge1.pod.npr.org/anon.npr-podcasts/podcast/npr/pmoney/2019/05/20190529_pmoney_pmpod916-3c38222a-1786-4732-8199-2055f4ecdbe8.mp3?awCollectionId=510289&awEpisodeId=728001911&orgId=1&d=1395&p=510289&story=728001911&t=podcast&e=728001911&size=22279265&ft=pod&f=510289")!



		//  let url = URL(string: "http://qthttp.apple.com.edgesuite.net/1010qwoeiuryfg/sl.m3u8")!

	//Local file
//		let audioFileURL = Bundle.main.url(forResource: "file_example_MP3_2MG", withExtension: "mp3")
//		playerEngine.openLocal(audioFileURL!)

	//Remote file
		//let str = "https://applehosted.podcasts.apple.com/apple_keynotes/2019/190603_SD.mp4"
	
		//let str = "https://cdn.fastlearner.media/bensound-rumble.mp3"
		//let str = "https://file-examples.com/wp-content/uploads/2017/11/file_example_MP3_700KB.mp3" //700km
		//let str = "https://file-examples.com/wp-content/uploads/2017/11/file_example_MP3_1MG.mp3" //1 MG
		//let str = "https://file-examples.com/wp-content/uploads/2017/11/file_example_MP3_2MG.mp3" //2 MG
		//let str = "https://file-examples.com/wp-content/uploads/2017/11/file_example_MP3_5MG.mp3" // MG
		//let str = "https://traffic.megaphone.fm/GLT1846252911.mp3" //good podcast


		//let str = "http://www.pusware.com/gobbet/gop1111.mp3" //no format for a long time (no range)
		//let str = "https://dts.podtrac.com/redirect.mp3/media.blubrry.com/99percentinvisible/dovetail.prxu.org/96/e8167dd5-7850-4de3-80c9-b51f39dbc087/01_356_The_Automat_pt01.mp3" //VBR

		//let str = "http://media.blubrry.com/shortstacks/continuum.umn.edu/media/Truth-Tweets-and-Tomorrows.mp3"//no total

		// let str = "http://feedproxy.google.com/~r/EndtimeMinistriesPodcast/~5/Af_F8emiKT0/631795170-endtime-ministries-eta060419.mp3"

		let str = "https://traffic.libsyn.com/secure/syntax/Syntax_-_899.mp3"
		//let str = "http://traffic.libsyn.com/joeroganexp/mmashow067.mp3?dest-id=19997"
		//let str = "http://traffic.libsyn.com/joeroganexp/p1304.mp3?dest-id=19997" // 2026-05-20: redirects to HTTPS 404
		//let str = "http://202.6.74.107:8060/triplej.mp3" //not exist

		//let str = "https://file-examples.com/wp-content/uploads/2017/11/file_example_WAV_1MG.wav" //WAW
		//let str = "https://file-examples.com/wp-content/uploads/2017/11/file_example_WAV_10MG.wav"

		//let str = "file:///Users/sergeymakeev/Downloads/file_example_OOG_5MG.ogg"

		let url = URL(string: str)!
		ID3Parser.isGoodForStream(url) { _, _ in
		}
		playerEngine.openRemote(url)

		playerEngine.addRateObserver(withId: "controller") { value in
			self.smartSpeedLabel.text = "\(value)"
		}
		smartSpeedBtn.action = { [unowned self] btn in
			if self.playerEngine.silenceHandlingType == .smart {
				self.playerEngine.silenceHandlingType = .none
				self.updateSilenceModeSelection()
				return
			}
			self.playerEngine.silenceHandlingType = .smart
			self.updateSilenceModeSelection()
		}
		
		speedUpBtn.action = { [unowned self] btn in
			if self.playerEngine.silenceHandlingType == .speedUp {
				self.playerEngine.silenceHandlingType = .none
				self.updateSilenceModeSelection()
				return
			}
			self.playerEngine.silenceHandlingType = .speedUp
			self.updateSilenceModeSelection()
		}
	}
	
	// MARK: - Setting Up The Engine
	
	func setupAudioSession() {
		let session = AVAudioSession.sharedInstance()
		do {
			try session.setCategory(.playback, mode: .default, policy: .default, options: [.allowBluetoothA2DP,.defaultToSpeaker])
			try session.setActive(true)
		} catch {
			//os_log("Failed to activate audio session: %@", log: ViewController.logger, type: .default, #function, #line, error.localizedDescription)
		}
	}

	internal func configurePlayerNotifications() {

		NotificationCenter.default.addObserver(self, selector: #selector(onInterruptionNotification(_:)), name: AVAudioSession.interruptionNotification, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(onMediaServicesWereResetNotification(_:)), name: AVAudioSession.mediaServicesWereLostNotification, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(onMediaServicesWereResetNotification(_:)), name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(onRouteChangeNotification(_:)),name: AVAudioSession.routeChangeNotification, object: nil)
	}

	internal func removePlayerNotifications() {
		NotificationCenter.default.removeObserver(self)
	}

	private func configureAdaptiveSpeedButton() {
		guard adaptiveSpeedBtn == nil,
			  let selectorStackView = speedUpBtn.superview as? UIStackView else {
			return
		}

		let button = SomeplayerEngineActionView()
		button.backgroundColor = .lightGray
		button.translatesAutoresizingMaskIntoConstraints = false

		let labelStack = UIStackView()
		labelStack.axis = .vertical
		labelStack.alignment = .center
		labelStack.distribution = .equalSpacing
		labelStack.translatesAutoresizingMaskIntoConstraints = false
		labelStack.isUserInteractionEnabled = false

		let valueLabel = UILabel()
		valueLabel.text = "adaptive"
		valueLabel.textAlignment = .center
		valueLabel.font = smartSpeedLabel.font
		valueLabel.textColor = .black

		let titleLabel = UILabel()
		titleLabel.text = "Adaptive Speed"
		titleLabel.textAlignment = .center
		titleLabel.numberOfLines = 2
		titleLabel.font = smartSpeedMainLabel.font
		titleLabel.textColor = .black

		labelStack.addArrangedSubview(valueLabel)
		labelStack.addArrangedSubview(titleLabel)
		button.addSubview(labelStack)
		NSLayoutConstraint.activate([
			labelStack.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 6),
			labelStack.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -6),
			labelStack.topAnchor.constraint(equalTo: button.topAnchor, constant: 8),
			labelStack.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -8)
		])

		button.action = { [unowned self] _ in
			if self.playerEngine.silenceHandlingType == .adaptiveSpeed {
				self.playerEngine.silenceHandlingType = .none
			} else {
				self.playerEngine.silenceHandlingType = .adaptiveSpeed
			}
			self.updateSilenceModeSelection()
		}

		selectorStackView.addArrangedSubview(button)
		adaptiveSpeedBtn = button
		adaptiveSpeedLabel = valueLabel
		adaptiveSpeedMainLabel = titleLabel
		updateSilenceModeSelection()
	}

	private func updateSilenceModeSelection() {
		let activeColor = #colorLiteral(red: 0.182216078, green: 0.2415350676, blue: 0.3457649052, alpha: 1)

		updateModeButton(
			smartSpeedBtn,
			valueLabel: smartSpeedLabel,
			titleLabel: smartSpeedMainLabel,
			isSelected: playerEngine.silenceHandlingType == .smart,
			activeColor: activeColor
		)
		updateModeButton(
			speedUpBtn,
			valueLabel: speedUpLabel,
			titleLabel: speedUpMainLabel,
			isSelected: playerEngine.silenceHandlingType == .speedUp,
			activeColor: activeColor
		)
		updateModeButton(
			adaptiveSpeedBtn,
			valueLabel: adaptiveSpeedLabel,
			titleLabel: adaptiveSpeedMainLabel,
			isSelected: playerEngine.silenceHandlingType == .adaptiveSpeed,
			activeColor: activeColor
		)
	}

	private func updateModeButton(
		_ button: SomeplayerEngineActionView?,
		valueLabel: UILabel?,
		titleLabel: UILabel?,
		isSelected: Bool,
		activeColor: UIColor
	) {
		button?.backgroundColor = isSelected ? activeColor : .lightGray
		valueLabel?.textColor = isSelected ? .white : .black
		titleLabel?.textColor = isSelected ? .white : .black
	}

	// MARK: - Playback
	
	@IBAction func togglePlayback(_ sender: UIButton) {
		//os_log("%@ - %d", log: ViewController.logger, type: .debug, #function, #line)
		
		if playerEngine.state == .playing {
			playerEngine.pause()
			
		} else {
			playerEngine.play()
		}
	}
	
	/// MARK: - Handle Seeking
	
	@IBAction func seek(_ sender: UISlider) {
		//os_log("%@ - %d [%.1f]", log: ViewController.logger, type: .debug, #function, #line, progressSlider.value)
		if !playerEngine.rangeHeader {
			let time = TimeInterval(progressSlider.value)
			playerEngine.seek(to: time)
		} else {
			let percent = progressSlider.value / progressSlider.maximumValue
			playerEngine.seekPercently(to: percent)
		}
	}
	
	@IBAction func progressSliderTouchedDown(_ sender: UISlider) {
		//os_log("%@ - %d", log: ViewController.logger, type: .debug, #function, #line)
		
		isSeeking = true
	}
	
	@IBAction func progressSliderValueChanged(_ sender: UISlider) {
	//	//os_log("%@ - %d", log: ViewController.logger, type: .debug, #function, #line)
		if playerEngine.fileDownloaded {
			let currentTime = TimeInterval(progressSlider.value / progressSlider.maximumValue) * playerEngine.hasDuration
			currentTimeLabel.text = currentTime.toMMSS()
		} else {
			guard progressSlider.maximumValue != 0 else { return }
			let currentTime = TimeInterval(progressSlider.value / progressSlider.maximumValue) * playerEngine.duration
			currentTimeLabel.text = currentTime.toMMSS()
		}
	}
	
	@IBAction func progressSliderTouchedUp(_ sender: UISlider) {
		//os_log("%@ - %d", log: ViewController.logger, type: .debug, #function, #line)
		
		seek(sender)
		isSeeking = false
	}

	/// MARK: - Change Pitch
	
	@IBAction func changePitch(_ sender: UISlider) {
		//os_log("%@ - %d [%.1f]", log: ViewController.logger, type: .debug, #function, #line, sender.value)
		
		let step: Float = 100
		var pitch = roundf(pitchSlider.value)
		let newStep = roundf(pitch / step)
		pitch = newStep * step
		playerEngine.pitch = pitch
		pitchSlider.value = pitch
		pitchLabel.text = String(format: "%i cents", Int(pitch))
	}
	
	@IBAction func resetPitch(_ sender: Any) {
		//os_log("%@ - %d [%.1f]", log: ViewController.logger, type: .debug, #function, #line)
		
		let pitch: Float = 0
		playerEngine.pitch = pitch
		pitchLabel.text = String(format: "%i cents", Int(pitch))
		pitchSlider.value = pitch
	}
	
	/// MARK: - Change Rate
	
	@IBAction func changeRate(_ sender: UISlider) {
		//os_log("%@ - %d [%.1f]", log: ViewController.logger, type: .debug, #function, #line, sender.value)
		
		let step: Float = 0.1
		var rate = rateSlider.value
		let newStep = roundf(rate / step)
		rate = newStep * step
		playerEngine.baseRate = rate
		rateSlider.value = rate
		rateLabel.text = String(format: "%.2fx", rate)
	}
	
	@IBAction func resetRate(_ sender: Any) {
		//os_log("%@ - %d [%.1f]", log: ViewController.logger, type: .debug, #function, #line)
		
		let rate: Float = 1
		playerEngine.baseRate = rate
		rateLabel.text = String(format: "%.2fx", rate)
		rateSlider.value = rate
	}

	@IBAction func onVoiceBoost(_ sender: Any) {
		if voiceBoostSwitch.isOn {
			playerEngine.globalGain = 10.0
		} else {
			playerEngine.globalGain = 0.0
		}
	}
}

extension ViewController {

	@objc fileprivate func onInterruptionNotification(_ notification: Notification) {

		guard let interruptionTypeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt else { return }
		guard let interruptionType = AVAudioSession.InterruptionType.init(rawValue: interruptionTypeValue) else { return }

		let shouldResume: Bool
		if let interruptionOptionsValue = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt {
			let interruptionOptions = AVAudioSession.InterruptionOptions.init(rawValue: interruptionOptionsValue)
			shouldResume = interruptionOptions.contains(.shouldResume)
		}
		else {
			shouldResume = false
		}

		let wasSuspended: Bool
		if #available(iOS 10.3, *) {
			let wasSuspendedNumber = notification.userInfo?[AVAudioSessionInterruptionWasSuspendedKey] as? NSNumber
			wasSuspended = wasSuspendedNumber?.boolValue ?? false
		} else {
			wasSuspended = false
		}

		let isInterrupted: Bool
		switch interruptionType {
		case .began: isInterrupted = !wasSuspended
		case .ended: isInterrupted = false
		@unknown default:
			isInterrupted = false
		}

		if isInterrupted {
			self.playerEngine.pause()
		}
		else if shouldResume {
			self.playerEngine.play()
		}

	}

	@objc fileprivate func onMediaServicesWereResetNotification(_ notification: Notification) {
		DispatchQueue.main.async {
			self.playerEngine.pause()
		}
	}

	@objc fileprivate func onRouteChangeNotification(_ notification: NSNotification) {
		DispatchQueue.main.async {
			self.playerEngine.pause()
		}
	}
}
