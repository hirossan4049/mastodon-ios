//
//  SettingsViewModel.swift
//  Mastodon
//
//  Created by ihugo on 2021/4/7.
//

import Combine
import CoreData
import CoreDataStack
import Foundation
import MastodonSDK
import UIKit
import os.log
import AuthenticationServices

class SettingsViewModel {
    
    var disposeBag = Set<AnyCancellable>()

    let context: AppContext
    var mastodonAuthenticationController: MastodonAuthenticationController?

    // input
    let setting: CurrentValueSubject<Setting, Never>
    var updateDisposeBag = Set<AnyCancellable>()
    var createDisposeBag = Set<AnyCancellable>()
    
    let viewDidLoad = PassthroughSubject<Void, Never>()
    
    // output
    var dataSource: UITableViewDiffableDataSource<SettingsSection, SettingsItem>!
    /// create a subscription when:
    /// - does not has one
    /// - does not find subscription for selected trigger when change trigger
    let createSubscriptionSubject = PassthroughSubject<(triggerBy: String, values: [Bool?]), Never>()
    let currentInstance = CurrentValueSubject<Mastodon.Entity.Instance?, Never>(nil)
    
    /// update a subscription when:
    /// - change switch for specified alerts
    let updateSubscriptionSubject = PassthroughSubject<(triggerBy: String, values: [Bool?]), Never>()
    
    lazy var privacyURL: URL? = {
        guard let box = AppContext.shared.authenticationService.activeMastodonAuthenticationBox.value else {
            return nil
        }
        
        return Mastodon.API.privacyURL(domain: box.domain)
    }()
    
    init(context: AppContext, setting: Setting) {
        self.context = context
        self.setting = CurrentValueSubject(setting)
        
        self.setting
            .sink(receiveValue: { [weak self] setting in
                guard let self = self else { return }
                self.processDataSource(setting)
            })
            .store(in: &disposeBag)

        context.authenticationService.activeMastodonAuthenticationBox
            .compactMap { $0?.domain }
            .map { context.apiService.instance(domain: $0) }
            .switchToLatest()
            .sink { [weak self] completion in
                guard let self = self else { return }
                switch completion {
                case .failure(let error):
                    os_log(.info, log: .debug, "%{public}s[%{public}ld], %{public}s: fetch instance fail: %s", ((#file as NSString).lastPathComponent), #line, #function, error.localizedDescription)
                    self.currentInstance.value = nil
                case .finished:
                    os_log(.info, log: .debug, "%{public}s[%{public}ld], %{public}s: fetch instance success", ((#file as NSString).lastPathComponent), #line, #function)

                }
            } receiveValue: { [weak self] response in
                guard let self = self else { return }
                self.currentInstance.value = response.value
            }
            .store(in: &disposeBag)
    }
    
    deinit {
        os_log(.info, log: .debug, "%{public}s[%{public}ld], %{public}s:", ((#file as NSString).lastPathComponent), #line, #function)
    }
    
}

extension SettingsViewModel {

    func openAuthenticationPage(
        authenticateURL: URL,
        presentationContextProvider: ASWebAuthenticationPresentationContextProviding
    ) {
        let authenticationController = MastodonAuthenticationController(
            context: self.context,
            authenticateURL: authenticateURL
        )

        self.mastodonAuthenticationController = authenticationController
        authenticationController.authenticationSession?.presentationContextProvider = presentationContextProvider
        authenticationController.authenticationSession?.start()
    }
    
    // MARK: - Private methods
    private func processDataSource(_ setting: Setting) {
        guard let dataSource = self.dataSource else { return }
        var snapshot = NSDiffableDataSourceSnapshot<SettingsSection, SettingsItem>()

        // appearance
        let appearanceItems = [SettingsItem.appearance(settingObjectID: setting.objectID)]
        snapshot.appendSections([.appearance])
        snapshot.appendItems(appearanceItems, toSection: .appearance)

        // notification
        let notificationItems = SettingsItem.NotificationSwitchMode.allCases.map { mode in
            SettingsItem.notification(settingObjectID: setting.objectID, switchMode: mode)
        }
        snapshot.appendSections([.notifications])
        snapshot.appendItems(notificationItems, toSection: .notifications)

        // preference
        snapshot.appendSections([.preference])
        let preferenceItems: [SettingsItem] = SettingsItem.PreferenceType.allCases.map { preferenceType in
            SettingsItem.preference(settingObjectID: setting.objectID, preferenceType: preferenceType)
        }
        snapshot.appendItems(preferenceItems,toSection: .preference)

        // boring zone
        let boringZoneSettingsItems: [SettingsItem] = {
            let links: [SettingsItem.Link] = [
                .accountSettings,
                .github,
                .termsOfService,
                .privacyPolicy
            ]
            let items = links.map { SettingsItem.boringZone(item: $0) }
            return items
        }()
        snapshot.appendSections([.boringZone])
        snapshot.appendItems(boringZoneSettingsItems, toSection: .boringZone)
        
        let spicyZoneSettingsItems: [SettingsItem] = {
            let links: [SettingsItem.Link] = [
                .clearMediaCache,
                .signOut
            ]
            let items = links.map { SettingsItem.spicyZone(item: $0) }
            return items
        }()
        snapshot.appendSections([.spicyZone])
        snapshot.appendItems(spicyZoneSettingsItems, toSection: .spicyZone)

        dataSource.apply(snapshot, animatingDifferences: false)
    }
    
}

extension SettingsViewModel {
    func setupDiffableDataSource(
        for tableView: UITableView,
        settingsAppearanceTableViewCellDelegate: SettingsAppearanceTableViewCellDelegate,
        settingsToggleCellDelegate: SettingsToggleCellDelegate
    ) {
        dataSource = SettingsSection.tableViewDiffableDataSource(
            for: tableView,
            managedObjectContext: context.managedObjectContext,
            settingsAppearanceTableViewCellDelegate: settingsAppearanceTableViewCellDelegate,
            settingsToggleCellDelegate: settingsToggleCellDelegate
        )
        processDataSource(self.setting.value)
    }
}
