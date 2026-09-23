import SwiftUI

// The macOS 27 SDK also declares a State macro whose plugin is absent in CLT.
// Alias the long-standing property-wrapper type explicitly; this still deploys to macOS 14.
typealias ViewState<Value> = SwiftUI.State<Value>
