/*
See LICENSE folder for this sample’s licensing information.

Abstract:
View controller containing the lower UI controls and the embedded child view controller (split view controller).
*/

import Cocoa

class WindowViewController: NSViewController {
    
    // MARK: Outlets
    
    @IBOutlet private weak var addButton: NSPopUpButton!
    @IBOutlet private weak var removeButton: NSButton!
    @IBOutlet private weak var progIndicator: NSProgressIndicator!
    
    // MARK: View Controller Lifecycle
    
    override func viewDidLoad() {
        /** Note: We keep the left split view item from growing as the window grows by setting its
         	holding priority to 200, and the right to 199. The view with the lowest priority will be
         	the first to take on additional width if the split view grows or shrinks.
         */
        super.viewDidLoad()
        
        // Insert an empty menu item at the beginning of the drown down button's menu and add its image.
        let addImage = NSImage(named: NSImage.addTemplateName)!
        addImage.size = NSSize(width: 10, height: 10)
        let addMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        addMenuItem.image = addImage
        addButton.menu?.insertItem(addMenuItem, at: 0)
        addButton.menu?.autoenablesItems = false
    }
    
    override func viewWillAppear() {
        super.viewWillAppear()
        
        /** Notification so we know when the tree controller's selection has changed selection.
    		Note: we start observing after our outline view is populated so we don't receive
     		unnecessary notifications at startup.
		*/
   		NotificationCenter.default.addObserver(
            self,
            selector: #selector(selectionDidChange(_:)),
            name: Notification.Name(OutlineViewController.NotificationNames.selectionChanged),
            object: nil)
        
        // Notification so we know when the icon view controller is done populating its content.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(contentReceived(_:)),
            name: Notification.Name(IconViewController.NotificationNames.receivedContent),
            object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(
            self,
            name: Notification.Name(OutlineViewController.NotificationNames.selectionChanged),
            object: nil)
        NotificationCenter.default.removeObserver(
            self,
            name: Notification.Name(IconViewController.NotificationNames.receivedContent),
            object: nil)
    }
    
    // MARK: NSNotifications
    
    // Notification sent from IconViewController class, indicating the file system content has been received.
    @objc
    private func contentReceived(_ notification: Notification) {
        progIndicator.isHidden = true
        progIndicator.stopAnimation(self)
    }
    
    // Listens for selection changes to the NSTreeController so to update the UI elements (add/remove buttons).
    @objc
    private func selectionDidChange(_ notification: Notification) {
        // Examine the current selection and adjust the UI elements.
        
        // Notification's object must be the tree controller.
        guard let treeController = notification.object as? NSTreeController else { return }
    
        // Both add and remove buttons are enabled only if there is a current outline selection.
        removeButton.isEnabled = !treeController.selectedNodes.isEmpty
        addButton.isEnabled = !treeController.selectedNodes.isEmpty
        
        if !treeController.selectedNodes.isEmpty {
            if treeController.selectedNodes.count == 1 {
                let selectedNode = treeController.selectedNodes[0]
                if let item = OutlineViewController.node(from: selectedNode as Any) {
                    // You can only add to a non-url based node.
                    addButton.isEnabled = item.canAddTo
                    
                    // A directory is selected, this could take a while to populate both master and detail).
                    if item.isDirectory {
                        // We are populating the detail view controler with contents of a folder on disk (may take a while).
                        progIndicator.isHidden = false
                        progIndicator.startAnimation(self)
                    }
                }
            }
        }
    }
    
    // MARK: Actions
    
    struct NotificationNames {
        // Notification to instruct OutlineViewController to add a folder.
        static let addFolder = "AddFolderNotification"
        // Notification to instruct OutlineViewController to add a picture.
        static let addPicture = "AddPictureNotification"
        // Notification to instruct OutlineViewController to remove an item.
        static let removeItem = "RemoveItemNotification"
    }

    @IBAction func addFolderAction(_: AnyObject) {
        // Post notification to OutlineViewController to add a new folder group.
        NotificationCenter.default.post(name: Notification.Name(NotificationNames.addFolder), object: nil)
    }
    
    @IBAction func addPictureAction(_: AnyObject) {
        // Post notification to OutlineViewController to add a new picture.
        NotificationCenter.default.post(name: Notification.Name(NotificationNames.addPicture), object: nil)
    }
    
    @IBAction func removeAction(_: AnyObject) {
        // Post notification to OutlineViewController to remove an item.
        NotificationCenter.default.post(name: Notification.Name(NotificationNames.removeItem), object: nil)
    }
    
}
