//
//  SomeplayerEngineActionView.swift
//  AudioStreamer-iOS
//
//  Created by Sergey Makeev on 31/05/2019.
//  Copyright © 2019 Ausome Apps LLC. All rights reserved.
//

import UIKit
import Foundation

public class SomeplayerEngineActionView: UIView {

	public var action: ((SomeplayerEngineActionView) -> Void)? = nil
	
	internal var oldBGColor: UIColor!
	
	override public func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
		oldBGColor = self.backgroundColor
		self.backgroundColor = .gray
	}
	
	override public func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
		self.backgroundColor = oldBGColor
		action?(self)
	}

}
