import UIKit

final class BottomSheetController: UIViewController {
    private let contentVC: UIViewController
    private let dimView = UIView()
    private let sheetContainer = UIView()
    private let grabber = UIView()
    private var sheetBottomConstraint: NSLayoutConstraint!
    private var sheetHeightConstraint: NSLayoutConstraint!

    static func present(_ content: UIViewController, from presenter: UIViewController) {
        let sheet = BottomSheetController(content: content)
        sheet.modalPresentationStyle = .overFullScreen
        sheet.modalTransitionStyle = .crossDissolve
        presenter.present(sheet, animated: false)
    }

    init(content: UIViewController) {
        self.contentVC = content
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let t = Theme.current
        view.backgroundColor = .clear

        dimView.backgroundColor = t.dimming
        dimView.alpha = 0
        dimView.translatesAutoresizingMaskIntoConstraints = false
        dimView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismissSheet)))
        view.addSubview(dimView)

        sheetContainer.backgroundColor = t.background
        sheetContainer.layer.cornerRadius = 20
        sheetContainer.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        sheetContainer.clipsToBounds = true
        sheetContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sheetContainer)

        grabber.backgroundColor = t.border
        grabber.layer.cornerRadius = 2.5
        grabber.translatesAutoresizingMaskIntoConstraints = false
        sheetContainer.addSubview(grabber)

        addChild(contentVC)
        contentVC.view.translatesAutoresizingMaskIntoConstraints = false
        sheetContainer.addSubview(contentVC.view)
        contentVC.didMove(toParent: self)

        let preferredH = contentVC.preferredContentSize.height > 0 ? contentVC.preferredContentSize.height : 420
        let maxH = UIScreen.main.bounds.height * 0.85
        let targetH = min(preferredH + 24, maxH)

        sheetBottomConstraint = sheetContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: targetH)
        sheetHeightConstraint = sheetContainer.heightAnchor.constraint(equalToConstant: targetH)

        NSLayoutConstraint.activate([
            dimView.topAnchor.constraint(equalTo: view.topAnchor),
            dimView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dimView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            sheetContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sheetContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sheetBottomConstraint,
            sheetHeightConstraint,

            grabber.topAnchor.constraint(equalTo: sheetContainer.topAnchor, constant: 8),
            grabber.centerXAnchor.constraint(equalTo: sheetContainer.centerXAnchor),
            grabber.widthAnchor.constraint(equalToConstant: 40),
            grabber.heightAnchor.constraint(equalToConstant: 5),

            contentVC.view.topAnchor.constraint(equalTo: grabber.bottomAnchor, constant: 8),
            contentVC.view.leadingAnchor.constraint(equalTo: sheetContainer.leadingAnchor),
            contentVC.view.trailingAnchor.constraint(equalTo: sheetContainer.trailingAnchor),
            contentVC.view.bottomAnchor.constraint(equalTo: sheetContainer.bottomAnchor)
        ])

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        sheetContainer.addGestureRecognizer(pan)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        sheetBottomConstraint.constant = 0
        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut]) {
            self.dimView.alpha = 1
            self.view.layoutIfNeeded()
        }
    }

    @objc func dismissSheet() {
        sheetBottomConstraint.constant = sheetHeightConstraint.constant
        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseIn], animations: {
            self.dimView.alpha = 0
            self.view.layoutIfNeeded()
        }) { _ in
            self.dismiss(animated: false)
        }
    }

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        let dy = max(0, g.translation(in: view).y)
        switch g.state {
        case .changed:
            sheetBottomConstraint.constant = dy
        case .ended, .cancelled:
            if dy > 100 || g.velocity(in: view).y > 600 {
                dismissSheet()
            } else {
                sheetBottomConstraint.constant = 0
                UIView.animate(withDuration: 0.2) { self.view.layoutIfNeeded() }
            }
        default: break
        }
    }
}
