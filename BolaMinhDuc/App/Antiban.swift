// Antiban.swift -- anti-ban da duoc GO BO theo yeu cau (da tim ra nguyen nhan).
// Chi con "Reset Guest": ghi co localConfig.json
// {"testCodePatch":true,"resetGuest":true} de game reset guest account.
import Foundation

enum Antiban {
    /// "Reset Guest": forces the game's own debug config file
    /// `Documents/localConfig.json` with `{"testCodePatch":true,"resetGuest":true}`
    /// into both game containers - exactly what the reference tool does when
    /// its reset button is pressed. The game reads that flag on next launch
    /// and resets its guest account (and bootstraps a fresh local identity).
    /// The user should force-close the game first, then relaunch it.
    @discardableResult
    static func resetGuest() -> Int {
        let fm = FileManager.default
        let json = "{\"testCodePatch\":true,\"resetGuest\":true}"
        var written = 0
        for game in [GameTarget.freefireTH, GameTarget.freefireMAX] {
            guard let container = Installer.containerPath(for: game.rawValue) else { continue }
            let doc = container + "/Documents"
            try? fm.createDirectory(atPath: doc, withIntermediateDirectories: true)
            let path = doc + "/localConfig.json"
            if let data = json.data(using: .utf8),
               (try? data.write(to: URL(fileURLWithPath: path), options: .atomic)) != nil {
                written += 1
            }
        }
        return written
    }
}
