/* 
    Copyright (C) 2016 Stephen Oliver <steve@infincia.com>

    This code is distributed under the GNU General Public License, version 2 
    (or at your option any later version).
    
    3rd party libraries may be distributed under an alternate Open Source license.
    
    See the Acknowledgements file included with this code for details.
    
*/

import Foundation
import Alamofire
import ServiceManagement

public extension Dictionary {
    func merge(dict: Dictionary<Key,Value>) -> Dictionary<Key,Value> {
        var c = self
        for (key, value) in dict {
            c[key] = value
        }        
        return c
    }    
}

class Helpers : NSObject {

    class func findNodeInstallation() -> NSURL? {
    
        let fileManager = NSFileManager.defaultManager()
        
        let applicationSupportURL = fileManager.URLsForDirectory(.ApplicationSupportDirectory, inDomains: .UserDomainMask).first!
        
        let applicationsURL = fileManager.URLsForDirectory(.AllApplicationsDirectory, inDomains:.SystemDomainMask).first!

        // existing or user-defined location
        var customInstallationURL: NSURL? = nil
        if let customPath = NSUserDefaults.standardUserDefaults().objectForKey(FNNodeInstallationDirectoryKey) as? String {
            customInstallationURL = NSURL.fileURLWithPath(customPath).URLByStandardizingPath
        }
        
        // new default ~/Library/Application Support/Freenet
        let defaultInstallationURL = applicationSupportURL.URLByAppendingPathComponent(FNNodeInstallationPathname, isDirectory:true)

        // old default /Applications/Freenet
        let deprecatedInstallationURL = applicationsURL.URLByAppendingPathComponent(FNNodeInstallationPathname, isDirectory:true)

        if self.validateNodeInstallationAtURL(customInstallationURL) {
            return customInstallationURL
        }
        else if self.validateNodeInstallationAtURL(defaultInstallationURL) {
            return defaultInstallationURL
        }
        else if self.validateNodeInstallationAtURL(deprecatedInstallationURL) {
            return deprecatedInstallationURL
        }
        return nil
    }

    class func validateNodeInstallationAtURL(nodeURL: NSURL?) -> Bool {
        guard let nodeURL = nodeURL else {
            return false
        }
        
        
        let fileURL = nodeURL.URLByAppendingPathComponent(FNNodeRunscriptPathname)
        
        let path = fileURL.path!
        
        let fileManager = NSFileManager.defaultManager()
        
        if fileManager.fileExistsAtPath(path, isDirectory:nil) {
            return true
        }
        return false
    }

    class func displayNodeMissingAlert() {
        // no installation found, tell the user to pick a location or start the installer
        dispatch_async(dispatch_get_main_queue(), {         
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("A Freenet installation could not be found.", comment: "String informing the user that no Freenet installation could be found")
            alert.informativeText = NSLocalizedString("Would you like to install Freenet now, or locate an existing Freenet installation?", comment: "String asking the user whether they would like to install freenet or locate an existing installation")
            alert.addButtonWithTitle(NSLocalizedString("Install Freenet", comment: "Button title"))

            alert.addButtonWithTitle(NSLocalizedString("Find Installation", comment: "Button title"))
            alert.addButtonWithTitle(NSLocalizedString("Quit", comment: ""))

            let button = alert.runModal()
            
            if button == NSAlertFirstButtonReturn {
                // display installer
                NSNotificationCenter.defaultCenter().postNotificationName(FNNodeShowInstallerWindow, object:nil)
            }
            else if button == NSAlertSecondButtonReturn {
                // display node finder panel
                NSNotificationCenter.defaultCenter().postNotificationName(FNNodeShowNodeFinderInSettingsWindow, object:nil)
            }
            else if button == NSAlertThirdButtonReturn {
                // display node finder panel
                NSApp.terminate(self)
            }
        }) 
    }

