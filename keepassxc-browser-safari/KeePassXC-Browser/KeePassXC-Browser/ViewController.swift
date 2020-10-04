//
//  ViewController.swift
//  KeePassXC-Browser
//
//  Created by Humanoid on 21.9.2020.
//

import Cocoa
import SafariServices.SFSafariApplication
import SafariServices.SFSafariExtensionManager
import os.log

let appName = "KeePassXC-Browser"
let extensionBundleIdentifier = "com.keepassxreboot.KeePassXC-Browser-Extension"

class ViewController: NSViewController {

    @IBOutlet var appNameLabel: NSTextField!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.appNameLabel.stringValue = appName
        SFSafariExtensionManager.getStateOfSafariExtension(withIdentifier: extensionBundleIdentifier) { (state, error) in
            guard let state = state, error == nil else {
                // Insert code to inform the user that something went wrong.
                return
            }

            DispatchQueue.main.async {
                if (state.isEnabled) {
                    self.appNameLabel.stringValue = "\(appName)'s extension is currently on."
                } else {
                    self.appNameLabel.stringValue = "\(appName)'s extension is currently off. You can turn it on in Safari Extensions preferences."
                }
            }
        }
    }
    
    @IBAction func openSafariExtensionPreferences(_ sender: AnyObject?) {
        SFSafariApplication.showPreferencesForExtension(withIdentifier: extensionBundleIdentifier) { error in
            guard error == nil else {
                // Insert code to inform the user that something went wrong.
                return
            }

            DispatchQueue.main.async {
                NSApplication.shared.terminate(nil)
            }
        }
    }
    
    @IBAction func sendMessageToExtension(_ sender: AnyObject?) {
        let messageName = "Hello from App"
        let messageInfo = ["AdditionalInformation":"Goes Here"]
        SFSafariApplication.dispatchMessage(withName: messageName, toExtensionWithIdentifier: extensionBundleIdentifier, userInfo: messageInfo) { error in
            debugPrint("Message attempted. Error info: \(String.init(describing: error))")
        }
    }

}