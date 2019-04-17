/*
See LICENSE folder for this sample’s licensing information.

Abstract:
The master view controller containing the NSOutlineView and NSTreeController.
*/

import Cocoa

class OutlineViewController: NSViewController,
    							NSTextFieldDelegate, // To respond text field's edit sending.
								NSUserInterfaceValidations { // To enable/disable menu items for the outline view.
    // MARK: Constants
    
    struct NameConstants {
        // Default name for added folders and leafs.
        static let untitled = NSLocalizedString("untitled string", comment: "")
        // Places group title.
        static let places = NSLocalizedString("places string", comment: "")
        // Pictures group title.
        static let pictures = NSLocalizedString("pictures string", comment: "")
    }

    struct NotificationNames {
        // Notification that the tree controller's selection has changed (used by SplitViewController).
        static let selectionChanged = "selectionChangedNotification"
    }
    
    // MARK: Outlets
    
    // The data source backing of the NSOutlineView.
    @IBOutlet weak var treeController: NSTreeController!

    @IBOutlet weak var outlineView: OutlineView! {
        didSet {
            // As soon as we have our outline view loaded, we populate its content tree controller.
            populateOutlineContents()
        }
    }
    
	@IBOutlet private weak var placeHolderView: NSView!
    
    // MARK: Instance Variables
    
    // Observer of tree controller when it's selection changes using KVO.
    private var treeControllerObserver: NSKeyValueObservation?
    
    // Outline view content top-level content (backed by NSTreeController).
    @objc dynamic var contents: [AnyObject] = []
    
  	var rowToAdd = -1 // A flagged row being added (for later renaming after it was added).
    
    // Directory for accepting promised files.
    lazy var promiseDestinationURL: URL = {
        let promiseDestinationURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Drops")
        try? FileManager.default.createDirectory(at: promiseDestinationURL, withIntermediateDirectories: true, attributes: nil)
        return promiseDestinationURL
    }()

    private var iconViewController: IconViewController!
    private var fileViewController: FileViewController!
    private var imageViewController: ImageViewController!
    private var multipleItemsViewController: NSViewController!
    
    var savedSelection: [IndexPath] = []
    
    // MARK: View Controller Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // We want to determine the contextual menu for the outline view.
   		outlineView.customMenuDelegate = self
        
        // Dragging items out: Set the default operation mask so we can drag (copy) items to outside this app, and delete to the Trash can.
        outlineView?.setDraggingSourceOperationMask([.copy, .delete], forLocal: false)
        
        // Register for drag types coming in, we want to receive file promises from Photos, Mail, Safari, etc.
        outlineView.registerForDraggedTypes(NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) })
        
        // We are interested in these drag types: our own type (outline row number), and for fileURLs.
		outlineView.registerForDraggedTypes([
      		.nodeRowPasteBoardType, // Our internal drag type, the outline view's row number for internal drags.
            NSPasteboard.PasteboardType.fileURL // To receive file URL drags.
            ])

        /** Disclose the two root outline groups (Places and Pictures) at first launch.
         	With all subsequent launches, these disclosure states will be determined by the
         	autosave disclosure states.
         */
        let defaults = UserDefaults.standard
        let initialDisclosure = defaults.string(forKey: "initialDisclosure")
        if initialDisclosure == nil {
            outlineView.expandItem(treeController.arrangedObjects.children![0])
            outlineView.expandItem(treeController.arrangedObjects.children![1])
            defaults.set("initialDisclosure", forKey: "initialDisclosure")
        }
        
        // Load the icon view controller from storyboard later use as our Detail view.
        iconViewController =
            storyboard!.instantiateController(withIdentifier: "IconViewController") as? IconViewController
        iconViewController.view.translatesAutoresizingMaskIntoConstraints = false
        
        // Load the file view controller from storyboard later use as our Detail view.
        fileViewController =
            storyboard!.instantiateController(withIdentifier: "FileViewController") as? FileViewController
        fileViewController.view.translatesAutoresizingMaskIntoConstraints = false
        
        // Load the image view controller from storyboard later use as our Detail view.
        imageViewController =
            storyboard!.instantiateController(withIdentifier: "ImageViewController") as? ImageViewController
        imageViewController.view.translatesAutoresizingMaskIntoConstraints = false
        
        // Load the multiple items selected view controller from storyboard later use as our Detail view.
        multipleItemsViewController =
            storyboard!.instantiateController(withIdentifier: "MultipleSelection") as? NSViewController
		multipleItemsViewController.view.translatesAutoresizingMaskIntoConstraints = false
        
        /** Note: The following will make our outline view appear with gradient background, and proper
         	selection to behave like the Finder's side-bar, iTunes, etc.
         */
        //outlineView.selectionHighlightStyle = .sourceList // But we already do this in the storyboard.
        
        // Setup observers for the outline view's selection, adding items, and removing items.
        setupObservers()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(
            self,
            name: Notification.Name(WindowViewController.NotificationNames.addFolder),
            object: nil)
        NotificationCenter.default.removeObserver(
            self,
        	name: Notification.Name(WindowViewController.NotificationNames.addPicture),
         	object: nil)
        NotificationCenter.default.removeObserver(
            self,
    		name: Notification.Name(WindowViewController.NotificationNames.removeItem),
   			object: nil)
    }
    
    // MARK: OutlineView Setup
    
    // Take the currently selected node and select its parent.
    private func selectParentFromSelection() {
        if !treeController.selectedNodes.isEmpty {
            let firstSelectedNode = treeController.selectedNodes[0]
            if let parentNode = firstSelectedNode.parent {
                // Select the parent.
                let parentIndex = parentNode.indexPath
                treeController.setSelectionIndexPath(parentIndex)
            } else {
                // No parent exists (we are at the top of tree), so make no selection in our outline.
                let selectionIndexPaths = treeController.selectionIndexPaths
                treeController.removeSelectionIndexPaths(selectionIndexPaths)
            }
        }
    }
	
    // Called by drag and drop from the Finder.
    func addFileSystemObject(_ url: URL, indexPath: IndexPath) {
        let node = OutlineViewController.fileSystemNode(from: url)
        treeController.insert(node, atArrangedObjectIndexPath: indexPath)
        
        if url.isFolder {
            do {
                node.identifier = NSUUID().uuidString
                // It's a folder node, find it's children
                let fileURLs =
                    try FileManager.default.contentsOfDirectory(at: node.url!,
                                                                includingPropertiesForKeys: [],
                                                                options: [.skipsHiddenFiles])
                // Move indexPath one level deep for insertion.
                let newIndexPath = indexPath
                let finalIndexPath = newIndexPath.appending(0)
                
                addFileSystemObjects(fileURLs, indexPath: finalIndexPath)
            } catch _ {
                // No content at this URL.
            }
        } else {
            // This is just a leaf node, no children to insert.
        }
    }

    private func addFileSystemObjects(_ entries: [URL], indexPath: IndexPath) {
        // First sort the array of URLs.
        var sorted = entries
        sorted.sort( by: { $0.lastPathComponent > $1.lastPathComponent })
        
        // Insert the sorted URL array into the tree controller.
        for entry in sorted {
            if entry.isFolder {
                // It's a folder node, add the folder.
                let node = OutlineViewController.fileSystemNode(from: entry)
                node.identifier = NSUUID().uuidString
                treeController.insert(node, atArrangedObjectIndexPath: indexPath)
                
                do {
                    let fileURLs =
                        try FileManager.default.contentsOfDirectory(at: entry,
                                                                    includingPropertiesForKeys: [],
                                                                    options: [.skipsHiddenFiles])
                    if !fileURLs.isEmpty {
                        // Move indexPath one level deep for insertions.
                        let newIndexPath = indexPath
                        let final = newIndexPath.appending(0)
                        
                        addFileSystemObjects(fileURLs, indexPath: final)
                    }
                } catch _ {
                    // No content at this URL.
                }
            } else {
                // It's a leaf node, add the leaf.
                addFileSystemObject(entry, indexPath: indexPath)
            }
        }
    }

    private func addGroupNode(_ folderName: String, identifier: String) {
        let node = Node()
        node.type = .container
        node.title = folderName
        node.identifier = identifier
    
        // Insert the group node.
        
        // Get the insertion indexPath from the current selection.
        var insertionIndexPath: IndexPath
        // If there is no selection, we will add a new group to the end of the contents array.
        if treeController.selectedObjects.isEmpty {
            // There's no selection so add the folder to the top-level and at the end.
            insertionIndexPath = IndexPath(index: contents.count)
        } else {
            /** Get the index of the currently selected node, then add the number its children
                to the path. This will give us an index which will allow us to add a node to the
                end of the currently selected node's children array.
             */
            insertionIndexPath = treeController.selectionIndexPath!
            if let selectedNode = treeController.selectedObjects[0] as? Node {
                // User is trying to add a folder on a selected folder, so select add the selection to the children.
                insertionIndexPath.append(selectedNode.children.count)
            }
        }
        
        treeController.insert(node, atArrangedObjectIndexPath: insertionIndexPath)
    }
    
    private func addNode(_ node: Node) {
        // Find the selection to insert our node.
        var indexPath: IndexPath
        if treeController.selectedObjects.isEmpty {
            // No selection, just add the child to the end of the tree.
            indexPath = IndexPath(index: contents.count)
        } else {
            // We have a selection, insert at the end of the selection.
            indexPath = treeController.selectionIndexPath!
            if let node = treeController.selectedObjects[0] as? Node {
                indexPath.append(node.children.count)
            }
        }
        
        // The child to insert has a valid URL, use its display name as the node title.
        // We need to take the url and obtain the display name (non escaped with no extension).
        if node.isURLNode {
            node.title = node.url!.localizedName
        }
        
        // The user is adding a child node, tell the controller directly.
        treeController.insert(node, atArrangedObjectIndexPath: indexPath)
        
        if !node.isDirectory {
        	// For leaf children we need to select it's parent for further additions.
        	selectParentFromSelection()
        }
    }
    
    // MARK: Outline Content
    
    // Unique nodeIDs for the two top level group nodes.
    static let picturesID = "1000"
    static let placesID = "1001"
    
    private func addPlacesGroup() {
        // Add the "Places" outline group section.
        // Note that the nodeID and expansion restoration ID are shared.
        
        addGroupNode(OutlineViewController.NameConstants.places, identifier: OutlineViewController.placesID)
        
        // Add the Applications folder inside "Places".
        let appsURLs = FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask)
        addFileSystemObject(appsURLs[0], indexPath: IndexPath(indexes: [0, 0]))
        
        treeController.setSelectionIndexPath(nil) // Start back up to the root level.
    }
    
    // Populate the tree controller from disk-based dictionary (DataSource.plist).
    private func addPicturesGroup() {
        // Add the "Pictures" section.
        addGroupNode(OutlineViewController.NameConstants.pictures, identifier: OutlineViewController.picturesID)
 
/// - Tag: DataSource
        guard let newPlistURL = Bundle.main.url(forResource: "DataSource", withExtension: "plist") else {
            fatalError("Failed to resolve URL for `DataSource.plist` in bundle.")
        }
        do {
            // Populate the outline view with the plist content.
            struct OutlineData: Decodable {
                let children: [Node]
            }
            // Decode the top-level children of the outline.
            let plistDecoder = PropertyListDecoder()
            let data = try Data(contentsOf: newPlistURL)
            let decodedData = try plistDecoder.decode(OutlineData.self, from: data)
            for node in decodedData.children {
                // Recursively add further content from the given node.
                addNode(node)
                if node.type == .container {
                    selectParentFromSelection()
                }
            }
        } catch {
            fatalError("Failed to load `DataSource.plist` in bundle.")
        }
        treeController.setSelectionIndexPath(nil) // Start back up to the root level.
    }
    
    private func populateOutlineContents() {
        // Add the Places grouping and it's content.
        addPlacesGroup()
        
        // Add the Pictures grouing and it's outline content.
        addPicturesGroup()
    }
    
    // MARK: Removal and Addition

    private func removalConfirmAlert(_ itemsToRemove: [Node]) -> NSAlert {
        let alert = NSAlert()
        
        var messageStr: String
        if itemsToRemove.count > 1 {
            // Remove multiple items.
            alert.messageText = NSLocalizedString("remove multiple string", comment: "")
        } else {
            // Remove the single item.
            if itemsToRemove[0].isURLNode {
                messageStr = NSLocalizedString("remove link confirm string", comment: "")
            } else {
                messageStr = NSLocalizedString("remove confirm string", comment: "")
            }
            alert.messageText = String(format: messageStr, itemsToRemove[0].title)
        }
        
        alert.addButton(withTitle: NSLocalizedString("ok button title", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("cancel button title", comment: ""))
        
        return alert
    }
    
    // Called from handleContextualMenu() or the remove button.
    func removeItems(_ itemsToRemove: [Node]) {
        // Confirm the removal operation.
        let confirmAlert = removalConfirmAlert(itemsToRemove)
        confirmAlert.beginSheetModal(for: view.window!) { returnCode in
            if returnCode == NSApplication.ModalResponse.alertFirstButtonReturn {
                // Remove the given set of node objects from the tree controller.
                var indexPathsToRemove = [IndexPath]()
                for item in itemsToRemove {
                    if let indexPath = self.treeController.indexPathOfObject(anObject: item) {
                    	indexPathsToRemove.append(indexPath)
                    }
                }
                self.treeController.removeObjects(atArrangedObjectIndexPaths: indexPathsToRemove)
                
                // Remove the current selection after the removal.
                self.treeController.setSelectionIndexPaths([])
            }
        }
    }
    
    // Remove the currently selected items.
    private func removeItems() {
        var nodesToRemove = [Node]()
        
        for item in treeController.selectedNodes {
            if let node = OutlineViewController.node(from: item) {
                nodesToRemove.append(node)
            }
        }
        removeItems(nodesToRemove)
    }
 
/// - Tag: Delete
    // User chose the Delete menu item or pressed the delete key.
    @IBAction func delete(_ sender: AnyObject) {
        removeItems()
    }
    
    // Called from handleContextualMenu(), or add group button.
   func addFolderAtItem(_ item: NSTreeNode) {
        // Obtain the base node at the given outline view's row number, and the indexPath of that base node.
        guard let rowItemNode = OutlineViewController.node(from: item),
            let itemNodeIndexPath = treeController.indexPathOfObject(anObject: rowItemNode) else { return }
    
        // We are inserting a new group folder at the node index path, add it to the end.
        let indexPathToInsert = itemNodeIndexPath.appending(rowItemNode.children.count)
    
        // Create an empty folder node.
        let nodeToAdd = Node()
        nodeToAdd.title = OutlineViewController.NameConstants.untitled
        nodeToAdd.identifier = NSUUID().uuidString
        nodeToAdd.type = .container
        treeController.insert(nodeToAdd, atArrangedObjectIndexPath: indexPathToInsert)
    
        // Flag the row we are adding (for later renaming after the row was added).
        rowToAdd = outlineView.row(forItem: item) + rowItemNode.children.count
    }

    // Called from handleContextualMenu() or add picture button.
    func addPictureAtItem(_ item: Node) {
        // Present an open panel to choose a picture to display in the outline view.
        let openPanel = NSOpenPanel()
        
        // Find a picture to add.
        let locationTitle = item.title
        let messageStr = NSLocalizedString("choose picture message", comment: "")
        openPanel.message = String(format: messageStr, locationTitle)
        openPanel.prompt = NSLocalizedString("open panel prompt", comment: "") // Set the Choose button title.
        openPanel.canCreateDirectories = false
        
        // We should allow choosing all kinds of image files that CoreGraphics can handle.
        if let imageTypes = CGImageSourceCopyTypeIdentifiers() as? [String] {
            openPanel.allowedFileTypes = imageTypes
        }
        
        openPanel.beginSheetModal(for: view.window!) { (response) in
            if response == NSApplication.ModalResponse.OK {
                // Create a leaf picture node.
                let node = Node()
                node.type = .document
                node.url = openPanel.url
                node.title = node.url!.localizedName
                
                // Get the indexPath of the folder being added to.
                if let itemNodeIndexPath = self.treeController.indexPathOfObject(anObject: item) {
                    // We are inserting a new picture at the item node index path.
                    let indexPathToInsert = itemNodeIndexPath.appending(IndexPath(index: 0))
                    self.treeController.insert(node, atArrangedObjectIndexPath: indexPathToInsert)
                }
            }
        }
    }
    
    // MARK: Notifications
    
    private func setupObservers() {
        // Notification to add a folder.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(addFolder(_:)),
            name: Notification.Name(WindowViewController.NotificationNames.addFolder),
            object: nil)
        
        // Notification to add a picture.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(addPicture(_:)),
            name: Notification.Name(WindowViewController.NotificationNames.addPicture),
            object: nil)
        
        // Notification to remove an item.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(removeItem(_:)),
            name: Notification.Name(WindowViewController.NotificationNames.removeItem),
            object: nil)
        
        // Listen to our treeController's selection changed so we can inform clients to react to selection changes.
        treeControllerObserver =
            treeController.observe(\.selectedObjects, options: [.new]) {(treeController, change) in
                            // Post this notification so other view controllers can react to the selection change.
                            // (Interested view controllers are: WindowViewController and SplitViewController)
                            NotificationCenter.default.post(
                                name: Notification.Name(OutlineViewController.NotificationNames.selectionChanged),
                                object: treeController)
                
                            // Remember the saved selection for restoring selection state later.
                            self.savedSelection = treeController.selectionIndexPaths
                            self.invalidateRestorableState()
        				}
    }
    
    // Notification sent from WindowViewController class, to add a generic folder to the current selection.
    @objc
    private func addFolder(_ notif: Notification) {
        // Add the folder with "untitled" title.
        let selectedRow = outlineView.selectedRow
        if let folderToAddNode = self.outlineView.item(atRow: selectedRow) as? NSTreeNode {
            addFolderAtItem(folderToAddNode)
        }
        // Flag the row we are adding (for later renaming after the row was added).
        rowToAdd = outlineView.selectedRow
    }
    
    // Notification sent from WindowViewController class, to add a picture to the selected folder node.
    @objc
    private func addPicture(_ notif: Notification) {
        let selectedRow = outlineView.selectedRow
        
        if let item = self.outlineView.item(atRow: selectedRow) as? NSTreeNode,
            let addToNode = OutlineViewController.node(from: item) {
            	addPictureAtItem(addToNode)
        }
    }
    
    // Notification sent from WindowViewController remove button, to remove a selected item from the outline view.
    @objc
    private func removeItem(_ notif: Notification) {
        removeItems()
    }
    
    // MARK: NSTextFieldDelegate
    
    // For a text field in each outline view item, the user commits the edit operation.
    func controlTextDidEndEditing(_ obj: Notification) {
        // Commit the edit by applying the text field's text to the current node.
        guard let item = outlineView.item(atRow: outlineView.selectedRow),
            let node = OutlineViewController.node(from: item) else { return }
        
        if let textField = obj.object as? NSTextField {
            node.title = textField.stringValue
        }
    }
    
    // MARK: NSValidatedUserInterfaceItem

