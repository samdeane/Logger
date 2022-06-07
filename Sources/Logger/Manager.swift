// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Created by Sam Deane, 15/02/2018.
// All code (c) 2018 - present day, Elegant Chaos Limited.
// For licensing terms, see http://elegantchaos.com/license/liberal/.
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

import Foundation

/// The main controller in charge of the logging system.
/// This is typically a singleton, and in most cases should not need
/// to be accessed at all from client code.
///
/// If you do need to the default instance - for example to
/// dynamically configure it, or introspect the list of channels,
/// you can access it with ``Manager.shared``.
///
/// Other instances can be created explicitly if necessary. This should be
/// avoided as they will share the same UserDefaults settings,
/// but may be useful for testing purposes.

public class Manager {
    typealias AssociatedChannelData = [Channel: Any]
    typealias AssociatedHandlerData = [Handler: AssociatedChannelData]

    public static let channelsUpdatedNotification = NSNotification.Name(rawValue: "com.elegantchaos.logger.channels.updated")

    let defaults: UserDefaults
    var channels: [Channel] = []
    var associatedData: AssociatedHandlerData = [:]
    var fatalHandler: FatalHandler = defaultFatalHandler
    var queue: DispatchQueue = .init(label: "com.elegantchaos.logger", qos: .utility, attributes: [], autoreleaseFrequency: DispatchQueue.AutoreleaseFrequency.inherit)
    lazy var channelsEnabledInSettings: [String] = loadChannelSettings()

    required init(defaults: UserDefaults = UserDefaults.standard) {
        self.defaults = defaults
    }

    /**
     Default log manager to use for channels if nothing else is specified.

     Under normal circumstances it makes sense for everything to share the same manager,
     which is why this exists.

     There are times (particularly testing) when we might want to use a different manager
     though, which is why it's not a true singleton.
     */

    public static let shared = initDefaultManager()

    /// Initialise the default log manager.
    static func initDefaultManager() -> Self {
        #if ensureUniqueManager
            /// We really do want there to only be a single instance of this, even if the logger library has mistakenly been
            /// linked multiple times, so we store it in the thread dictionary for the main thread, and retrieve it from there if necessary
            let dictionary = Thread.main.threadDictionary
            if let manager = dictionary["Logger.Manager"] {
                return unsafeBitCast(manager as AnyObject, to: Manager.self) // a normal cast might fail here if the code has been linked multiple times, since the class could be different (but identical)
            }

            let manager = Manager()
            dictionary["Logger.Manager"] = manager
            return manager

        #else
            return Self()
        #endif
    }

    /**
     Return arbitrary data associated with a channel/handler pair.
     This provides handlers with a mechanism to use to store per-channel state.

     If no data is stored, the setter closure is called to provide it.
     */

    public func associatedData<T>(handler: Handler, channel: Channel, setter: () -> T) -> T {
        var handlerData = associatedData[handler]
        if handlerData == nil {
            handlerData = [:]
            associatedData[handler] = handlerData
        }

        var channelData = handlerData![channel] as? T
        if channelData == nil {
            channelData = setter()
            handlerData![channel] = channelData
        }

        return channelData!
    }

    /**
     An array of the names of the log channels
     that were persistently enabled - either in the settings
     or on the command line.
     */

    func logStartup(enabledChannels: String) {
        if let mode = ProcessInfo.processInfo.environment["LoggerDebug"], mode == "1" {
            #if DEBUG
                let mode = "debug"
            #else
                let mode = "release"
            #endif
            print("\nLogger running in \(mode) mode.")
            if enabledChannels.isEmpty {
                print("All channels currently disabled.\n")
            } else {
                print("Enabled log channels: \(enabledChannels)\n")
            }
        }
    }

    /**
         Pause until everything in the log queue has been logged.

         You shouldn't generally need to do this, but it's helpful if you
         need to ensure that all output reaches its destination before some
         action (exiting, for example).
     */

    public func flush() {
        queue.sync {
            // do nothing
        }
    }
}

// MARK: Fatal Error Handling

public extension Manager {
    typealias FatalHandler = (Any, Channel, StaticString, UInt) -> Never

    /**
     Default handler when a channel is sent a fatal error.

     Just calls the system's fatal error function and exits.
     */

    static func defaultFatalHandler(_ message: Any, channel: Channel, file: StaticString = #file, line: UInt = #line) -> Never {
        fatalError("Channel \(channel.name) was sent fatal message.\n\(message)", file: file, line: line)
    }

    /**
     Install a custom handler for fatal errors.
     */

