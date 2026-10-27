import SwiftUI

/// The macOS 27 SDK declares `@State` as a macro whose plugin ships only with Xcode, so
/// Command Line Tools builds fail on it. This alias points at the underlying property wrapper.
typealias ViewState<Value> = SwiftUI.State<Value>
