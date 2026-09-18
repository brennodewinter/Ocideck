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
