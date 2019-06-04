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
            progressSlider.value = Float(currentTime)
            currentTimeLabel.text = currentTime.toMMSS()
        }
    }
    
    func player(_ player: SomePlayer, updatedDuration duration: TimeInterval) {
        let formattedDuration = duration.toMMSS()
       // os_log("%@ - %d [%@]", log: ViewController.logger, type: .debug, #function, #line, formattedDuration)
        if player.fileDownloaded {
        	durationTimeLabel.text = formattedDuration
			progressSlider.minimumValue = 0.0
        	progressSlider.maximumValue = Float(duration)
		} else {
			progressSlider.maximumValue = Float(player.totalSize)
		}

        durationTimeLabel.isEnabled = true
        playButton.isEnabled = true
        progressSlider.isEnabled = true
    }
	
    func player(_ player: SomePlayer, savedSeconds: TimeInterval) {
    	self.savedSeconds += savedSeconds
	}
}
