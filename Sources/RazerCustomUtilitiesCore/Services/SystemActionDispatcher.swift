import AppKit
import Foundation

enum SystemActionDispatcher {
    static func perform(_ action: SystemActionKind) {
        switch action {
        case .createFolder:
            runAppleScript("""
            tell application "Finder"
                activate
                try
                    make new folder at insertion location
                on error
                    make new folder at desktop
                end try
            end tell
            """)
        case .launchPad:
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Launchpad.app"))
        case .search:
            ShortcutDispatcher.post(keyCode: 49, flags: [.maskCommand])
        case .forceQuit:
            openAppleMenuItem(
                names: [
                    "Force Quit…",
                    "Force Quit...",
                    "Forzar salida…",
                    "Forzar salida...",
                    "Forzar salida de aplicaciones…",
                    "Forzar salida de aplicaciones..."
                ],
                fallback: """
                tell application "System Events" to key code 53 using {command down, option down}
                """
            )
        case .sleep:
            runProcess("/usr/bin/pmset", arguments: ["sleepnow"])
        case .shutdown:
            runAppleScript("""
            tell application "System Events" to shut down
            """)
        }
    }

    private static func openAppleMenuItem(names: [String], fallback: String?) {
        let quotedNames = names
            .map { "\"\($0.replacingOccurrences(of: "\"", with: "\\\""))\"" }
            .joined(separator: ", ")

        let script = """
        set candidateNames to {\(quotedNames)}
        tell application "System Events"
            set targetProcess to first process whose frontmost is true
            tell targetProcess
                tell menu bar item 1 of menu bar 1
                    click
                    repeat with candidateName in candidateNames
                        try
                            click menu item (candidateName as text) of menu 1
                            return
                        end try
                    end repeat
                end tell
            end tell
        end tell
        \(fallback ?? "")
        """

        runAppleScript(script)
    }

    private static func runAppleScript(_ source: String) {
        runProcess("/usr/bin/osascript", arguments: ["-e", source])
    }

    private static func runProcess(_ path: String, arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        try? process.run()
    }
}
