/*
See LICENSE folder for this sample’s licensing information.

Abstract:
View controller object to host the icon collection view to display contents of a folder.
*/

import Cocoa

class IconViewController: NSViewController {
    
    struct NotificationNames {
        // Notification for indicating file system content has been received.
        static let receivedContent = "ReceivedContentNotification"
    }

    // Key values for the icon view dictionary.
    struct IconViewKeys {
        static let keyName = "name"
        static let keyIcon = "icon"
    }
    
    @objc private dynamic var icons: [[String: Any]] = []
    
    var url: URL? {
        didSet {
            // Our url has changed, notify ourselves to update our data source.
            DispatchQueue.global(qos: .default).async {
                // Asynchronously fetch the contents of this url.
                self.gatherContents(self.url!)
            }
        }
    }
    
    var nodeContent: Node? {
        didSet {
            // Our base node has changed, notify ourselves to update our data source.
            gatherContents(nodeContent!)
        }
    }
    
    // The incoming object is the array of file system objects to display.
    private func updateIcons(_ iconArray: [[String: Any]]) {
        icons = iconArray
        
        // Notify interested view controllers that the content has been obtained.
        NotificationCenter.default.post(name: Notification.Name(IconViewController.NotificationNames.receivedContent), object: nil)
    }
    
    /**	Gathering the contents and their icons could be expensive.
     	This method is being called on a separate thread to avoid blocking the UI.
     */
    private func gatherContents(_ inObject: Any) {
        autoreleasepool {
            
            var contentArray: [[String: Any]] = []
            
            if inObject is Node {
                // We are populating our collection view from a Node.
                for node in nodeContent!.children {
                    // The node's icon was set to a smaller size before, for this collection view we need to make it bigger.
                    var content: [String: Any] = [IconViewKeys.keyName: node.title]
                    
                    if let icon = node.nodeIcon.copy() as? NSImage {
                        content[IconViewKeys.keyIcon] = icon
                    }

                    contentArray.append(content)
                }
            } else {
                // We are populating our collection view from a file system directory URL.
                if let urlToDirectory = inObject as? URL {
                    do {
                        let fileURLs =
                            try FileManager.default.contentsOfDirectory(at: urlToDirectory,
                                                                        includingPropertiesForKeys: [],
                                                                        options: [])
                        for element in fileURLs {
                            // Only allow visible objects.
                            let isHidden = element.isHidden
                            if !isHidden {
                                let elementNameStr = element.localizedName
                                let elementIcon = element.icon
                                // File system object is visible so add to our content array.
                                contentArray.append([
                                    IconViewKeys.keyIcon: elementIcon,
                                    IconViewKeys.keyName: elementNameStr
                                ])
                            }
                        }
                    } catch _ {}
                }
            }
            
            // Call back on the main thread to update the icons in our view.
            DispatchQueue.main.async {
                self.updateIcons(contentArray)
            }
        }
    }
    
}
