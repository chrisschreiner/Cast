//
//  Stub.swift
//  Cast
//

import Cocoa
import RxCocoa
import RxSwift


class StubHandler: NSObject {
    @IBOutlet var result: NSTextView!
    @IBOutlet weak var lastResult: NSTextField!
	@IBOutlet weak var pboard: NSTextField!
    @IBOutlet weak var appendOutput: NSButton!
    @IBOutlet weak var openLastResult: NSButton!
	
    var appendOutputToggle: Bool {
        get {
            return appendOutput.state == 0
        }
        set {
			guard appendOutput != nil else {return}
            appendOutput.state = newValue ? 0 : 1
        }
    }

    @IBAction func openURLFromLastResult(sender: NSButton) {
		NSWorkspace.sharedWorkspace().openURL(NSURL(string:lastResult.stringValue)!)
	}

    @IBAction func toggleAppendOutput(sender: NSButton) {
    }

	@IBAction func sampleAction(sender: NSObject) {
		getPasteboardItems()
			.observeOn(MainScheduler.sharedInstance)
			.subscribeNext{ value in
				if case PBItem.Text(let s) = value {
					self.pboard.stringValue = s
				}
		}
	}
	
	@IBAction func sendSampleGist(sender: NSObject) {
		let gistOptions = GistOptions()
		let gist = GistClient(options: gistOptions)

		gist.setGist(content: "This is a gist")
			.observeOn(MainScheduler.sharedInstance)
			.subscribeNext {(url:NSURL) in
			let s = NSAttributedString(string: url.description + "\n")
				if self.appendOutputToggle {
					self.clearResult()
				}
				
				self.result.textStorage?.appendAttributedString(s)
				self.lastResult.stringValue = url.description
				self.openLastResult.enabled = !self.lastResult.stringValue.isEmpty
		}
	}
	
	override func awakeFromNib() {
		super.awakeFromNib()
		appendOutputToggle = true
        lastResult.stringValue = ""
		self.openLastResult.enabled = false
	}

    func clearResult() {
        result.textStorage?.setAttributedString(NSAttributedString(string: ""))
    }
}


class StubController: NSWindowController, NSWindowDelegate {
    @IBOutlet var stubHandler: StubHandler!

    override var windowNibName: String? {
        return "StubWindow"
    }

    override func windowDidLoad() {
        super.windowDidLoad()
        self.window?.delegate = self
    }

    func windowWillClose(notification: NSNotification) {

    }
}