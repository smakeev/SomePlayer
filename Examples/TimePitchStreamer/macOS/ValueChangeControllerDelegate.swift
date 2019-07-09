//
//  ValueChangeControllerDelegate.swift
//  TimePitchStreamer-macOS
//
//  Created by Haris Ali on 1/26/19.
//

import Foundation

protocol ValueChangeControllerDelegate: class {
    
    /// <#Description#>
    ///
    /// - Parameters:
    ///   - controller: <#controller description#>
    ///   - value: <#value description#>
    func valueChangeController(_ controller: ValueChangeController, changedValue value: Float)
    
    /// <#Description#>
    ///
    /// - Parameter controller: <#controller description#>
    func valueChangeControllerTappedResetButton(_ controller: ValueChangeController)
    
}
