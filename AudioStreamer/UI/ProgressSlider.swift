//
//  ProgressSlider.swift
//  AudioStreamer
//
//  Created by Syed Haris Ali on 5/22/18.
//

import UIKit
import os.log

/// The `ProgressSlider` is a `UISlider` subclass that adds a `UIProgressView` to show a deterministic loading state. In streaming this is useful for showing how much of the file has been downloaded.
public class ProgressSlider: UISlider {
    
    /// A `UIProgressView` used to display the track progress layer
    fileprivate let progressView = UIProgressView(progressViewStyle: .default)
    
    /// A `Float` representing the progress value
    @IBInspectable public var progress: Float {
        get {
            return progressView.progress
        }
        set {
            progressView.progress = newValue
        }
    }
    
    /// A `UIColor` representing the progress view's track tint color (right region)
    @IBInspectable public var progressTrackTintColor: UIColor {
        get {
            return progressView.trackTintColor ?? .white
        }
        set {
            progressView.trackTintColor = newValue
        }
    }
    
    /// A `UIColor` representing the progress view's progress tint color (left region)
    @IBInspectable public var progressProgressTintColor: UIColor {
        get {
            return progressView.progressTintColor ?? .blue
        }
        set {
            progressView.progressTintColor = newValue
        }
    }

	public var offset: Float = 0 {
		didSet {
			let trackFrame = super.trackRect(forBounds: bounds)
			progressView.frame.origin.x = 0 + CGFloat(offset) * (trackFrame.width)
		}
	}

    /// Setup / Drawing
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setup()
    }
    
    func setup() {

		let emptyPath: UIView = UIView()
		insertSubview(emptyPath, at: 0)
		let trackFrame = super.trackRect(forBounds: bounds)
		var center = CGPoint(x: 0, y: 0)
		center.y = floor(frame.height / 2 + progressView.frame.height / 2)
		emptyPath.center = center
		emptyPath.frame.origin.x = 0
		emptyPath.frame.size.width = trackFrame.width
		emptyPath.frame.size.height = 1.5
		emptyPath.autoresizingMask = [.flexibleWidth]
		emptyPath.clipsToBounds = true
		emptyPath.layer.cornerRadius = 2
		emptyPath.backgroundColor = .gray

        insertSubview(progressView, at: 1)
        
        progressView.center = center
        progressView.frame.origin.x = 0 + CGFloat(offset) * (trackFrame.width)
        progressView.frame.size.width = trackFrame.width
        progressView.autoresizingMask = [.flexibleWidth]
        progressView.clipsToBounds = true
        progressView.layer.cornerRadius = 2
		self.clipsToBounds = true
    }
    
    public override func trackRect(forBounds bounds: CGRect) -> CGRect {
        var result = super.trackRect(forBounds: bounds)
        result.size.height = 0.01
        return result
    }

    /// Sets the progress on the progress view.
    ///
    /// - Parameters:
    ///   - progress: A float representing the progress value (0 - 1)
    ///   - animated: A bool indicating whether the new progress value is animated
    public func setProgress(_ progress: Float, animated: Bool) {
        progressView.setProgress(progress, animated: animated)
    }
    
}
