// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//  Created by Sam Deane on 28/06/2019.
//  All code (c) 2019 - present day, Elegant Chaos Limited.
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#if canImport(UIKit)

import UIKit
import Logger

public class LoggerMenu: UIResponder {
    static let debugMenuIdentifier = UIMenu.Identifier("com.elegantchaos.logger.debug.menu")
    static let loggerMenuIdentifier = UIMenu.Identifier("com.elegantchaos.logger.logger.menu")
    static let channelsMenuIdentifier = UIMenu.Identifier("com.elegantchaos.logger.channels.menu")

    var _next: UIResponder? = nil
    var channelMenu: UIMenu? = nil
    
    public override var next: UIResponder? {
        get {
            return _next
        }
        
        set (value) {
            _next = value
        }
    }
    
    public override func buildMenu(with builder: UIMenuBuilder) {
        guard builder.system == .main else { return }
        
        let debugMenu = buildDebugMenu(with: builder)
        addLoggerMenu(to: debugMenu, with: builder)
        
        NotificationCenter.default.addObserver(forName: Manager.channelsUpdatedNotification, object: Logger.defaultManager, queue: OperationQueue.main) {_ in
            UIMenuSystem.main.setNeedsRebuild()
        }
        
        
    }
    
    public override func validate(_ command: UICommand) {
        if command.action == #selector(toggleChannel) {
            if let channel = channel(for: command) {
                command.state = channel.enabled ? .on : .off
            }
        }
    }
    
    func buildDebugMenu(with builder: UIMenuBuilder, identifier: UIMenu.Identifier = LoggerMenu.debugMenuIdentifier) -> UIMenu {
        // if the menu already exists, just return it
        if let menu = builder.menu(for: identifier) {
            return menu
        }
        
        // if not, insert one before the Help menu
        let debugMenu = UIMenu(__title: "Debug",
                               image: nil,
                               identifier: identifier,
                               options: [],
                               children: []
        )
        builder.insertSibling(debugMenu, beforeMenu: .help)
        return debugMenu
    }
    
    func addLoggerMenu(to debugMenu: UIMenu, with builder: UIMenuBuilder) {
        
        let enableAllItem = UIKeyCommand(input: "E", modifierFlags: [.command, .control], action: #selector(enableAllChannels))
        enableAllItem.title = "Enable All"
        
        let disableAllItem = UIKeyCommand(input: "D", modifierFlags: [.command, .control], action: #selector(disableAllChannels(_:)))
        disableAllItem.title = "Disable All"

        let loggerMenu = UIMenu(__title: "Logger",
                                image: nil,
                                identifier: LoggerMenu.loggerMenuIdentifier,
                                options: [],
                                children: [
                                    enableAllItem,
                                    disableAllItem
            ]
        )
        builder.insertChild(loggerMenu, atStartOfMenu: debugMenu.identifier)
        
        var channelItems = [UIMenuElement]()
        for channel in Logger.defaultManager.registeredChannels {
            let item = UICommand(title: channel.name, image: nil, action: #selector(toggleChannel), propertyList: channel.name, alternates: [], discoverabilityTitle: channel.name, attributes: [], state: .on)
            item.title = channel.name
            channelItems.append(item)
        }
        
        let channelMenu = UIMenu(__title: "Channels",
                                 image: nil,
                                 identifier: LoggerMenu.channelsMenuIdentifier,
                                 options: [.displayInline],
                                 children: channelItems
        )
        builder.insertChild(channelMenu, atEndOfMenu: loggerMenu.identifier)
        self.channelMenu = channelMenu
    }
    
    func channel(for command: UICommand) -> Channel? {
        guard let name = command.propertyList as? String else { return nil }
        return Logger.defaultManager.channel(named: name)
    }
    
    @IBAction func toggleChannel(_ sender: Any) {
        if let command = sender as? UICommand, let channel = channel(for: command) {
            Logger.defaultManager.update(channels: [channel], state: !channel.enabled)
        }
    }
    
    @IBAction func enableAllChannels(_ sender: Any) {
        let manager = Logger.defaultManager
        manager.update(channels: manager.registeredChannels, state: true)
    }
    
    @IBAction func disableAllChannels(_ sender: Any) {
        let manager = Logger.defaultManager
        manager.update(channels: manager.registeredChannels, state: false)
    }
}

#endif
