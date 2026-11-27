import UIKit

final class IconButton: UIButton {
    var icon: IconName {
        didSet { refreshColor() }
    }
    var iconSize: CGFloat
    var customTint: UIColor? {
        didSet { refreshColor() }
    }

    init(icon: IconName, size: CGFloat = 22, tint: UIColor? = nil) {
        self.icon = icon
        self.iconSize = size
        self.customTint = tint
        super.init(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
        heightAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
        refreshColor()
        NotificationCenter.default.addObserver(self, selector: #selector(refreshColor), name: Theme.didChange, object: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc func refreshColor() {
        let color = customTint ?? Theme.current.textPrimary
        setImage(Icons.image(icon, size: iconSize, color: color), for: .normal)
    }
}
