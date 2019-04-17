/*
See LICENSE folder for this sample’s licensing information.

Abstract:
View controller managing our split view interface.
*/

import Cocoa

class SplitViewController: NSSplitViewController {
    
    private var verticalConstraints: [NSLayoutConstraint] = []
    private var horizontalConstraints: [NSLayoutConstraint] = []
    
    var treeControllerObserver: NSKeyValueObservation?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        /** Note: We keep the left split view item from growing as the window grows by setting its
         	hugging priority to 200, and the right to 199. The view with the lowest priority will be
         	the first to take on additional width if the split view grows or shrinks.
         */
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSelectionChange(_:)),
            name: Notification.Name(OutlineViewController.NotificationNames.selectionChanged),
            object: nil)
    }
    
    // MARK: Detail View Controller Management
    
    private var detailViewController: NSViewController {
        let rightSplitViewItem = splitViewItems[1]
        return rightSplitViewItem.viewController
    }
    
    private var hasChildViewController: Bool {
        return !detailViewController.children.isEmpty
    }
    
    private func embedChildViewController(_ childViewController: NSViewController) {
        // To embed a new child view controller.
        let currentDetailVC = detailViewController
        currentDetailVC.addChild(childViewController)
        currentDetailVC.view.addSubview(childViewController.view)
        
        // Build the horizontal, vertical constraints so that added child view controllers matches the width and height of it's parent.
        let views = ["targetView": childViewController.view]
        horizontalConstraints =
            NSLayoutConstraint.constraints(withVisualFormat: "H:|[targetView]|",
                                           options: [],
                                           metrics: nil,
                                           views: views)
        NSLayoutConstraint.activate(horizontalConstraints)
        
        verticalConstraints =
            NSLayoutConstraint.constraints(withVisualFormat: "V:|[targetView]|",
                                           options: [],
                                           metrics: nil,
                                           views: views)
        NSLayoutConstraint.activate(verticalConstraints)
    }
    
    // MARK: Notifications
    
    // Listens for selection changes to the NSTreeController.
    @objc
    private func handleSelectionChange(_ notification: Notification) {
        // Examine the current selection and adjust the UI.
        
        // First make sure the notification's object is a tree controller.
        guard let treeController = notification.object as? NSTreeController else { return }
        
        let leftSplitViewItem = splitViewItems[0]
        if let outlineViewControllerToObserve = leftSplitViewItem.viewController as? OutlineViewController {
            let currentDetailVC = detailViewController
            
            // Let the outline view controller handle the selection (helps us decide which detail view to use).
            if let vcForDetail = outlineViewControllerToObserve.viewControllerForSelection(treeController.selectedNodes) {
                if hasChildViewController && currentDetailVC.children[0] != vcForDetail {
                    /** The incoming child view controller is different from the one we
                        currently have, remove the old one and add the new one.
                    */
                    currentDetailVC.removeChild(at: 0)
                    // Remove the old child detail view.
                    detailViewController.view.subviews[0].removeFromSuperview()
                    // Add the new child detail view.
                    embedChildViewController(vcForDetail)
                } else {
                    if !hasChildViewController {
                        // We don't have a child view controller so embed the new one.
                        embedChildViewController(vcForDetail)
                    }
                }
            } else {
                // No selection, we don't have a child view controller to embed so remove current child view controller.
                if hasChildViewController {
                    currentDetailVC.removeChild(at: 0)
                    detailViewController.view.subviews[0].removeFromSuperview()
                }
            }
        }
    }
    
}
