import SwiftUI

/// A deliberately empty host application.
///
/// A window-drawn capture (`drawHierarchyInKeyWindow: true`) composites over the host
/// application's own window, so the host must put as little on screen as possible. See
/// <doc:VisualEffects> for the full rationale.
@main
struct HostApp: App {
  var body: some Scene {
    WindowGroup { EmptyView() }
  }
}