    class func displayUninstallAlert() {
        // ask the user if they really do want to uninstall Freenet
        dispatch_async(dispatch_get_main_queue(), {         
            let alert:NSAlert! = NSAlert()
            alert.messageText = NSLocalizedString("Uninstall Freenet now?", comment: "Title of window")
            alert.informativeText = NSLocalizedString("Uninstalling Freenet is immediate and irreversible, are you sure you want to uninstall Freenet now?", comment: "String asking the user whether they would like to uninstall freenet")
            alert.addButtonWithTitle(NSLocalizedString("Uninstall Freenet", comment: "Button title"))
            alert.addButtonWithTitle(NSLocalizedString("Cancel", comment: "Button title"))

            let button:Int = alert.runModal()
            if button == NSAlertFirstButtonReturn {
                // start uninstallation
                NSNotificationCenter.defaultCenter().postNotificationName(FNNodeUninstall, object:nil)
            }
            else if button == NSAlertSecondButtonReturn {
                // user canceled, don't do anything
            }
        }) 
    }

    class func installedWebBrowsers() -> [Browser]? {
        let url = NSURL(string: "https://")!
        
        let roles = LSRolesMask.Viewer
        
        if let appUrls = LSCopyApplicationURLsForURL(url, roles)?.takeRetainedValue() {
            // Extract the app names and sort them for prettiness.
            var appNames = [Browser]()
            guard let appUrls = appUrls as NSArray as? [NSURL] else {
                return nil
            }

            for url in appUrls {
                appNames.append(Browser.browserWithFileURL(url))
            }

            return appNames
        }
        return nil
    }

    // MARK: -
    // MARK: - Migrations

    class func migrateLaunchAgent() throws {
        let fileManager = NSFileManager.defaultManager()
    
        let libraryDirectory = fileManager.URLsForDirectory(.LibraryDirectory, inDomains: .UserDomainMask).first
        
        if let launchAgentsDirectory = libraryDirectory?.URLByAppendingPathComponent("LaunchAgents", isDirectory:true) {
            let launchAgent:NSURL! = launchAgentsDirectory.URLByAppendingPathComponent(FNNodeLaunchAgentPathname)
            if fileManager.fileExistsAtPath(launchAgent.path!, isDirectory:nil) {
                try fileManager.removeItemAtURL(launchAgent)
            }
        }
    }
    
    class func migrateLaunchAtStart() {
        let startAtLaunch = NSUserDefaults.standardUserDefaults().boolForKey(FNStartAtLaunchKey)
        Helpers.enableLoginItem(startAtLaunch)
    }

    class func createGist(string: String, withTitle title: String, success: FNGistSuccessBlock, failure: FNGistFailureBlock) {
        let fileName = "FreenetTray - \(title).txt"
        let params: [String: AnyObject] = [
            "description": title,
            "public": true,
            "files": [
                fileName: [
                    "content": string
                ]
            ]
        ]
        
        let headers: [String: String] = [
            "Content-Type": "application/vnd.github.v3+json",
            "Accept": "application/json",
            "User-Agent": "FreenetTray for OS X"
        ]
        
        Alamofire.request(.POST, "https://\(FNGithubAPI)/gists", parameters: params, headers: headers, encoding: .JSON)
            .validate()
            .responseJSON { response in                
            switch response.result {
            case .Success(let data):
                let response = data as! [String: AnyObject]
                let html_url = response["html_url"] as! String
                let gist = NSURL(fileURLWithPath: html_url)
                success(gist)
            case .Failure(let error):
                let body = response.request!.HTTPBody
                let headers = response.request!.allHTTPHeaderFields!
                let string = String(data: body!, encoding: NSUTF8StringEncoding)!
                print(headers)
                print(string)

                print(response.response!)
                
                failure(error)
            }
        }
    }
    
    class func enableLoginItem(state: Bool) -> Bool {

        let helper = NSBundle.mainBundle().bundleURL.URLByAppendingPathComponent("Contents/Library/LoginItems/FreenetTray Helper.app", isDirectory: true)

        if LSRegisterURL(helper, state) != noErr {
            print("Failed to LSRegisterURL \(helper)")
        }

        if (SMLoginItemSetEnabled(("org.freenetproject.FreenetTray-Helper" as CFStringRef), true)) {
            return true
        }
        else {
            print("Failed to SMLoginItemSetEnabled \(helper)")
            return false
        }
    }
}