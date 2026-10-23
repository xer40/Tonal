import Foundation

// MARK: - Weather
struct WeatherData: Codable {
    let temperature: Int
    let feelsLike: Int
    let precipitationChance: Int
    let windSpeed: Int
    let humidity: Int
    let condition: String
    let rainAlert: Bool
    let unit: String
    let hourly: [HourlyWeather]
    let daily: [DailyWeather]
}

struct HourlyWeather: Codable, Identifiable {
    var id: String { time }
    let time: String
    let hour: Int
    let temperature: Int
    let precipitationChance: Int
    let condition: String
}

struct DailyWeather: Codable, Identifiable {
    var id: String { date }
    let date: String
    let high: Int
    let low: Int
    let condition: String
    let precipitationChance: Int
}

// MARK: - Analysis
struct OutfitAnalysis: Codable {
    let pieces: [String]
    let rating: Int
    let verdict: String
    let colorAnalysis: String
    let weatherCheck: String
    let occasionFit: String
    let elevationTip: String
    let tips: [String]
    let rainAlert: Bool
}

// MARK: - Saved Combo
struct SavedCombo: Codable, Identifiable {
    let id: String
    let date: String
    let pieces: [String]
    let occasion: String
    let verdict: String
    let colorAnalysis: String
    let rating: Int?
    let notes: String

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case date, pieces, occasion, verdict, colorAnalysis, rating, notes
    }
}

// MARK: - Outfit Log
struct OutfitLog: Codable, Identifiable {
    let id: String
    let date: String
    let pieces: [String]
    let occasion: String
    let notes: String

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case date, pieces, occasion, notes
    }
}

// MARK: - Closet Item
struct ClosetItem: Codable, Identifiable {
    let id: String
    let name: String
    let type: String?
    let color: String?
    let description: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name, type, color, description
    }
}

// MARK: - Occasions
enum Occasion: String, CaseIterable {
    case casual = "Casual"
    case work = "Work"
    case goingOut = "Going Out"
    case formal = "Formal"
    case gym = "Gym"
    case dateNight = "Date Night"
    case beach = "Beach"
    case travel = "Travel"

    var icon: String {
        switch self {
        case .casual: return "🧢"
        case .work: return "💼"
        case .goingOut: return "✨"
        case .formal: return "🎩"
        case .gym: return "🏋️"
        case .dateNight: return "🌹"
        case .beach: return "🏖️"
        case .travel: return "✈️"
        }
    }
}
