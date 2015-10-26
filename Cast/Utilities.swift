//
//  Utilities.swift
//  Cast
//

import Cocoa


func extractExcerptFromString(string: String, length: Int) -> String {
	if string.endIndex > string.startIndex.advancedBy(length) {
		return string.substringWithRange(string.startIndex ... (string.startIndex.advancedBy(length)))
	} else {
		return string
	}
}


typealias MenuTypeTuple = (tag:Int, title:String, imageName:String)


func buildMenuPopup(source source: [MenuTypeTuple]) -> NSMenu {
	let menuItemList = source.map {
		tag, title, imageName -> NSMenuItem in
		let m = NSMenuItem()
		m.tag = tag
		m.title = title
		m.onStateImage = NSImage(named: imageName)
		m.onStateImage?.template = false
		return m
	}
	
	let menu = NSMenu()
	for each in menuItemList {
		menu.addItem(each)
	}
	
	return menu
}


extension NSMenu {
	func addSeparator() {
		self.addItem(NSMenuItem.separatorItem())
	}
	func addItemWithTitle(title:String, action:MenuSelectorAction, key:String = "", target: MenuActionHandler? = nil, representedObject:NSObject? = nil){
		let m = NSMenuItem(title: title, action: action.rawValue, keyEquivalent: key)
		m.representedObject = representedObject
		m.target = target
	
		self.addItem(m)
	}
}


extension NSMenuItem {
	func setItemWithTitle(title:String, action:MenuSelectorAction, key:String = "", target: MenuActionHandler? = nil, representedObject:NSObject? = nil) -> NSMenuItem {
		let m = NSMenuItem(title: title, action: action.rawValue, keyEquivalent: key)
		m.representedObject = representedObject
		m.target = target
		return m
	}	
}