import UIKit

final class ThinkingView: UIView {
    private let container = UIView()
    private let headerButton = UIButton(type: .system)
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let chevronView = UIImageView()
    private let bodyLabel = UILabel()
    private var bodyBottomConstraint: NSLayoutConstraint!
    private var headerBottomConstraint: NSLayoutConstraint!

    var isExpanded: Bool = false {
        didSet { updateExpandState() }
    }
    var onToggle: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        container.layer.cornerRadius = 12
        container.layer.borderWidth = 1
        container.clipsToBounds = true
        container.translatesAutoresizingMaskIntoConstraints = false
        addSubview(container)

        headerButton.translatesAutoresizingMaskIntoConstraints = false
        headerButton.addTarget(self, action: #selector(headerTapped), for: .touchUpInside)
        container.addSubview(headerButton)

        iconView.contentMode = .scaleAspectFit
        iconView.isUserInteractionEnabled = false
        iconView.translatesAutoresizingMaskIntoConstraints = false
        headerButton.addSubview(iconView)

        titleLabel.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        titleLabel.isUserInteractionEnabled = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        headerButton.addSubview(titleLabel)

        chevronView.contentMode = .scaleAspectFit
        chevronView.isUserInteractionEnabled = false
        chevronView.translatesAutoresizingMaskIntoConstraints = false
        headerButton.addSubview(chevronView)

        bodyLabel.numberOfLines = 0
        bodyLabel.font = UIFont.systemFont(ofSize: 13)
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(bodyLabel)

        headerBottomConstraint = headerButton.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        bodyBottomConstraint = bodyLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: topAnchor),
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor),

            headerButton.topAnchor.constraint(equalTo: container.topAnchor),
            headerButton.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            headerButton.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            headerButton.heightAnchor.constraint(equalToConstant: 36),

            iconView.leadingAnchor.constraint(equalTo: headerButton.leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: headerButton.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            titleLabel.centerYAnchor.constraint(equalTo: headerButton.centerYAnchor),

            chevronView.trailingAnchor.constraint(equalTo: headerButton.trailingAnchor, constant: -10),
            chevronView.centerYAnchor.constraint(equalTo: headerButton.centerYAnchor),
            chevronView.widthAnchor.constraint(equalToConstant: 14),
            chevronView.heightAnchor.constraint(equalToConstant: 14),

            bodyLabel.topAnchor.constraint(equalTo: headerButton.bottomAnchor, constant: 2),
            bodyLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            bodyLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
        ])
        updateExpandState()
    }

    func configure(thinking: String, isStreaming: Bool, expanded: Bool) {
        let t = Theme.current
        container.backgroundColor = t.thinkingBackground
        container.layer.borderColor = t.border.cgColor
        iconView.image = Icons.image(.thinking, size: 16, color: t.accent)
        titleLabel.text = isStreaming ? "思考中..." : "思考プロセスを表示"
        titleLabel.textColor = t.textSecondary
        bodyLabel.text = thinking
        bodyLabel.textColor = t.textSecondary
        self.isExpanded = expanded
    }

    private func updateExpandState() {
        let t = Theme.current
        bodyLabel.isHidden = !isExpanded
        chevronView.image = Icons.image(isExpanded ? .chevronUp : .chevronDown, size: 14, color: t.textTertiary)
        headerBottomConstraint.isActive = !isExpanded
        bodyBottomConstraint.isActive = isExpanded
    }

    @objc private func headerTapped() {
        isExpanded.toggle()
        onToggle?()
    }
}
