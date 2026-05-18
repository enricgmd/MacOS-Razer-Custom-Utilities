import AppKit
import Foundation

public enum AppAssets {
    public static func image(named name: String) -> NSImage? {
        let candidateURLs = [
            Bundle.main.resourceURL?.appendingPathComponent("graphics").appendingPathComponent(name),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("graphics")
                .appendingPathComponent(name)
        ].compactMap { $0 }

        for url in candidateURLs {
            if let image = NSImage(contentsOf: url) {
                return image
            }
        }

        return nil
    }
}
