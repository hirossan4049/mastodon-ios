//
//  MainTabBarController.swift
//  Mastodon
//
//  Created by Cirno MainasuK on 2021-1-27.
//

import os.log
import UIKit
import Combine
import SafariServices

class MainTabBarController: UITabBarController {
    
    var disposeBag = Set<AnyCancellable>()
    
    weak var context: AppContext!
    weak var coordinator: SceneCoordinator!

    var currentTab = Tab.home
        
    enum Tab: Int, CaseIterable {
        case home
        case search
        case notification
        case me
        
        var title: String {
            switch self {
            case .home:             return L10n.Common.Controls.Tabs.home
            case .search:           return L10n.Common.Controls.Tabs.search
            case .notification:     return L10n.Common.Controls.Tabs.notification
            case .me:               return L10n.Common.Controls.Tabs.profile
            }
        }
        
        var image: UIImage {
            switch self {
            case .home:             return UIImage(systemName: "house.fill")!
            case .search:           return UIImage(systemName: "magnifyingglass")!
            case .notification:     return UIImage(systemName: "bell.fill")!
            case .me:               return UIImage(systemName: "person.fill")!
            }
        }

        var largeImage: UIImage {
            switch self {
            case .home:             return UIImage(systemName: "house.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 80))!
            case .search:           return UIImage(systemName: "magnifyingglass", withConfiguration: UIImage.SymbolConfiguration(pointSize: 80))!
            case .notification:     return UIImage(systemName: "bell.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 80))!
            case .me:               return UIImage(systemName: "person.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 80))!
            }
        }
        
        func viewController(context: AppContext, coordinator: SceneCoordinator) -> UIViewController {
            let viewController: UIViewController
            switch self {
            case .home:
                #if ASDK
                let _viewController: NeedsDependency & UIViewController = UserDefaults.shared.preferAsyncHomeTimeline ? AsyncHomeTimelineViewController() : HomeTimelineViewController()
                #else
                let _viewController = HomeTimelineViewController()
                #endif
                _viewController.context = context
                _viewController.coordinator = coordinator
                viewController = _viewController
            case .search:
                let _viewController = SearchViewController()
                _viewController.context = context
                _viewController.coordinator = coordinator
                viewController = _viewController
            case .notification:
                let _viewController = NotificationViewController()
                _viewController.context = context
                _viewController.coordinator = coordinator
                viewController = _viewController
            case .me:
                let _viewController = ProfileViewController()
                _viewController.context = context
                _viewController.coordinator = coordinator
                _viewController.viewModel = MeProfileViewModel(context: context)
                viewController = _viewController
            }
            viewController.title = self.title
            return AdaptiveStatusBarStyleNavigationController(rootViewController: viewController)
        }
    }
    
    init(context: AppContext, coordinator: SceneCoordinator) {
        self.context = context
        self.coordinator = coordinator
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}

extension MainTabBarController {
    
    open override var childForStatusBarStyle: UIViewController? {
        return selectedViewController
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        delegate = self

        view.backgroundColor = ThemeService.shared.currentTheme.value.systemBackgroundColor
        ThemeService.shared.currentTheme
            .receive(on: RunLoop.main)
            .sink { [weak self] theme in
                guard let self = self else { return }
                self.view.backgroundColor = theme.tabBarBackgroundColor
            }
            .store(in: &disposeBag)

        let tabs = Tab.allCases
        let viewControllers: [UIViewController] = tabs.map { tab in
            let viewController = tab.viewController(context: context, coordinator: coordinator)
            viewController.tabBarItem.title = tab.title
            viewController.tabBarItem.image = tab.image
            viewController.tabBarItem.accessibilityLabel = tab.title
            viewController.tabBarItem.largeContentSizeImage = tab.largeImage
            viewController.tabBarItem.imageInsets = UIEdgeInsets(top: 6, left: 0, bottom: -6, right: 0)
            return viewController
        }
        setViewControllers(viewControllers, animated: false)
        selectedIndex = 0

        UITabBarItem.appearance().setTitleTextAttributes([.foregroundColor : UIColor.clear], for: .normal)
        UITabBarItem.appearance().setTitleTextAttributes([.foregroundColor : UIColor.clear], for: .highlighted)
        UITabBarItem.appearance().setTitleTextAttributes([.foregroundColor : UIColor.clear], for: .selected)
        
        context.apiService.error
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                guard let self = self, let coordinator = self.coordinator else { return }
                switch error {
                case .implicit:
                    break
                case .explicit:
                    let alertController = UIAlertController(for: error, title: nil, preferredStyle: .alert)
                    let okAction = UIAlertAction(title: "OK", style: .default, handler: nil)
                    alertController.addAction(okAction)
                    coordinator.present(
                        scene: .alertController(alertController: alertController),
                        from: nil,
                        transition: .alertController(animated: true, completion: nil)
                    )
                }
            }
            .store(in: &disposeBag)
        
        // handle post failure
        context.statusPublishService
            .latestPublishingComposeViewModel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] composeViewModel in
                guard let self = self else { return }
                guard let composeViewModel = composeViewModel else { return }
                guard let currentState = composeViewModel.publishStateMachine.currentState else { return }
                guard currentState is ComposeViewModel.PublishState.Fail else { return }
                
                let alertController = UIAlertController(title: L10n.Common.Alerts.PublishPostFailure.title, message: L10n.Common.Alerts.PublishPostFailure.message, preferredStyle: .alert)
                let discardAction = UIAlertAction(title: L10n.Common.Controls.Actions.discard, style: .destructive) { [weak self, weak composeViewModel] _ in
                    guard let self = self else { return }
                    guard let composeViewModel = composeViewModel else { return }
                    self.context.statusPublishService.remove(composeViewModel: composeViewModel)
                }
                alertController.addAction(discardAction)
                let retryAction = UIAlertAction(title: L10n.Common.Controls.Actions.tryAgain, style: .default) { [weak composeViewModel] _ in
                    guard let composeViewModel = composeViewModel else { return }
                    composeViewModel.publishStateMachine.enter(ComposeViewModel.PublishState.Publishing.self)
                }
                alertController.addAction(retryAction)
                self.present(alertController, animated: true, completion: nil)
            }
            .store(in: &disposeBag)
                
        // handle push notification. toggle entry when finish fetch latest notification
        context.notificationService.hasUnreadPushNotification
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hasUnreadPushNotification in
                guard let self = self else { return }
                guard let notificationViewController = self.notificationViewController else { return }
                
                let image = hasUnreadPushNotification ? UIImage(systemName: "bell.badge.fill")! : UIImage(systemName: "bell.fill")!
                notificationViewController.tabBarItem.image = image
                notificationViewController.navigationController?.tabBarItem.image = image
            }
            .store(in: &disposeBag)
        
