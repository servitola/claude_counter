public import Foundation

/// Where the app leaves the latest snapshot for the widget.
public enum SharedContainer {
    /// Team-prefixed: macOS lets a Developer ID app and its extension share a
    /// group container only under the signing team's ID. Must match both
    /// `.entitlements` files in `App/Resources`.
    public static let appGroup = "NZNV266K59.com.servitola.claudecounter"

    /// The widget's `kind`, which the app names when it asks for a reload.
    public static let widgetKind = "UsageWidget"

    /// `usage.json` in the group container; nil when the signature carries no
    /// matching App Group entitlement.
    public static var snapshotURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("usage.json")
    }
}
