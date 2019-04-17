/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Generic multi-use node object used with NSOutlineView and NSTreeController.
*/

import Cocoa

enum NodeType: Int, Codable {
    case container
    case document
    case separator
    case unknown
}

/// - Tag: NodeClass
class Node: NSObject, Codable {
    var type: NodeType = .unknown
    var title: String = ""
    var identifier: String = ""
    var url: URL?
    @objc dynamic var children = [Node]()
}

extension Node {
    
    /** Called by the tree controller to determine is this node is a leaf node,
     used to determine if the node should have a disclosure triangle.
     */
    @objc dynamic var isLeaf: Bool {
        return type == .document || type == .separator
    }
    
    var isURLNode: Bool {
        return url != nil
    }
    
    var isSpecialGroup: Bool {
        // A group node is a special node representing either "Pictures" or "Places" as grouped sections.
        return (!isURLNode &&
            (title == OutlineViewController.NameConstants.pictures || title == OutlineViewController.NameConstants.places))
    }
    
    override class func description() -> String {
        return "Node"
    }
    
    var nodeIcon: NSImage {
        var icon = NSImage()
        if let nodeURL = url {
            // If the node has a URL, use it to obtain its icon.
            icon = nodeURL.icon
        } else {
            // No URL for this node, so determine it's icon generically.
            let osType = isDirectory ? kGenericFolderIcon : kGenericDocumentIcon
            let iconType = NSFileTypeForHFSTypeCode(OSType(osType))
            icon = NSWorkspace.shared.icon(forFileType: iconType!)
        }
        return icon
    }
    
    var canChange: Bool {
        // You can only change (rename or add to) non-url based directory node.
        return isDirectory && url == nil
    }
    
    var canAddTo: Bool {
        return isDirectory && canChange
    }
    
    var isSeparator: Bool {
        return type == .separator
    }
    
    var isDirectory: Bool {
        return type == .container
    }
    
}
