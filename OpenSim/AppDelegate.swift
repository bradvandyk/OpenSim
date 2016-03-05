//
//  AppDelegate.swift
//  SimPholders
//
//  Created by Luo Sheng on 11/9/15.
//  Copyright © 2015 Luo Sheng. All rights reserved.
//

import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    @IBOutlet weak var window: NSWindow!
    
    var statusItem: NSStatusItem!
    var watcher: DirectoryWatcher!
    var subWatchers: [DirectoryWatcher?]?
    var block: dispatch_cancelable_block_t?

    func applicationDidFinishLaunching(aNotification: NSNotification) {
        statusItem = NSStatusBar.systemStatusBar().statusItemWithLength(NSVariableStatusItemLength)
        statusItem.image = NSImage(named: "menubar")
        statusItem.image!.template = true
        statusItem.menu = NSMenu()
        
        buildMenu()
        
        watcher = DirectoryWatcher(URL: URLHelper.deviceURL)
        watcher.completionCallback = {
            self.reloadWhenReady()
            self.buildSubWatchers()
        }
        try! watcher.start()
        self.buildSubWatchers()
    }
    
    private func reloadWhenReady() {
        dispatch_cancel_block_t(self.block)
        self.block = dispatch_block_t(1) {
            self.buildMenu()
        }
    }
    
    private func buildSubWatchers() {
        subWatchers?.forEach({ (watcher) -> () in
            watcher?.stop()
        })
        subWatchers = try! NSFileManager.defaultManager().contentsOfDirectoryAtURL(URLHelper.deviceURL, includingPropertiesForKeys: FileInfo.prefetchedProperties, options: .SkipsSubdirectoryDescendants).map { URL in
            guard let info = FileInfo(URL: URL) where info.isDirectory else {
                return nil
            }
            let watcher = DirectoryWatcher(URL: URL)
            watcher.completionCallback = {
                self.reloadWhenReady()
            }
            try watcher.start()
            return watcher
        }
    }
    
    private func buildFileInfoList() -> [FileInfo?] {
        return try! NSFileManager.defaultManager().contentsOfDirectoryAtURL(URLHelper.deviceURL, includingPropertiesForKeys: FileInfo.prefetchedProperties, options: .SkipsSubdirectoryDescendants).map { FileInfo(URL: $0) }
    }
    
    func buildMenu() {
        statusItem.menu!.removeAllItems()
        
        // extract devices and sort based on runtime version so latest is on the bottom
        DeviceManager.defaultManager.reload()
        let iOSDevices = DeviceManager.defaultManager.deviceMapping

        var currentRuntime = ""
        iOSDevices.forEach { device in
            if (currentRuntime != "" && device.runtime.name != currentRuntime) {
                // add filler
                statusItem.menu?.addItem(NSMenuItem.separatorItem())
            }
            
            currentRuntime = device.runtime.name
            
            let deviceMenuItem = statusItem.menu?.addItemWithTitle(device.fullName, action: nil, keyEquivalent: "")
            deviceMenuItem?.onStateImage = NSImage(named: "active")
            deviceMenuItem?.offStateImage = NSImage(named: "inactive")
            deviceMenuItem?.state = device.state == .Booted ? NSOnState : NSOffState
            deviceMenuItem?.submenu = NSMenu()
            device.applications.forEach { app in
                let appMenuItem = deviceMenuItem?.submenu?.addItemWithTitle(app.bundleDisplayName, action: "appMenuItemClicked:", keyEquivalent: "")
                appMenuItem?.representedObject = DeviceApplicationPair(device: device, application: app)
            }
        }
        
        statusItem.menu!.addItem(NSMenuItem.separatorItem())
        // reload needed since DirectoryWatcher might not be working
        statusItem.menu!.addItemWithTitle("Reload", action: "reload", keyEquivalent: "r")
        statusItem.menu!.addItemWithTitle("Quit", action: "quit", keyEquivalent: "q")
    }
    
    func quit() {
        NSApplication.sharedApplication().terminate(self)
    }
    
    func reload() {
        // needed since
        self.buildMenu()
    }
    
    func dialogOKCancel(question: String, text: String) -> Bool {
        let myPopup: NSAlert = NSAlert()
        myPopup.messageText = question
        myPopup.informativeText = text
        myPopup.alertStyle = NSAlertStyle.CriticalAlertStyle
        myPopup.addButtonWithTitle("OK")
        myPopup.addButtonWithTitle("Cancel")
        let res = myPopup.runModal()
        if res == NSAlertFirstButtonReturn {
            return true
        }
        return false
    }
    
    func appMenuItemClicked(sender: NSMenuItem) {
        if let pair = sender.representedObject as? DeviceApplicationPair,
            appState = pair.device.fetchApplicationState(pair.application) {
                // if control click
                if let event = NSApp.currentEvent where event.modifierFlags.contains(.ControlKeyMask) {
                    let answer = dialogOKCancel("Confirm Delete?", text: "Are you sure you want to delete \(pair.application.bundleDisplayName) for \(pair.device.fullName)")
                    if answer {
                        // delete the app
                        shell("/usr/bin/xcrun", arguments: ["simctl", "uninstall", pair.device.UDID, pair.application.bundleID])
                        // might not need this if DirectoryWatcher is working
                        self.buildMenu()
                    }
                }
                else {
                    // open the app directory
                    if NSFileManager.defaultManager().fileExistsAtPath(appState.sandboxPath) {
                        NSWorkspace.sharedWorkspace().openURL(NSURL(fileURLWithPath: appState.sandboxPath))
                    }
                }
        }
    }

    func applicationWillTerminate(aNotification: NSNotification) {
        // Insert code here to tear down your application
    }


}

