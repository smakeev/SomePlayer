//
//  ValueChangeController.swift
//  TimePitchStreamer-iOS
//
//  Created by Haris Ali on 1/26/19.
//

import Cocoa
import os.log

class ValueChangeController: NSViewController {
    static let logger = OSLog(subsystem: "com.ausomeapps", category: "ValueChangeController")
    var logger: OSLog {
        return ValueChangeController.logger
    }
    
    weak var delegate: ValueChangeControllerDelegate?
    
    // MARK: - Properties

    @IBOutlet weak var titleLabel: NSTextField! {
        willSet {
            newValue.textColor = NSColor(red: 0.18, green: 0.243, blue: 0.345, alpha: 1)
        }
    }
    @IBOutlet weak var subtitleLabel: NSTextField!
    @IBOutlet weak var slider: NSSlider!
    @IBOutlet weak var resetButton: NSButton!

    // MARK: - Methods
    
    @IBAction func resetButtonPressed(_ sender: NSButton) {
        os_log("%s - %d", log: logger, type: .debug, #function, #line)
        delegate?.valueChangeControllerTappedResetButton(self)
    }
    
    @IBAction func sliderValueChanged(_ sender: NSSlider) {
        os_log("%s - %d", log: logger, type: .debug, #function, #line)
        delegate?.valueChangeController(self, changedValue: sender.floatValue)
    }
    
    func setup(_ delegate: ValueChangeControllerDelegate,
               title: String,
               subtitle: String,
               filterColor: NSColor,
               currentValue: Double,
               minValue: Double,
               maxValue: Double) {
        _ = view
        titleLabel.stringValue = title
        subtitleLabel.stringValue = subtitle
        slider.setFilterColor(filterColor)
        slider.doubleValue = currentValue
        slider.minValue = minValue
        slider.maxValue = maxValue
        resetButton.setFilterColor(filterColor)
        self.delegate = delegate
    }
    
}
