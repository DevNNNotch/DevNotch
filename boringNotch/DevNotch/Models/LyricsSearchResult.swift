import Foundation

struct LRCLIBSearchResult: Decodable, Equatable {
    let instrumental: Bool
    let plainLyrics: String?
    let syncedLyrics: String?
}
