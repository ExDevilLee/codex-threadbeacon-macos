import Foundation

enum ProjectLinks {
    static let repository = URL(string: "https://github.com/ExDevilLee/codex-threadbeacon-macos")!
    static let releases = repository.appending(path: "releases")
    static let privacy = repository.appending(path: "blob/main/PRIVACY.md")
    static let license = repository.appending(path: "blob/main/LICENSE")
    static let sponsor = repository.appending(path: "blob/main/SPONSOR.md")
}