/// - Tag: DeleteValidation
    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(delete(_:)) {
            return !treeController.selectedObjects.isEmpty
        }
        return true
    }

    // MARK: Detail View Management
    
    // Used to decide which view controller to use as the detail.
    func viewControllerForSelection(_ selection: [NSTreeNode]?) -> NSViewController? {
        guard let outlineViewSelection = selection else { return nil }
        
        var viewController: NSViewController?
        
        switch outlineViewSelection.count {
        case 0:
            // No selection.
            viewController = nil
        case 1:
            // Single selection.
            if let node = OutlineViewController.node(from: selection?[0] as Any) {
                if let url = node.url {
                    // Node has a URL.
                    if node.isDirectory {
                        // It is a folder url.
                        iconViewController.url = url
                        viewController = iconViewController
                    } else {
                        // It is a file url.
                        fileViewController.url = url
                        viewController = fileViewController
                    }
                } else {
                    // Node does not have a URL.
                    if node.isDirectory {
                        // It is a non-url grouping of pictures.
                        iconViewController.nodeContent = node
                        viewController = iconViewController
                    } else {
                        // It is a non-url image document, so load its image.
                        if let loadedImage = NSImage(named: node.title) {
                            imageViewController.fileImageView?.image = loadedImage
                        } else {
                            debugPrint("Failed to load built-in image: \(node.title)")
                        }
                        viewController = imageViewController
                    }
                }
            }
        default:
            // Selection is multiple or more than one.
            viewController = multipleItemsViewController
        }

        return viewController
    }
    
    // MARK: File Promise Drag Handling

    /// Queue used for reading and writing file promises.
    lazy var workQueue: OperationQueue = {
        let providerQueue = OperationQueue()
        providerQueue.qualityOfService = .userInitiated
        return providerQueue
    }()
    
}

