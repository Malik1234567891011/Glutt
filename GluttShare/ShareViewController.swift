import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Runs the full recipe import inside the share sheet, then either closes
/// (staying in the source app) or opens Glutt to the imported recipe.
final class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.98, green: 0.96, blue: 0.93, alpha: 1)
        loadSharedURL { [weak self] urlString in
            self?.present(urlString: urlString)
        }
    }

    // MARK: - Shared URL

    private func loadSharedURL(_ completion: @escaping (String?) -> Void) {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let provider = item.attachments?.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) })
        else { completion(nil); return }

        provider.loadItem(forTypeIdentifier: UTType.url.identifier) { value, _ in
            let urlString = (value as? URL)?.absoluteString
            DispatchQueue.main.async { completion(urlString) }
        }
    }

    private func present(urlString: String?) {
        guard let urlString else { close(); return }

        let viewModel = ShareImportViewModel(urlString: urlString)
        let root = ShareRootView(
            viewModel: viewModel,
            sourceURLString: urlString,
            onViewRecipe: { [weak self] id in self?.openApp(path: "recipe?import=\(id.uuidString)") },
            onClose: { [weak self] in self?.close() },
            onOpenInApp: { [weak self] url in
                PendingImportStore.save(urlString: url)
                self?.openApp(path: "import?url=\(url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url)")
            }
        )

        let hosting = UIHostingController(rootView: root)
        addChild(hosting)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        hosting.didMove(toParent: self)
    }

    // MARK: - Terminal actions

    private func close() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    /// Opens the host app via the custom scheme. `extensionContext.open` is the
    /// only sanctioned way for a share extension to launch its container app.
    private func openApp(path: String) {
        guard let url = URL(string: "glutt://\(path)") else { close(); return }
        extensionContext?.open(url) { [weak self] _ in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