        context.notificationService.requestRevealNotificationPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notificationID in
                guard let self = self else { return }
                self.coordinator.switchToTabBar(tab: .notification)
                let threadViewModel = RemoteThreadViewModel(context: self.context, notificationID: notificationID)
                self.coordinator.present(scene: .thread(viewModel: threadViewModel), from: nil, transition: .show)
            }
            .store(in: &disposeBag)

        #if DEBUG
//        selectedIndex = 1
        #endif
    }

}

extension MainTabBarController {

    var notificationViewController: NotificationViewController? {
        return viewController(of: NotificationViewController.self)
    }
    
}

// MARK: - UITabBarControllerDelegate
extension MainTabBarController: UITabBarControllerDelegate {
    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        os_log(.info, log: .debug, "%{public}s[%{public}ld], %{public}s: select %s", ((#file as NSString).lastPathComponent), #line, #function, viewController.debugDescription)
        defer {
            if let tab = Tab(rawValue: tabBarController.selectedIndex) {
                currentTab = tab
            }
        }
        guard currentTab.rawValue == tabBarController.selectedIndex,
              let navigationController = viewController as? UINavigationController,
              navigationController.viewControllers.count == 1,
              let scrollViewContainer = navigationController.topViewController as? ScrollViewContainer else {
            return
        }

        scrollViewContainer.scrollToTop(animated: true)
    }
}


// HIG: keyboard UX
// https://developer.apple.com/design/human-interface-guidelines/macos/user-interaction/keyboard/
extension MainTabBarController {
    
    var switchToTabKeyCommands: [UIKeyCommand] {
        var commands: [UIKeyCommand] = []
        for (i, tab) in Tab.allCases.enumerated() {
            let title = L10n.Common.Controls.Keyboard.Common.switchToTab(tab.title)
            let input = String(i + 1)
            let command = UIKeyCommand(
                title: title,
                image: nil,
                action: #selector(MainTabBarController.switchToTabKeyCommandHandler(_:)),
                input: input,
                modifierFlags: .command,
                propertyList: tab.rawValue,
                alternates: [],
                discoverabilityTitle: nil,
                attributes: [],
                state: .off
            )
            commands.append(command)
        }
        return commands
    }
    
    var showFavoritesKeyCommand: UIKeyCommand {
        UIKeyCommand(
            title: L10n.Common.Controls.Keyboard.Common.showFavorites,
            image: nil,
            action: #selector(MainTabBarController.showFavoritesKeyCommandHandler(_:)),
            input: "f",
            modifierFlags: .command,
            propertyList: nil,
            alternates: [],
            discoverabilityTitle: nil,
            attributes: [],
            state: .off
        )
    }
    
    var openSettingsKeyCommand: UIKeyCommand {
        UIKeyCommand(
            title: L10n.Common.Controls.Keyboard.Common.openSettings,
            image: nil,
            action: #selector(MainTabBarController.openSettingsKeyCommandHandler(_:)),
            input: ",",
            modifierFlags: .command,
            propertyList: nil,
            alternates: [],
            discoverabilityTitle: nil,
            attributes: [],
            state: .off
        )
    }
    
    var composeNewPostKeyCommand: UIKeyCommand {
        UIKeyCommand(
            title: L10n.Common.Controls.Keyboard.Common.composeNewPost,
            image: nil,
            action: #selector(MainTabBarController.composeNewPostKeyCommandHandler(_:)),
            input: "n",
            modifierFlags: .command,
            propertyList: nil,
            alternates: [],
            discoverabilityTitle: nil,
            attributes: [],
            state: .off
        )
    }
    
    override var keyCommands: [UIKeyCommand]? {
        guard let topMost = self.topMost else {
            return []
        }
        
        var commands: [UIKeyCommand] = []
        
        if topMost.isModal {
            
        } else {
            // switch tabs
            commands.append(contentsOf: switchToTabKeyCommands)
            
            // show compose
            if !(self.topMost is ComposeViewController) {
                commands.append(composeNewPostKeyCommand)
            }
            
            // show favorites
            if !(self.topMost is FavoriteViewController) {
                commands.append(showFavoritesKeyCommand)
            }
            
            // open settings
            if context.settingService.currentSetting.value != nil {
                commands.append(openSettingsKeyCommand)
            }
        }

        return commands
    }
    
    @objc private func switchToTabKeyCommandHandler(_ sender: UIKeyCommand) {
        guard let rawValue = sender.propertyList as? Int,
              let tab = Tab(rawValue: rawValue) else { return }
        os_log(.info, log: .debug, "%{public}s[%{public}ld], %{public}s: %s", ((#file as NSString).lastPathComponent), #line, #function, tab.title)
        
        guard let index = Tab.allCases.firstIndex(of: tab) else { return }
        let previousTab = Tab(rawValue: selectedIndex)
        selectedIndex = index
        if let tab = Tab(rawValue: index) {
            currentTab = tab
        }

        if let previousTab = previousTab {
            switch (tab, previousTab) {
            case (.home, .home):
                guard let navigationController = topMost?.navigationController else { return }
                if navigationController.viewControllers.count > 1 {
                    // pop to top when previous tab position already is home
                    navigationController.popToRootViewController(animated: true)
                } else if let homeTimelineViewController = topMost as? HomeTimelineViewController {
                    // trigger scrollToTop if topMost is home timeline
                    homeTimelineViewController.scrollToTop(animated: true)
                }
            default:
                break
            }
        }
    }
    
    @objc private func showFavoritesKeyCommandHandler(_ sender: UIKeyCommand) {
        os_log(.info, log: .debug, "%{public}s[%{public}ld], %{public}s", ((#file as NSString).lastPathComponent), #line, #function)
        let favoriteViewModel = FavoriteViewModel(context: context)
        coordinator.present(scene: .favorite(viewModel: favoriteViewModel), from: nil, transition: .show)
    }
    
    @objc private func openSettingsKeyCommandHandler(_ sender: UIKeyCommand) {
        os_log(.info, log: .debug, "%{public}s[%{public}ld], %{public}s", ((#file as NSString).lastPathComponent), #line, #function)
        guard let setting = context.settingService.currentSetting.value else { return }
        let settingsViewModel = SettingsViewModel(context: context, setting: setting)
        coordinator.present(scene: .settings(viewModel: settingsViewModel), from: nil, transition: .modal(animated: true, completion: nil))
    }
    
    @objc private func composeNewPostKeyCommandHandler(_ sender: UIKeyCommand) {
        os_log(.info, log: .debug, "%{public}s[%{public}ld], %{public}s", ((#file as NSString).lastPathComponent), #line, #function)
        let composeViewModel = ComposeViewModel(context: context, composeKind: .post)
        coordinator.present(scene: .compose(viewModel: composeViewModel), from: nil, transition: .modal(animated: true, completion: nil))
    }
    
}

#if ASDK
extension MainTabBarController {
    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        guard let event = event else { return }
        switch event.subtype {
        case .motionShake:
            let alertController = UIAlertController(title: "ASDK Debug Panel", message: nil, preferredStyle: .alert)
            let toggleHomeAction = UIAlertAction(title: "Toggle Home", style: .default) { [weak self] _ in
                guard let self = self else { return }
                MainTabBarController.toggleAsyncHome()
                let okAlertController = UIAlertController(title: "Success", message: "Please restart the app", preferredStyle: .alert)
                let okAction = UIAlertAction(title: "OK", style: .default, handler: nil)
                okAlertController.addAction(okAction)
                self.coordinator.present(scene: .alertController(alertController: okAlertController), from: nil, transition: .alertController(animated: true, completion: nil))
            }
            alertController.addAction(toggleHomeAction)
            let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
            alertController.addAction(cancelAction)
            self.coordinator.present(scene: .alertController(alertController: alertController), from: nil, transition: .alertController(animated: true, completion: nil))
        default:
            break
        }
    }
    
    static func toggleAsyncHome() {
        UserDefaults.shared.preferAsyncHomeTimeline.toggle()
    }
}
#endif
