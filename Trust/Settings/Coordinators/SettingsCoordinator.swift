// Copyright SIX DAY LLC. All rights reserved.

import Foundation
import TrustKeystore
import UIKit

protocol SettingsCoordinatorDelegate: class {
    func didRestart(with account: Wallet, in coordinator: SettingsCoordinator)
    func didUpdateAccounts(in coordinator: SettingsCoordinator)
    func didCancel(in coordinator: SettingsCoordinator)
}

class SettingsCoordinator: Coordinator {

    let navigationController: UINavigationController
    let keystore: Keystore
    let session: WalletSession
    let storage: TransactionsStorage
    let balanceCoordinator: TokensBalanceService
    weak var delegate: SettingsCoordinatorDelegate?
    let pushNotificationsRegistrar = PushNotificationsRegistrar()
    var coordinators: [Coordinator] = []

    lazy var accountsCoordinator: AccountsCoordinator = {
        let coordinator = AccountsCoordinator(
            navigationController: navigationController,
            keystore: keystore,
            session: session,
            balanceCoordinator: balanceCoordinator
        )
        coordinator.delegate = self
        return coordinator
    }()

    lazy var rootViewController: SettingsViewController = {
        let controller = SettingsViewController(
            session: session,
            keystore: keystore,
            balanceCoordinator: balanceCoordinator,
            accountsCoordinator: accountsCoordinator
        )
        controller.delegate = self
        controller.modalPresentationStyle = .pageSheet
        return controller
    }()

    init(
        navigationController: UINavigationController = NavigationController(),
        keystore: Keystore,
        session: WalletSession,
        storage: TransactionsStorage,
        balanceCoordinator: TokensBalanceService
    ) {
        self.navigationController = navigationController
        self.navigationController.modalPresentationStyle = .formSheet
        self.keystore = keystore
        self.session = session
        self.storage = storage
        self.balanceCoordinator = balanceCoordinator

        addCoordinator(accountsCoordinator)
    }

    func start() {
        navigationController.viewControllers = [rootViewController]
    }

    func restart(for wallet: Wallet) {
        delegate?.didRestart(with: wallet, in: self)
    }

    private func presentSwitchNetworkWarning(for server: RPCServer) {
        var config = session.config
        let viewModel = SettingsViewModel()
        let alertViewController = UIAlertController.alertController(
            title: viewModel.testNetworkWarningTitle,
            message: viewModel.testNetworkWarningMessage,
            style: .alert,
            in: navigationController
        )

        alertViewController.popoverPresentationController?.sourceView = navigationController.view
        alertViewController.popoverPresentationController?.sourceRect = navigationController.view.centerRect

        let okAction = UIAlertAction(title: NSLocalizedString("OK", value: "OK", comment: ""), style: .default) { _ in
            self.switchNetwork(for: server)
        }
        let dontShowAgainAction = UIAlertAction(title: viewModel.testNetworkWarningDontShowAgainLabel, style: .default) { _ in
            config.testNetworkWarningOff = true
            self.switchNetwork(for: server)
        }

        alertViewController.addAction(dontShowAgainAction)
        alertViewController.addAction(okAction)
        navigationController.present(alertViewController, animated: true, completion: nil)
    }

    func prepareSwitchNetwork(for server: RPCServer) {
        if server.isTestNetwork == true && session.config.testNetworkWarningOff == false {
            presentSwitchNetworkWarning(for: server)
        } else {
            switchNetwork(for: server)
        }
    }

    func switchNetwork(for server: RPCServer) {
        var config = session.config
        config.chainID = server.chainID
        restart(for: session.account)
    }
}

extension SettingsCoordinator: SettingsViewControllerDelegate {
    func didAction(action: SettingsAction, in viewController: SettingsViewController) {
        switch action {
        case .RPCServer(let server):
            prepareSwitchNetwork(for: server)
        case .currency:
            restart(for: session.account)
        case .pushNotifications(let change):
            switch change {
            case .state(let isEnabled):
                switch isEnabled {
                case true:
                    pushNotificationsRegistrar.register()
                case false:
                    pushNotificationsRegistrar.unregister()
                }
            case .preferences:
                pushNotificationsRegistrar.register()
            }
        }
    }
}

extension SettingsCoordinator: AccountsCoordinatorDelegate {
    func didAddAccount(account: Wallet, in coordinator: AccountsCoordinator) {
        delegate?.didUpdateAccounts(in: self)
    }

    func didDeleteAccount(account: Wallet, in coordinator: AccountsCoordinator) {
        storage.deleteAll()
        delegate?.didUpdateAccounts(in: self)
        guard !coordinator.accountsViewController.hasWallets else { return }
        coordinator.navigationController.dismiss(animated: true, completion: nil)
        delegate?.didCancel(in: self)
    }

    func didCancel(in coordinator: AccountsCoordinator) {
        coordinator.navigationController.dismiss(animated: true, completion: nil)
        removeCoordinator(coordinator)
    }

    func didSelectAccount(account: Wallet, in coordinator: AccountsCoordinator) {
        coordinator.navigationController.dismiss(animated: true, completion: nil)
        removeCoordinator(coordinator)
        restart(for: account)
    }
}
