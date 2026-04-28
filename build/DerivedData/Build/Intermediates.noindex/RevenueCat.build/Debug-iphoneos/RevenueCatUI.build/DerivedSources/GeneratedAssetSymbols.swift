import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(SwiftUI)
import SwiftUI
#endif
#if canImport(DeveloperToolsSupport)
import DeveloperToolsSupport
#endif

#if SWIFT_PACKAGE
private let resourceBundle = Foundation.Bundle.module
#else
private class ResourceBundleClass {}
private let resourceBundle = Foundation.Bundle(for: ResourceBundleClass.self)
#endif

// MARK: - Color Symbols -

@available(iOS 11.0, macOS 10.13, tvOS 11.0, *)
extension ColorResource {

}

// MARK: - Image Symbols -

@available(iOS 11.0, macOS 10.7, tvOS 11.0, *)
extension ImageResource {

    /// The "android" asset catalog image resource.
    static let android = ImageResource(name: "android", bundle: resourceBundle)

    /// The "apple" asset catalog image resource.
    static let apple = ImageResource(name: "apple", bundle: resourceBundle)

    /// The "attach_money" asset catalog image resource.
    static let attachMoney = ImageResource(name: "attach_money", bundle: resourceBundle)

    /// The "attachment" asset catalog image resource.
    static let attachment = ImageResource(name: "attachment", bundle: resourceBundle)

    /// The "bar_chart" asset catalog image resource.
    static let barChart = ImageResource(name: "bar_chart", bundle: resourceBundle)

    /// The "bookmark" asset catalog image resource.
    static let bookmark = ImageResource(name: "bookmark", bundle: resourceBundle)

    /// The "bookmark_no_fill" asset catalog image resource.
    static let bookmarkNoFill = ImageResource(name: "bookmark_no_fill", bundle: resourceBundle)

    /// The "calendar_today" asset catalog image resource.
    static let calendarToday = ImageResource(name: "calendar_today", bundle: resourceBundle)

    /// The "chat_bubble" asset catalog image resource.
    static let chatBubble = ImageResource(name: "chat_bubble", bundle: resourceBundle)

    /// The "check_circle" asset catalog image resource.
    static let checkCircle = ImageResource(name: "check_circle", bundle: resourceBundle)

    /// The "close" asset catalog image resource.
    static let close = ImageResource(name: "close", bundle: resourceBundle)

    /// The "collapse" asset catalog image resource.
    static let collapse = ImageResource(name: "collapse", bundle: resourceBundle)

    /// The "compare" asset catalog image resource.
    static let compare = ImageResource(name: "compare", bundle: resourceBundle)

    /// The "default-paywall" asset catalog image resource.
    static let defaultPaywall = ImageResource(name: "default-paywall", bundle: resourceBundle)

    /// The "download" asset catalog image resource.
    static let download = ImageResource(name: "download", bundle: resourceBundle)

    /// The "edit" asset catalog image resource.
    static let edit = ImageResource(name: "edit", bundle: resourceBundle)

    /// The "email" asset catalog image resource.
    static let email = ImageResource(name: "email", bundle: resourceBundle)

    /// The "error" asset catalog image resource.
    static let error = ImageResource(name: "error", bundle: resourceBundle)

    /// The "experiments" asset catalog image resource.
    static let experiments = ImageResource(name: "experiments", bundle: resourceBundle)

    /// The "extension" asset catalog image resource.
    static let `extension` = ImageResource(name: "extension", bundle: resourceBundle)

    /// The "file_copy" asset catalog image resource.
    static let fileCopy = ImageResource(name: "file_copy", bundle: resourceBundle)

    /// The "filter_list" asset catalog image resource.
    static let filterList = ImageResource(name: "filter_list", bundle: resourceBundle)

    /// The "folder" asset catalog image resource.
    static let folder = ImageResource(name: "folder", bundle: resourceBundle)

    /// The "globe" asset catalog image resource.
    static let globe = ImageResource(name: "globe", bundle: resourceBundle)

    /// The "help" asset catalog image resource.
    static let help = ImageResource(name: "help", bundle: resourceBundle)

    /// The "insert_drive_file" asset catalog image resource.
    static let insertDriveFile = ImageResource(name: "insert_drive_file", bundle: resourceBundle)

    /// The "key" asset catalog image resource.
    static let key = ImageResource(name: "key", bundle: resourceBundle)

    /// The "launch" asset catalog image resource.
    static let launch = ImageResource(name: "launch", bundle: resourceBundle)

    /// The "layers" asset catalog image resource.
    static let layers = ImageResource(name: "layers", bundle: resourceBundle)

    /// The "line_chart" asset catalog image resource.
    static let lineChart = ImageResource(name: "line_chart", bundle: resourceBundle)

    /// The "lock" asset catalog image resource.
    static let lock = ImageResource(name: "lock", bundle: resourceBundle)

