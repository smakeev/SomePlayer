//
//  SAPDispatcher.swift
//  SomePLayer
//
//  Created by Sergey Makeev on 19/06/2019.
//  Copyright © 2019 Sergey Makeev. All rights reserved.
//

import Foundation

internal struct DispatcherItem<Type> {

	weak public var subscriber: AnyObject?
		 public var handler:    (Type) -> Void
		 public var once:       Bool
}

internal class Dispatcher<Type> {

	private var items = [DispatcherItem<Type>]()

	func dispatch(_ value: Type) {

		for item in items {
			if item.subscriber != nil {
				item.handler(value)
			}
		}
		minimize(subscriber: nil, removeOnce: true)
	}

	func add(subscriber: AnyObject, once: Bool, handler: @escaping (Type) -> Void) {
		items.append(DispatcherItem(subscriber: subscriber, handler: handler, once: once))
		minimize(subscriber: nil, removeOnce: false)
	}

	func remove(subscriber: AnyObject) {
		minimize(subscriber: subscriber, removeOnce: false)
	}

	func reset() {
		items = [DispatcherItem<Type>]()
	}

	private func minimize(subscriber: AnyObject?, removeOnce once: Bool) {
		items = items.filter {
			guard let itemSubscriber = $0.subscriber else { return false }
			var result = once ? !$0.once : true
			if result {
				if let validSubscriber = subscriber {
					result = itemSubscriber !== validSubscriber
				}
			}
			return result
		}
	}

}
