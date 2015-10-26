//
//  Preferences.swift
//  Cast
//

import Cocoa


struct PreferencesModel {
	var gistService: Int
	var shortenService: Int
	var secretGist: Bool
	
	func load() {
	}
	
	func save() {
	}
}


class PreferencesViewModel: NSObject {
	@IBOutlet weak var secretGist: NSButton!
	@IBOutlet weak var shortenService: NSPopUpButton!
	@IBOutlet weak var gistService: NSPopUpButton!
	@IBOutlet weak var loginButton: NSButton!
	
	override func awakeFromNib() {
		gistService.imagePosition = .ImageLeft
		gistService.menu = GistService.popupMenuList()
		shortenService.imagePosition = .ImageLeft
		shortenService.menu = ShortenService.popupMenuList()
	}
	
	var model: PreferencesModel! {
		didSet {
			shortenService.selectItemWithTag(1)
			gistService.selectItemWithTag(2)
			secretGist.integerValue = 0
		}
	}
}


class PreferencesController: NSWindowController, NSWindowDelegate {
	@IBOutlet var viewModel: PreferencesViewModel!
	
	override var windowNibName: String? {
		return "PreferenceWindow"
	}
	
	override func windowDidLoad() {
		super.windowDidLoad()
		self.window?.delegate = self
		viewModel.model = PreferencesModel(gistService: 0, shortenService: 0, secretGist: false)
	}
	
	func windowWillClose(notification: NSNotification) {
		
	}
}

