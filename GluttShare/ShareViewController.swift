import UIKit
import UniformTypeIdentifiers

/// Receives shared URLs from Safari/TikTok/Instagram/YouTube, stashes them
/// in the app group, and tells the user to open Glutt to finish the import.
final class ShareViewController: UIViewController {

    private let appGroupID = "group.com.malik.glutt"

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.98, green: 0.96, blue: 0.93, alpha: 1)
        buildUI()
        captureSharedURL()
    }

    private func captureSharedURL() {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let provider = item.attachments?.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) })
        else {
            finish(after: 1.2)
            return
        }

        provider.loadItem(forTypeIdentifier: UTType.url.identifier) { [weak self] value, _ in
            guard let self else { return }
            if let url = value as? URL {
                UserDefaults(suiteName: self.appGroupID)?.set(url.absoluteString, forKey: "pendingImportURL")
            }
            DispatchQueue.main.async {
                self.finish(after: 1.2)
            }
        }
    }

    private func finish(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }

    private func buildUI() {
        let checkmark = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
        checkmark.tintColor = UIColor(red: 0.18, green: 0.37, blue: 0.24, alpha: 1)
        checkmark.contentMode = .scaleAspectFit

        let label = UILabel()
        label.text = "Saved! Open Glutt to review the import."
        label.font = .preferredFont(forTextStyle: .headline)
        label.textColor = UIColor(red: 0.17, green: 0.14, blue: 0.12, alpha: 1)
        label.textAlignment = .center
        label.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [checkmark, label])
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
            checkmark.widthAnchor.constraint(equalToConstant: 48),
            checkmark.heightAnchor.constraint(equalToConstant: 48),
        ])
    }
}
