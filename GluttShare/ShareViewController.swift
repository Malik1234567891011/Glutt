import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Runs the full recipe import inside the share sheet, then either closes
/// (staying in the source app) or opens Glutt to the imported recipe.
final class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.98, green: 0.96, blue: 0.93, alpha: 1)
        // Flatten attachments across ALL shared items — some apps split the URL
        // and a preview image into separate NSExtensionItems.
        let attachments = (extensionContext?.inputItems as? [NSExtensionItem])?
            .flatMap { $0.attachments ?? [] } ?? []
        presentAttachmentDiagnostic(attachments) { [weak self] in
            self?.loadSharedInput(from: attachments) { urlString, imageData in
                self?.present(urlString: urlString, imageData: imageData)
            }
        }
    }

    // MARK: - Shared input

    /// TEMP diagnostic: list exactly what the source app handed the extension, so
    /// we can see whether Instagram provides an image attachment at all.
    private func presentAttachmentDiagnostic(_ attachments: [NSItemProvider], then proceed: @escaping () -> Void) {
        let types = attachments.flatMap { $0.registeredTypeIdentifiers }
        let alert = UIAlertController(
            title: "Share attachments (\(attachments.count))",
            message: types.isEmpty ? "(none)" : types.joined(separator: "\n"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Continue", style: .default) { _ in proceed() })
        present(alert, animated: true)
    }

    /// Loads the shared URL (required) and, when the source app also provides a
    /// preview image (e.g. an Instagram reel thumbnail), its bytes — so we can
    /// show/save an image even when the page exposes no scrapable thumbnail.
    private func loadSharedInput(from attachments: [NSItemProvider], _ completion: @escaping (String?, Data?) -> Void) {
        guard let urlProvider = attachments.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) })
        else { completion(nil, nil); return }

        let imageProvider = attachments.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) })

        urlProvider.loadItem(forTypeIdentifier: UTType.url.identifier) { value, _ in
            let urlString = (value as? URL)?.absoluteString
            guard let imageProvider else {
                DispatchQueue.main.async { completion(urlString, nil) }
                return
            }
            Self.loadImageData(from: imageProvider) { data in
                DispatchQueue.main.async { completion(urlString, data) }
            }
        }
    }

    private static func loadImageData(from provider: NSItemProvider, completion: @escaping (Data?) -> Void) {
        if provider.canLoadObject(ofClass: UIImage.self) {
            _ = provider.loadObject(ofClass: UIImage.self) { object, _ in
                completion((object as? UIImage)?.jpegData(compressionQuality: 0.8))
            }
            return
        }
        provider.loadItem(forTypeIdentifier: UTType.image.identifier) { value, _ in
            if let image = value as? UIImage {
                completion(image.jpegData(compressionQuality: 0.8))
            } else if let url = value as? URL, let data = try? Data(contentsOf: url) {
                completion(data)
            } else {
                completion(value as? Data)
            }
        }
    }

    private func present(urlString: String?, imageData: Data?) {
        guard let urlString else { close(); return }

        let viewModel = ShareImportViewModel(urlString: urlString, sharedImageData: imageData)
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

    /// Launches the host app at a deep-link path. A *share* extension can't use
    /// `extensionContext.open` for a custom scheme, and the deprecated `openURL:`
    /// selector isn't honored on current iOS — so we reach `UIApplication` via the
    /// responder chain and call the modern `open(_:options:completionHandler:)`.
    /// If no UIApplication is reachable we just dismiss: the recipe is already in
    /// the inbox, so it still lands in the library next time the app opens.
    private func openApp(path: String) {
        guard let url = URL(string: "glutt://\(path)") else { close(); return }

        var responder: UIResponder? = self
        while let current = responder {
            if let application = current as? UIApplication {
                application.open(url, options: [:]) { [weak self] _ in
                    self?.extensionContext?.completeRequest(returningItems: nil)
                }
                return
            }
            responder = current.next
        }
        close()
    }
}
