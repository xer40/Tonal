import Foundation
import UIKit

enum APIError: LocalizedError {
    case server(String)
    case badStatus(Int)

    var errorDescription: String? {
        switch self {
        case .server(let message): return message
        case .badStatus(let code): return "Server error (\(code)) — try again."
        }
    }
}

class APIService {
    // Simulator can use localhost; a real device needs your Mac's LAN IP
    // (e.g. "http://192.168.1.100:3000") or the deployed backend URL.
    static let baseURL = "http://192.168.1.170:3000"

    // MARK: - Request Helpers
    private static func get(_ path: String) async throws -> Data {
        try await send(URLRequest(url: URL(string: "\(baseURL)\(path)")!))
    }

    private static func send(_ path: String, method: String, body: [String: Any]? = nil) async throws -> Data {
        var request = URLRequest(url: URL(string: "\(baseURL)\(path)")!)
        request.httpMethod = method
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return try await send(request)
    }

    // Throws the backend's { error } message on non-2xx responses
    private static func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            struct ErrorBody: Codable { let error: String }
            if let body = try? JSONDecoder().decode(ErrorBody.self, from: data) {
                throw APIError.server(body.error)
            }
            throw APIError.badStatus(http.statusCode)
        }
        return data
    }

    // Snapshot of current conditions stored alongside saved combos and logs
    private static func weatherSummary(_ weather: WeatherData) -> [String: Any] {
        [
            "temperature": weather.temperature,
            "feelsLike": weather.feelsLike,
            "condition": weather.condition,
            "precipitationChance": weather.precipitationChance
        ]
    }

    // MARK: - Weather
    static func fetchWeather(lat: Double, lon: Double) async throws -> WeatherData {
        let data = try await get("/api/weather?lat=\(lat)&lon=\(lon)")
        return try JSONDecoder().decode(WeatherData.self, from: data)
    }

    // MARK: - Analyze Outfit
    static func analyzeOutfit(
        googleId: String,
        images: [UIImage],
        occasion: String,
        weather: WeatherData
    ) async throws -> OutfitAnalysis {
        let imagePayloads = images.compactMap { img -> [String: String]? in
            guard let data = img.jpegData(compressionQuality: 0.7) else { return nil }
            return ["base64": data.base64EncodedString(), "mimeType": "image/jpeg"]
        }

        let body: [String: Any] = [
            "images": imagePayloads,
            "occasion": occasion,
            "temp": weather.temperature,
            "feelsLike": weather.feelsLike,
            "condition": weather.condition,
            "precipChance": weather.precipitationChance,
            "humidity": weather.humidity,
            "windSpeed": weather.windSpeed
        ]

        let data = try await send("/api/analyze/\(googleId)", method: "POST", body: body)
        struct AnalysisResponse: Codable { let analysis: OutfitAnalysis }
        return try JSONDecoder().decode(AnalysisResponse.self, from: data).analysis
    }

    // MARK: - Saved Combos
    static func fetchCombos(googleId: String) async throws -> [SavedCombo] {
        let data = try await get("/api/combos/\(googleId)")
        struct Response: Codable { let combos: [SavedCombo] }
        return try JSONDecoder().decode(Response.self, from: data).combos
    }

    static func saveCombo(googleId: String, analysis: OutfitAnalysis, occasion: String, weather: WeatherData, notes: String = "") async throws -> SavedCombo {
        let body: [String: Any] = [
            "pieces": analysis.pieces,
            "occasion": occasion,
            "weather": weatherSummary(weather),
            "verdict": analysis.verdict,
            "colorAnalysis": analysis.colorAnalysis,
            "rating": analysis.rating,
            "notes": notes
        ]
        let data = try await send("/api/combos/\(googleId)", method: "POST", body: body)
        struct Response: Codable { let combo: SavedCombo }
        return try JSONDecoder().decode(Response.self, from: data).combo
    }

    static func deleteCombo(googleId: String, comboId: String) async throws {
        _ = try await send("/api/combos/\(googleId)/\(comboId)", method: "DELETE")
    }

    // MARK: - Outfit Log
    static func fetchLogs(googleId: String) async throws -> [OutfitLog] {
        let data = try await get("/api/logs/\(googleId)")
        struct Response: Codable { let logs: [OutfitLog] }
        return try JSONDecoder().decode(Response.self, from: data).logs
    }

    static func logOutfit(googleId: String, analysis: OutfitAnalysis, occasion: String, weather: WeatherData, notes: String = "") async throws {
        let body: [String: Any] = [
            "pieces": analysis.pieces,
            "occasion": occasion,
            "weather": weatherSummary(weather),
            "notes": notes
        ]
        _ = try await send("/api/logs/\(googleId)", method: "POST", body: body)
    }

    // MARK: - Closet
    static func fetchCloset(googleId: String) async throws -> [ClosetItem] {
        let data = try await get("/api/closet/\(googleId)")
        struct Response: Codable { let items: [ClosetItem] }
        return try JSONDecoder().decode(Response.self, from: data).items
    }

    static func addClosetItem(googleId: String, name: String, type: String, color: String, description: String) async throws -> ClosetItem {
        let body: [String: Any] = ["name": name, "type": type, "color": color, "description": description]
        let data = try await send("/api/closet/\(googleId)", method: "POST", body: body)
        struct Response: Codable { let item: ClosetItem }
        return try JSONDecoder().decode(Response.self, from: data).item
    }

    static func deleteClosetItem(googleId: String, itemId: String) async throws {
        _ = try await send("/api/closet/\(googleId)/\(itemId)", method: "DELETE")
    }
}
