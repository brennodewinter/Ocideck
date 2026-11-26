// NOTICE: This file was added by the OciDeck project.
// Original package: desktop_multi_window (c) 2021 Mixin, Apache License 2.0
// (see ../../../../../LICENSE). Modification notice per Apache-2.0 section
// 4(b); see ../../../../../MODIFICATIONS.md.

import AppKit

/// Kiest de veilige vensterstijl voor een schermvullend beamervenster.
///
/// AppKit breekt het proces af wanneer `.fullScreen` buiten zijn eigen
/// overgang wordt verwijderd. Alle andere vensters worden randloos gemaakt.
public func coverScreenStyleMask(from current: NSWindow.StyleMask) -> NSWindow.StyleMask {
    current.contains(.fullScreen) ? current : [.borderless]
}

/// Resolves identities within one live enumeration; stale indices never apply.
public func audienceDisplayIndex(_ identities: [String], presenter: String, target: String) -> Int? {
    guard identities.count >= 2, !presenter.isEmpty, !target.isEmpty,
        presenter != target, Set(identities).count == identities.count,
        identities.contains(presenter)
    else { return nil }
    return identities.firstIndex(of: target)
}
