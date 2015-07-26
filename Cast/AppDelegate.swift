//
//  AppDelegate.swift
//  Cast
//
//  Created by Leonardo on 18/07/2015.
//  Copyright © 2015 Leonardo Faoro. All rights reserved.
//

import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    
    let statusBar = LFStatusBar()
    
    func applicationDidFinishLaunching(aNotification: NSNotification) {
        // Insert code here to initialize your application
        
        
    }
    
    override func awakeFromNib() {
        
		//create the statusbar and its menu and installs it on the systemstatusbar (3)
		statusBar.displayStatusBarItem()

    }
    
    func applicationWillTerminate(aNotification: NSNotification) {
        // Insert code here to tear down your application
    }
    
    
}

