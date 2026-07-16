#if os(macOS)
import AppKit
import SwiftUI

struct MacWorkspaceSplitView: NSViewControllerRepresentable {
    let workspace: RouteWorkspace
    @Binding var isInspectorPresented: Bool

    func makeNSViewController(context: Context) -> MacWorkspaceSplitViewController {
        let controller = MacWorkspaceSplitViewController(workspace: workspace)
        controller.setInspectorPresented(isInspectorPresented)
        return controller
    }

    func updateNSViewController(
        _ controller: MacWorkspaceSplitViewController,
        context: Context
    ) {
        controller.setInspectorPresented(isInspectorPresented)
    }
}

@MainActor
final class MacWorkspaceSplitViewController: NSSplitViewController {
    let sidebarItem: NSSplitViewItem
    let contentItem: NSSplitViewItem
    let inspectorItem: NSSplitViewItem

    init(workspace: RouteWorkspace) {
        let sidebarController = NSHostingController(
            rootView: RouteSidebar(workspace: workspace)
        )
        let contentController = NSHostingController(
            rootView: RouteDetailView(workspace: workspace)
        )
        let inspectorController = NSHostingController(
            rootView: RouteInspector(workspace: workspace)
        )

        sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarController)
        contentItem = NSSplitViewItem(viewController: contentController)
        inspectorItem = NSSplitViewItem(inspectorWithViewController: inspectorController)

        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        splitView.isVertical = true
        splitView.dividerStyle = .thin

        sidebarItem.minimumThickness = 220
        sidebarItem.maximumThickness = 280
        sidebarItem.preferredThicknessFraction = 0.24
        sidebarItem.canCollapse = false
        sidebarItem.holdingPriority = NSLayoutConstraint.Priority(252)

        contentItem.minimumThickness = 320
        contentItem.holdingPriority = NSLayoutConstraint.Priority(249)

        inspectorItem.minimumThickness = 280
        inspectorItem.maximumThickness = 360
        inspectorItem.preferredThicknessFraction = 0.30
        inspectorItem.canCollapse = true
        inspectorItem.holdingPriority = NSLayoutConstraint.Priority(251)

        addSplitViewItem(sidebarItem)
        addSplitViewItem(contentItem)
        addSplitViewItem(inspectorItem)
        configureLiveResizeRedraw()
    }

    func setInspectorPresented(_ isPresented: Bool) {
        loadViewIfNeeded()
        guard inspectorItem.isCollapsed == isPresented else { return }
        inspectorItem.isCollapsed = !isPresented
    }

    private func configureLiveResizeRedraw() {
        let paneViews = splitViewItems.flatMap { item in
            [item.viewController.view, item.viewController.view.superview].compactMap { $0 }
        }
        for view in [self.view, splitView] + paneViews {
            view.wantsLayer = true
            view.layerContentsRedrawPolicy = .duringViewResize
        }
    }

}
#endif