    /// The "notification" asset catalog image resource.
    static let notification = ImageResource(name: "notification", bundle: resourceBundle)

    /// The "person" asset catalog image resource.
    static let person = ImageResource(name: "person", bundle: resourceBundle)

    /// The "phone" asset catalog image resource.
    static let phone = ImageResource(name: "phone", bundle: resourceBundle)

    /// The "play_circle" asset catalog image resource.
    static let playCircle = ImageResource(name: "play_circle", bundle: resourceBundle)

    /// The "plus" asset catalog image resource.
    static let plus = ImageResource(name: "plus", bundle: resourceBundle)

    /// The "remove_red_eye" asset catalog image resource.
    static let removeRedEye = ImageResource(name: "remove_red_eye", bundle: resourceBundle)

    /// The "search" asset catalog image resource.
    static let search = ImageResource(name: "search", bundle: resourceBundle)

    /// The "share" asset catalog image resource.
    static let share = ImageResource(name: "share", bundle: resourceBundle)

    /// The "smartphone" asset catalog image resource.
    static let smartphone = ImageResource(name: "smartphone", bundle: resourceBundle)

    /// The "stacked_bar" asset catalog image resource.
    static let stackedBar = ImageResource(name: "stacked_bar", bundle: resourceBundle)

    /// The "stars" asset catalog image resource.
    static let stars = ImageResource(name: "stars", bundle: resourceBundle)

    /// The "subtract" asset catalog image resource.
    static let subtract = ImageResource(name: "subtract", bundle: resourceBundle)

    /// The "tick" asset catalog image resource.
    static let tick = ImageResource(name: "tick", bundle: resourceBundle)

    /// The "transfer" asset catalog image resource.
    static let transfer = ImageResource(name: "transfer", bundle: resourceBundle)

    /// The "two_way_arrows" asset catalog image resource.
    static let twoWayArrows = ImageResource(name: "two_way_arrows", bundle: resourceBundle)

    /// The "warning" asset catalog image resource.
    static let warning = ImageResource(name: "warning", bundle: resourceBundle)

}

// MARK: - Backwards Deployment Support -

/// A color resource.
struct ColorResource: Swift.Hashable, Swift.Sendable {

    /// An asset catalog color resource name.
    fileprivate let name: Swift.String

    /// An asset catalog color resource bundle.
    fileprivate let bundle: Foundation.Bundle

    /// Initialize a `ColorResource` with `name` and `bundle`.
    init(name: Swift.String, bundle: Foundation.Bundle) {
        self.name = name
        self.bundle = bundle
    }

}

/// An image resource.
struct ImageResource: Swift.Hashable, Swift.Sendable {

    /// An asset catalog image resource name.
    fileprivate let name: Swift.String

    /// An asset catalog image resource bundle.
    fileprivate let bundle: Foundation.Bundle

    /// Initialize an `ImageResource` with `name` and `bundle`.
    init(name: Swift.String, bundle: Foundation.Bundle) {
        self.name = name
        self.bundle = bundle
    }

}

#if canImport(AppKit)
@available(macOS 10.13, *)
@available(macCatalyst, unavailable)
extension AppKit.NSColor {

    /// Initialize a `NSColor` with a color resource.
    convenience init(resource: ColorResource) {
        self.init(named: NSColor.Name(resource.name), bundle: resource.bundle)!
    }

}

protocol _ACResourceInitProtocol {}
extension AppKit.NSImage: _ACResourceInitProtocol {}

@available(macOS 10.7, *)
@available(macCatalyst, unavailable)
extension _ACResourceInitProtocol {

    /// Initialize a `NSImage` with an image resource.
    init(resource: ImageResource) {
        self = resource.bundle.image(forResource: NSImage.Name(resource.name))! as! Self
    }

}
#endif

#if canImport(UIKit)
@available(iOS 11.0, tvOS 11.0, *)
@available(watchOS, unavailable)
extension UIKit.UIColor {

    /// Initialize a `UIColor` with a color resource.
    convenience init(resource: ColorResource) {
#if !os(watchOS)
        self.init(named: resource.name, in: resource.bundle, compatibleWith: nil)!
#else
        self.init()
#endif
    }

}

@available(iOS 11.0, tvOS 11.0, *)
@available(watchOS, unavailable)
extension UIKit.UIImage {

    /// Initialize a `UIImage` with an image resource.
    convenience init(resource: ImageResource) {
#if !os(watchOS)
        self.init(named: resource.name, in: resource.bundle, compatibleWith: nil)!
#else
        self.init()
#endif
    }

}
#endif

#if canImport(SwiftUI)
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension SwiftUI.Color {

    /// Initialize a `Color` with a color resource.
    init(_ resource: ColorResource) {
        self.init(resource.name, bundle: resource.bundle)
    }

}

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension SwiftUI.Image {

    /// Initialize an `Image` with an image resource.
    init(_ resource: ImageResource) {
        self.init(resource.name, bundle: resource.bundle)
    }

}
#endif