    @discardableResult func installFatalErrorHandler(_ handler: @escaping FatalHandler) -> FatalHandler {
        let previous = fatalHandler
        fatalHandler = handler
        return previous
    }

    /**
     Restore the default fatal error handler.
     */

    func resetFatalErrorHandler() {
        fatalHandler = Manager.defaultFatalHandler
    }
}

// MARK: Channels

public extension Manager {
    /**
      Add to our list of registered channels.
     */

    internal func register(channel: Channel) {
        queue.async {
            self.channels.append(channel)
            #if os(macOS) || os(iOS)
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: Manager.channelsUpdatedNotification, object: self)
                }
            #endif
        }
    }

    /**
     All the channels registered with the manager.

     Channels get registered when they're first used,
     which may not necessarily be when the application first runs.
     */

    var registeredChannels: [Channel] {
        var result = [Channel]()
        queue.sync {
            result.append(contentsOf: channels)
        }
        return result
    }

    var enabledChannels: [Channel] {
        var result: [Channel]?
        queue.sync {
            result = channels.filter { $0.enabled }
        }
        return result!
    }

    func channel(named name: String) -> Channel? {
        return registeredChannels.first(where: { $0.name == name })
    }
}

// MARK: Settings

extension Manager {
    static let persistentLogsKey = "logs-persistent"
    static let logsKey = "logs"

    /**
         Calculate the list of enabled channels.

         This is determined by two settings: `logsKey` and `persistentLogsKey`,
         both of which contain comma-delimited strings.

         The persistentLogs setting contains the names of all the channels that were
         enabled last time. This is expected to be read from the user defaults.

         The logs setting contains overrides, and if present, is expected to have
         been supplied on the command line.

         Items in the overrides can be in two forms:

             - "name1,-name2,+name3": *modifies* the list by enabling/disabling named channels
             - "=name1,name2,name3": *resets* the list to the named channels

         Note that `+name` is a synonym for `name` in the first form - there just for symmetry.
         Note also that if any item in the list begins with `=`, the second form is used and the list is reset.
     */

    public func loadChannelSettings() -> [String] {
        var persistent = defaults.string(forKey: Manager.persistentLogsKey)?.split(separator: ",") ?? []
        let changes = defaults.string(forKey: Manager.logsKey)?.split(separator: ",") ?? []

        var onlyDeltas = true
        var newItems = [String.SubSequence]()
        for item in changes {
            var trimmed = item
            if let first = item.first {
                switch first {
                case "=":
                    trimmed.removeFirst()
                    newItems.append(trimmed)
                    onlyDeltas = false
                case "-":
                    trimmed.removeFirst()
                    if let index = persistent.firstIndex(of: trimmed) {
                        persistent.remove(at: index)
                    }
                case "+":
                    trimmed.removeFirst()
                    newItems.append(trimmed)
                default:
                    newItems.append(item)
                }
            }
        }

        if onlyDeltas {
            persistent.append(contentsOf: newItems)
        } else {
            persistent = newItems
        }

        var uniquePersistent = Set<String.SubSequence>()
        for item in persistent { uniquePersistent.insert(item) }
        let string = uniquePersistent.joined(separator: ",")
        let list = uniquePersistent.map { String($0) }

        defaults.set(string, forKey: Manager.persistentLogsKey)
        defaults.set("", forKey: Manager.logsKey)
        logStartup(enabledChannels: string)

        return list
    }

    /**
      Update the enabled/disabled state of one or more channels.
      The change is persisted in the settings, and will be restored
      next time the application runs.
     */

    public func update(channels: [Channel], state: Bool) {
        for channel in channels {
            channel.enabled = state
            let change = channel.enabled ? "enabled" : "disabled"
            print("Channel \(channel.name) \(change).")
        }

        saveChannelSettings()
    }

    /**
      Save the list of currently enabled channels.
     */

    func saveChannelSettings() {
        let names = enabledChannels.map { $0.fullName }
        defaults.set(names.joined(separator: ","), forKey: Manager.persistentLogsKey)
    }

    /**
     Returns a copy of the input arguments array which has had any
     arguments that we handle stripped out of it.

     This is useful for clients that are parsing the command line arguments,
     particularly with something like Docopt.

     Our options are meant to be semi-hidden, and we don't really want every
     client of this library to have to know about all of them, or to have
     to document them.
     */

    public static func removeLoggingOptions(from arguments: [String]) -> [String] {
        var args: [String] = []
        var dropNext = false
        for argument in arguments {
            if argument == "-\(Manager.logsKey)" {
                dropNext = true
            } else if dropNext {
                dropNext = false
            } else if !argument.starts(with: "--logs=") {
                args.append(argument)
            }
        }
        return args
    }
}
