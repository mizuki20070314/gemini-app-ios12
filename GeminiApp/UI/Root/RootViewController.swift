import UIKit

final class RootViewController: UIViewController {
    private let sidebarVC = SidebarViewController()
    private var mainVC: UIViewController?

    private let mainContainer = UIView()
    private let dimView = UIView()
    private let sidebarContainer = UIView()

    private var sidebarLeadingConstraint: NSLayoutConstraint!
    private var sidebarWidthConstraint: NSLayoutConstraint!
    private var mainLeadingConstraint: NSLayoutConstraint!
    private var isSidebarOpen = false

    var isSidebarPersistent: Bool {
        return view.bounds.width >= 700
    }

    private var drawerWidth: CGFloat {
        return min(view.bounds.width * 0.82, 300)
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return Theme.current.statusBarStyle
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        applyTheme()
        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme), name: Theme.didChange, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupViews() {
        mainContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mainContainer)

        dimView.backgroundColor = Theme.current.dimming
        dimView.alpha = 0
        dimView.isHidden = true
        dimView.translatesAutoresizingMaskIntoConstraints = false
        dimView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(closeSidebar)))
        view.addSubview(dimView)

        sidebarContainer.translatesAutoresizingMaskIntoConstraints = false
        sidebarContainer.layer.shadowColor = UIColor.black.cgColor
        sidebarContainer.layer.shadowOpacity = 0.18
        sidebarContainer.layer.shadowRadius = 10
        sidebarContainer.layer.shadowOffset = CGSize(width: 2, height: 0)
        view.addSubview(sidebarContainer)

        addChild(sidebarVC)
        sidebarVC.view.translatesAutoresizingMaskIntoConstraints = false
        sidebarContainer.addSubview(sidebarVC.view)
        sidebarVC.didMove(toParent: self)

        sidebarWidthConstraint = sidebarContainer.widthAnchor.constraint(equalToConstant: 280)
        sidebarLeadingConstraint = sidebarContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: -280)
        mainLeadingConstraint = mainContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor)

        NSLayoutConstraint.activate([
            mainLeadingConstraint,
            mainContainer.topAnchor.constraint(equalTo: view.topAnchor),
            mainContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mainContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            dimView.topAnchor.constraint(equalTo: view.topAnchor),
            dimView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dimView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            sidebarLeadingConstraint,
            sidebarWidthConstraint,
            sidebarContainer.topAnchor.constraint(equalTo: view.topAnchor),
            sidebarContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            sidebarVC.view.topAnchor.constraint(equalTo: sidebarContainer.topAnchor),
            sidebarVC.view.leadingAnchor.constraint(equalTo: sidebarContainer.leadingAnchor),
            sidebarVC.view.trailingAnchor.constraint(equalTo: sidebarContainer.trailingAnchor),
            sidebarVC.view.bottomAnchor.constraint(equalTo: sidebarContainer.bottomAnchor),
        ])

        let edgePan = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handleEdgePan(_:)))
        edgePan.edges = .left
        view.addGestureRecognizer(edgePan)

        let closeSwipe = UISwipeGestureRecognizer(target: self, action: #selector(closeSidebar))
        closeSwipe.direction = .left
        sidebarContainer.addGestureRecognizer(closeSwipe)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateLayoutForSize()
    }

    private func updateLayoutForSize() {
        if isSidebarPersistent {
            let w: CGFloat = 290
            sidebarWidthConstraint.constant = w
            sidebarLeadingConstraint.constant = 0
            mainLeadingConstraint.constant = w
            dimView.isHidden = true
            dimView.alpha = 0
            sidebarContainer.layer.shadowOpacity = 0
        } else {
            let w = drawerWidth
            sidebarWidthConstraint.constant = w
            mainLeadingConstraint.constant = 0
            sidebarLeadingConstraint.constant = isSidebarOpen ? 0 : -w
            sidebarContainer.layer.shadowOpacity = isSidebarOpen ? 0.22 : 0
        }
    }

    func setMainViewController(_ vc: UIViewController) {
        if let old = mainVC {
            old.willMove(toParent: nil)
            old.view.removeFromSuperview()
            old.removeFromParent()
        }
        mainVC = vc
        addChild(vc)
        vc.view.translatesAutoresizingMaskIntoConstraints = false
        mainContainer.addSubview(vc.view)
        NSLayoutConstraint.activate([
            vc.view.topAnchor.constraint(equalTo: mainContainer.topAnchor),
            vc.view.leadingAnchor.constraint(equalTo: mainContainer.leadingAnchor),
            vc.view.trailingAnchor.constraint(equalTo: mainContainer.trailingAnchor),
            vc.view.bottomAnchor.constraint(equalTo: mainContainer.bottomAnchor),
        ])
        vc.didMove(toParent: self)
    }

    func toggleSidebar() {
        if isSidebarPersistent { return }
        if isSidebarOpen { closeSidebar() } else { openSidebar() }
    }

    func openSidebar() {
        if isSidebarPersistent { return }
        view.endEditing(true)
        isSidebarOpen = true
        sidebarVC.reloadData()
        dimView.isHidden = false
        sidebarWidthConstraint.constant = drawerWidth
        sidebarLeadingConstraint.constant = 0
        sidebarContainer.layer.shadowOpacity = 0.22
        UIView.animate(withDuration: 0.24, delay: 0, options: [.curveEaseOut]) {
            self.dimView.alpha = 1
            self.view.layoutIfNeeded()
        }
    }

    @objc func closeSidebar() {
        if isSidebarPersistent { return }
        guard isSidebarOpen else { return }
        isSidebarOpen = false
        sidebarLeadingConstraint.constant = -drawerWidth
        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseIn], animations: {
            self.dimView.alpha = 0
            self.view.layoutIfNeeded()
        }) { _ in
            self.dimView.isHidden = true
            self.sidebarContainer.layer.shadowOpacity = 0
        }
    }

    @objc private func handleEdgePan(_ g: UIScreenEdgePanGestureRecognizer) {
        if isSidebarPersistent { return }
        if g.state == .began { openSidebar() }
    }

    @objc private func applyTheme() {
        view.backgroundColor = Theme.current.background
        dimView.backgroundColor = Theme.current.dimming
        setNeedsStatusBarAppearanceUpdate()
    }
}
