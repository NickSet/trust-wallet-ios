// Copyright SIX DAY LLC. All rights reserved.

import UIKit
import Eureka
import StoreKit

protocol SettingsViewControllerDelegate: class {
    func didAction(action: SettingsAction, in viewController: SettingsViewController)
}

class SettingsViewController: FormViewController, Coordinator {
    var coordinators: [Coordinator] = []
    struct Values {
        static let currencyPopularKey = "0"
        static let currencyAllKey = "1"
    }
    private var config = Config()
    private var lock = Lock()
    private let helpUsCoordinator = HelpUsCoordinator()
    weak var delegate: SettingsViewControllerDelegate?
    var isPasscodeEnabled: Bool {
        return lock.isPasscodeSet()
    }
    lazy var viewModel: SettingsViewModel = {
        return SettingsViewModel(isDebug: isDebug)
    }()

    lazy var networkStateView: NetworkStateView? = {
        let view = NetworkStateView(frame: .zero)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    let session: WalletSession
    let keystore: Keystore
    let balanceCoordinator: TokensBalanceService
    let accountsCoordinator: AccountsCoordinator

    init(
        session: WalletSession,
        keystore: Keystore,
        balanceCoordinator: TokensBalanceService,
        accountsCoordinator: AccountsCoordinator
    ) {
        self.session = session
        self.keystore = keystore
        self.balanceCoordinator = balanceCoordinator
        self.accountsCoordinator = accountsCoordinator
        super.init(nibName: nil, bundle: nil)
        self.chaineStateObservation()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        if let stateView = networkStateView {
            self.navigationItem.leftBarButtonItem = UIBarButtonItem(customView: stateView)
        }
        title = NSLocalizedString("settings.navigation.title", value: "Settings", comment: "")
        let account = session.account

        form = Section()

            <<< PushRow<RPCServer> { [weak self] in
                guard let strongSelf = self else {
                    return
                }
                $0.title = strongSelf.viewModel.networkTitle
                $0.options = strongSelf.viewModel.servers
                $0.value = RPCServer(chainID: strongSelf.config.chainID)
                $0.selectorTitle = strongSelf.viewModel.networkTitle
                $0.displayValueFor = { value in
                    return value?.displayName
                }
            }.onChange { [weak self] row in
                let server = row.value ?? RPCServer.main
                self?.run(action: .RPCServer(server: server))
            }.onPresent { _, selectorController in
                selectorController.enableDeselection = false
                selectorController.sectionKeyForValue = { option in
                    switch option {
                    case .main, .classic, .callisto, .poa: return ""
                    case .kovan, .ropsten, .rinkeby, .sokol: return NSLocalizedString("settings.network.test.label.title", value: "Test", comment: "")
                    case .custom:
                        return NSLocalizedString("settings.network.custom.label.title", value: "Custom", comment: "")
                    }
                }
            }.cellSetup { cell, _ in
                cell.imageView?.image = R.image.settings_server()
            }

            <<< AppFormAppearance.button { [weak self] row in
                guard let `self` = self else { return }
                row.cellStyle = .value1
                row.presentationMode = .show(controllerProvider: ControllerProvider<UIViewController>.callback {
                    return self.accountsCoordinator.accountsViewController
                }, onDismiss: { _ in })
            }.cellUpdate { cell, _ in
                cell.textLabel?.textColor = .black
                cell.imageView?.image = R.image.settings_wallet()
                cell.textLabel?.text = NSLocalizedString("settings.wallets.button.title", value: "Wallets", comment: "")
                cell.detailTextLabel?.text = String(account.address.description.prefix(10)) + "..."
                cell.accessoryType = .disclosureIndicator
            }

            +++ Section(NSLocalizedString("settings.security.label.title", value: "Security", comment: ""))

            <<< SwitchRow { [weak self] in
                $0.title = self?.viewModel.passcodeTitle
                $0.value = self?.isPasscodeEnabled
            }.onChange { [unowned self] row in
                if row.value == true {
                    self.setPasscode { result in
                        row.value = result
                        row.updateCell()
                    }
                } else {
                    self.lock.deletePasscode()
                }
            }.cellSetup { cell, _ in
                cell.imageView?.image = R.image.settings_lock()
            }

            <<< AppFormAppearance.button { [weak self] row in
                row.cellStyle = .value1
                row.presentationMode = .show(controllerProvider: ControllerProvider<UIViewController>.callback {
                    let controller = NotificationsViewController()
                    controller.didChange = { [weak self] change in
                        self?.run(action: .pushNotifications(change))
                    }
                    return controller
                }, onDismiss: { _ in
            })
            }.cellUpdate { cell, _ in
                cell.imageView?.image = R.image.settings_push_notifications()
                cell.textLabel?.text = NSLocalizedString("settings.pushNotifications.title", value: "Push Notifications", comment: "")
                cell.accessoryType = .disclosureIndicator
            }

            +++ Section()

            <<< PushRow<Currency> { [weak self] in
                $0.title = self?.viewModel.currencyTitle
                $0.selectorTitle = self?.viewModel.currencyTitle
                $0.options = self?.viewModel.currency
                $0.value = self?.config.currency
                $0.displayValueFor = { value in
                    let currencyCode = value?.rawValue ?? ""
                    return currencyCode + " - " + (NSLocale.current.localizedString(forCurrencyCode: currencyCode) ?? "")
                }
            }.onChange { [weak self]  row in
                guard let value = row.value else { return }
                self?.config.currency = value
                self?.run(action: .currency)
            }.onPresent { _, selectorController in
                selectorController.enableDeselection = false
                selectorController.sectionKeyForValue = { option in
                    switch option {
                    case .USD, .EUR, .GBP, .AUD, .RUB: return Values.currencyPopularKey
                    default: return Values.currencyAllKey
                    }
                }
                selectorController.sectionHeaderTitleForKey = { option in
                    switch option {
                    case Values.currencyPopularKey:
                        return NSLocalizedString("settings.currency.popular.label.title", value: "Popular", comment: "")
                    case Values.currencyAllKey:
                        return NSLocalizedString("settings.currency.all.label.title", value: "All", comment: "")
                    default: return ""
                    }
                }
            }.cellSetup { cell, _ in
                cell.imageView?.image = R.image.settingsCurrency()
            }

//            <<< AppFormAppearance.button { row in
//                row.cellStyle = .value1
//                row.presentationMode = .show(controllerProvider: ControllerProvider<UIViewController>.callback {
//                    return PreferencesViewController()
//                }, onDismiss: { _ in })
//            }.cellUpdate { cell, _ in
//                cell.textLabel?.textColor = .black
//                cell.imageView?.image = R.image.settings_preferences()
//                cell.textLabel?.text = NSLocalizedString("settings.preferences.title", value: "Preferences", comment: "")
//                cell.accessoryType = .disclosureIndicator
//            }

            +++ Section(NSLocalizedString("settings.joinCommunity.label.title", value: "Join Community", comment: ""))

            <<< linkProvider(type: .twitter)
            <<< linkProvider(type: .telegram)
            <<< linkProvider(type: .facebook)
            <<< linkProvider(type: .discord)

            +++ Section(NSLocalizedString("settings.support.label.title", value: "Support", comment: ""))

            <<< AppFormAppearance.button { button in
                button.title = NSLocalizedString("settings.shareWithFriends.button.title", value: "Share With Friends", comment: "")
                button.cell.imageView?.image = R.image.settingsShare()
            }.onCellSelection { [unowned self] cell, _  in
                self.helpUsCoordinator.presentSharing(in: self, from: cell.contentView)
            }

            <<< AppFormAppearance.button { button in
                button.title = NSLocalizedString("settings.rateUsAppStore.button.title", value: "Rate Us on App Store", comment: "")
            }.onCellSelection { [weak self] _, _  in
                self?.helpUsCoordinator.rateUs()
            }.cellSetup { cell, _ in
                cell.imageView?.image = R.image.settings_rating()
            }

            +++ Section()

            <<< AppFormAppearance.button { row in
                row.cellStyle = .value1
                row.presentationMode = .show(controllerProvider: ControllerProvider<UIViewController>.callback {
                    return SupportViewController()
                }, onDismiss: { _ in })
            }.cellUpdate { cell, _ in
                cell.textLabel?.textColor = .black
                cell.imageView?.image = R.image.settings_terms()
                cell.textLabel?.text = NSLocalizedString("settings.support.title", value: "Support", comment: "")
                cell.accessoryType = .disclosureIndicator
            }

            +++ Section()

            <<< TextRow {
                $0.title = NSLocalizedString("settings.version.label.title", value: "Version", comment: "")
                $0.value = Bundle.main.fullVersion
                $0.disabled = true
            }
    }

    func setPasscode(completion: ((Bool) -> Void)? = .none) {
        let coordinator = LockCreatePasscodeCoordinator(
            model: LockCreatePasscodeViewModel()
        )
        coordinator.delegate = self
        coordinator.start()
        coordinator.lockViewController.willFinishWithResult = { [weak self] result in
            completion?(result)
            self?.navigationController?.dismiss(animated: true, completion: nil)
        }
        addCoordinator(coordinator)
        navigationController?.present(coordinator.navigationController, animated: true, completion: nil)
    }

    private func linkProvider(
        type: URLServiceProvider
    ) -> ButtonRow {
        return AppFormAppearance.button {
            $0.title = type.title
        }.onCellSelection { [unowned self] _, _ in
            if let localURL = type.localURL, UIApplication.shared.canOpenURL(localURL) {
                UIApplication.shared.open(localURL, options: [:], completionHandler: .none)
            } else {
                self.openURL(type.remoteURL)
            }
        }.cellSetup { cell, _ in
            cell.imageView?.image = type.image
        }.cellUpdate { cell, _ in
            cell.accessoryType = .disclosureIndicator
            cell.textLabel?.textAlignment = .left
            cell.textLabel?.textColor = .black
        }
    }

    private func chaineStateObservation() {
        self.session.chainState.chainStateCompletion = { [weak self] (state, block) in
            let condition = NetworkCondition.from(state, block)
            self?.networkStateView?.viewModel = NetworkConditionViewModel(condition: condition)
        }
    }

    func run(action: SettingsAction) {
        delegate?.didAction(action: action, in: self)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension SettingsViewController: LockCreatePasscodeCoordinatorDelegate {
    func didCancel(in coordinator: LockCreatePasscodeCoordinator) {
        coordinator.lockViewController.willFinishWithResult?(false)
        navigationController?.dismiss(animated: true, completion: nil)
        removeCoordinator(coordinator)
    }
}
