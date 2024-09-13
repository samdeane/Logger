// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Created by Sam Deane, 31/01/2018.
// All code (c) 2018 - present day, Elegant Chaos Limited.
// For licensing terms, see http://elegantchaos.com/license/liberal/.
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

import Combine
import Foundation

/**
 Represents a channel through which log messages can be sent.
 Each channel can be enabled/disabled, and configured to send its output
 to one or more handlers.
 */

public actor Channel {
  /**
     Default log handler which prints to standard out,
     without appending the channel details.
     */

  public static let stdoutHandler = PrintHandler("default", showName: false, showSubsystem: false)

  /**
     Default handler to use for channels if nothing else is specified.

     On the Mac this is an OSLogHandler, which will log directly to the console without
     sending output to stdout/stderr.

     On Linux it is a PrintHandler which will log to stdout.
     */

  static func initDefaultHandler() -> Handler {
    #if os(macOS) || os(iOS)
      return OSLogHandler("default")
    #else
      return stdoutHandler  // TODO: should perhaps be stderr instead?
    #endif
  }

  public static let defaultHandler = initDefaultHandler()

  /**
     Default subsystem if nothing else is specified.
     If the channel name is in dot syntax (x.y.z), then the last component is
     assumed to be the name, and the rest is assumed to be the subsystem.

     If there are no dots, it's all assumed to be the name, and this default
     is used for the subsytem.
     */

  static let defaultSubsystem = "com.elegantchaos.logger"

  /**
     Default log channel that clients can use to log their actual output.
     This is intended as a convenience for command line programs which actually want to produce output.
     They could of course just use print() for this (producing normal output isn't strictly speaking
     the same as logging), but this channel exists to allow output and logging to be treated in a uniform
     way.

     Unlike most channels, we want this one to default to always being on.
     */

  public static let stdout = Channel("stdout", handlers: [stdoutHandler], alwaysEnabled: true)

  public let name: String
  public let subsystem: String

  nonisolated(unsafe) public private(set) var enabled: Bool

  public var fullName: String {
    "\(subsystem).\(name)"
  }

  let manager: Manager
  var handlers: [Handler] = []

  /// MainActor isolated properties for use in the user interface.
  /// This object is observable so the UI can watch it for changes
  /// to the enabled state of the channel.
  @MainActor public class UI: Identifiable, ObservableObject {
    @Published public private(set) var enabled: Bool
    public weak var channel: Channel!
    public let id: String

    init(channel: Channel, id: String, enabled: Bool) {
      self.channel = channel
      self.id = id
      self.enabled = enabled
    }

    func setEnabled(state: Bool) {
      enabled = state
    }
  }

  public let ui: UI

  public init(
    _ name: String, handlers: @autoclosure () -> [Handler] = [defaultHandler],
    alwaysEnabled: Bool = false, manager: Manager = Manager.shared
  ) {
    let components = name.split(separator: ".")
    let last = components.count - 1
    let shortName: String
    let subName: String

    if last > 0 {
      shortName = String(components[last])
      subName = components[..<last].joined(separator: ".")
    } else {
      shortName = name
      subName = Channel.defaultSubsystem
    }

    let fullName = "\(subName).\(shortName)"
    let enabledList = manager.channelsEnabledInSettings
    let isEnabled =
      enabledList.contains(shortName) || enabledList.contains(fullName) || alwaysEnabled

    self.name = shortName
    self.subsystem = subName
    self.manager = manager
    self.enabled = isEnabled

    self.handlers = handlers()  // TODO: does this need to be a closure any more?
    self.ui = UI(channel: self, id: fullName, enabled: isEnabled)
    Task {
      await manager.register(channel: self)
    }
  }

  /**
     Log something.

     The logged value is an autoclosure, to avoid doing unnecessary work if the channel is disabled.

     If the channel is enabled, we capture the logged value in the calling thread, by evaluating the autoclosure.
     We then log the value asynchronously. The log manager serialises the logging, to avoid race conditions.

     Note that reading the `enabled` flag is not serialised, to avoid taking unnecessary locks. It's theoretically
     possible for another thread to be writing to this flag whilst we're reading it, if the channel state is being
     changed. Thread sanitizer might flag this up, but it's harmless, and should generally only happen in a debug
     setting.
     */

  public func log(
    _ logged: @autoclosure () -> Any, file: StaticString = #file, line: UInt = #line,
    column: UInt = #column, function: StaticString = #function
  ) {
    if enabled {
      let value = logged()
      let context = Context(file: file, line: line, column: column, function: function)
      self.handlers.forEach { $0.log(channel: self, context: context, logged: value) }
    }
  }

  public func debug(
    _ logged: @autoclosure () -> Any, file: StaticString = #file, line: UInt = #line,
    column: UInt = #column, function: StaticString = #function
  ) {
    #if DEBUG
      if enabled {
        log(logged(), file: file, line: line, column: column, function: function)
      }
    #endif
  }

  public func fatal(
    _ logged: @autoclosure () -> Any, file: StaticString = #file, line: UInt = #line,
    column: UInt = #column, function: StaticString = #function
  ) -> Never {
    let value = logged()
    log(value, file: file, line: line, column: column, function: function)
    manager.fatalHandler(value, self, file, line)
  }
}

extension Channel: Hashable {
  // For now, we treat channels with the same name as equal,
  // as long as they belong to the same manager.
  nonisolated public func hash(into hasher: inout Hasher) {
    name.hash(into: &hasher)
  }

  public static func == (lhs: Channel, rhs: Channel) -> Bool {
    (lhs.name == rhs.name) && (lhs.manager === rhs.manager)
  }
}
