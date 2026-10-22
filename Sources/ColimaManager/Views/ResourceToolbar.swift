import AppKit
import SwiftUI

/// One native window toolbar owns layout, glass, and search-field focus.
struct ResourceToolbar: NSViewRepresentable {
    @ObservedObject var model: ManagerViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeNSView(context: Context) -> ToolbarAttachmentView {
        let view = ToolbarAttachmentView()
        view.attach = { [weak coordinator = context.coordinator] window in
            coordinator?.install(in: window)
        }
        return view
    }

    func updateNSView(_ view: ToolbarAttachmentView, context: Context) {
        context.coordinator.update()
    }

    static func dismantleNSView(_ view: ToolbarAttachmentView, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    final class ToolbarAttachmentView: NSView {
        var attach: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            attach?(window)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSToolbarDelegate, NSSearchFieldDelegate {
        private static let reloadID = NSToolbarItem.Identifier("resources.reload")
        private static let pruneID = NSToolbarItem.Identifier("resources.pruneOrphans")
        private static let pruneAllID = NSToolbarItem.Identifier("resources.pruneAll")
        private static let tabsID = NSToolbarItem.Identifier("resources.tabs")
        private static let searchID = NSToolbarItem.Identifier("resources.search")

        private let model: ManagerViewModel
        private weak var window: NSWindow?
        private var toolbar: NSToolbar?
        private var items: [NSToolbarItem.Identifier: NSToolbarItem] = [:]
        private var tabItem: NSToolbarItemGroup?
        private var searchItem: NSSearchToolbarItem?

        init(model: ManagerViewModel) {
            self.model = model
        }

        func install(in window: NSWindow) {
            guard self.window !== window else { return }
            self.window = window

            let toolbar = NSToolbar(identifier: "ColimaManager.ResourceToolbar")
            toolbar.delegate = self
            toolbar.displayMode = .iconOnly
            toolbar.allowsUserCustomization = false
            toolbar.autosavesConfiguration = false
            // Center relative to the window, independent of the two side groups.
            toolbar.centeredItemIdentifiers = [Self.tabsID]
            self.toolbar = toolbar

            window.title = ""
            window.titleVisibility = .hidden
            window.toolbarStyle = .unified
            window.toolbar = toolbar
            update()
        }

        func detach() {
            if window?.toolbar === toolbar {
                window?.toolbar = nil
            }
        }

        func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
            [Self.reloadID, .space, Self.pruneID, Self.pruneAllID,
             .flexibleSpace, Self.tabsID, .flexibleSpace, Self.searchID]
        }

        func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
            toolbarDefaultItemIdentifiers(toolbar)
        }

        func toolbar(
            _ toolbar: NSToolbar,
            itemForItemIdentifier identifier: NSToolbarItem.Identifier,
            willBeInsertedIntoToolbar flag: Bool
        ) -> NSToolbarItem? {
            if let item = items[identifier] { return item }

            let item: NSToolbarItem
            switch identifier {
            case Self.reloadID:
                item = actionItem(identifier, title: "Reload", symbol: "arrow.clockwise", action: #selector(reload))
            case Self.pruneID:
                item = actionItem(identifier, title: "Prune Orphans", symbol: "trash", action: #selector(pruneOrphans))
            case Self.pruneAllID:
                item = actionItem(identifier, title: "Prune All", symbol: "trash.fill", action: #selector(pruneAll))
            case Self.tabsID:
                let group = NSToolbarItemGroup(
                    itemIdentifier: identifier,
                    titles: ResourceTab.allCases.map(\.title),
                    selectionMode: .selectOne,
                    labels: nil,
                    target: self,
                    action: #selector(selectTab)
                )
                group.label = "Resource tabs"
                group.controlRepresentation = .expanded
                group.isBordered = true
                group.autovalidates = false
                group.selectedIndex = ResourceTab.allCases.firstIndex(of: model.selectedTab) ?? 0
                tabItem = group
                item = group
            case Self.searchID:
                let field = NSSearchField()
                field.placeholderString = "Search"
                field.sendsSearchStringImmediately = true
                field.delegate = self
                field.setAccessibilityLabel("Search")

                let search = NSSearchToolbarItem(itemIdentifier: identifier)
                search.label = "Search"
                search.searchField = field
                search.preferredWidthForSearchField = 180
                // Bound both resting and focused width so search never evicts actions.
                field.widthAnchor.constraint(equalToConstant: 180).isActive = true
                search.resignsFirstResponderWithCancel = true
                searchItem = search
                item = search
            default:
                return nil
            }
            item.visibilityPriority = .high
            items[identifier] = item
            return item
        }

        private func actionItem(
            _ identifier: NSToolbarItem.Identifier,
            title: String,
            symbol: String,
            action: Selector
        ) -> NSToolbarItem {
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.label = title
            item.paletteLabel = title
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            item.isBordered = true
            item.autovalidates = false
            item.target = self
            item.action = action
            return item
        }

        func update() {
            tabItem?.selectedIndex = ResourceTab.allCases.firstIndex(of: model.selectedTab) ?? 0
            items[Self.reloadID]?.isEnabled = !model.isLoading(model.selectedTab)
            items[Self.reloadID]?.toolTip = "Reload \(model.selectedTab.title.lowercased())"

            for (identifier, all) in [(Self.pruneID, false), (Self.pruneAllID, true)] {
                let operation = DockerPruneOperation.operation(for: model.selectedTab, pruneAll: all)
                items[identifier]?.isEnabled = operation != nil && !model.isPruning
                items[identifier]?.toolTip = pruneHelp(all: all, operation: operation)
            }
            if let field = searchItem?.searchField, field.stringValue != model.searchText {
                field.stringValue = model.searchText
            }
        }

        private func pruneHelp(all: Bool, operation: DockerPruneOperation?) -> String {
            let title = all ? "Prune All" : "Prune Orphans"
            if let operation {
                return "\(title) — \(model.selectedTab.title)\n\(operation.confirmationMessage)"
            }
            return model.selectedTab == .stacks
                ? "\(title): Docker has no stack prune command. Use a stack’s Delete action."
                : "\(title): Prune Orphans already removes all unused \(model.selectedTab.title.lowercased())."
        }

        @objc private func reload() { model.refreshSelectedTab() }
        @objc private func pruneOrphans() { model.requestPrune(all: false) }
        @objc private func pruneAll() { model.requestPrune(all: true) }

        @objc private func selectTab() {
            guard let index = tabItem?.selectedIndex,
                  ResourceTab.allCases.indices.contains(index) else { return }
            model.selectedTab = ResourceTab.allCases[index]
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            model.searchText = field.stringValue
        }
    }
}
