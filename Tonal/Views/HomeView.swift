import SwiftUI
import PhotosUI
import CoreLocation
import Combine

struct HomeView: View {
    let googleId: String

    @StateObject private var locationManager = LocationManager()
    @State private var weather: WeatherData?
    @State private var weatherError: String?
    @State private var loadingWeather = false

    @State private var selectedOccasion: Occasion = .casual
    @State private var selectedItems: [PhotosPickerItem] = []
    // Kept separate so re-picking from the library doesn't wipe camera shots
    @State private var libraryImages: [UIImage] = []
    @State private var cameraImages: [UIImage] = []
    private var selectedImages: [UIImage] { libraryImages + cameraImages }

    @State private var analyzing = false
    @State private var analysis: OutfitAnalysis?
    @State private var analysisError: String?
    @State private var showNoClothingAlert = false
    @State private var showResult = false
    @State private var showCamera = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    weatherCard
                    occasionPicker
                    photoPicker
                    cameraButton
                    if !selectedImages.isEmpty {
                        analyzeButton
                    }
                }
                .padding()
            }
            .navigationTitle("Tonal")
            .navigationBarTitleDisplayMode(.large)
            .task { await loadWeather() }
            .sheet(isPresented: $showResult) {
                if let analysis = analysis, let weather = weather {
                    ResultView(
                        analysis: analysis,
                        occasion: selectedOccasion.rawValue,
                        weather: weather,
                        googleId: googleId
                    )
                }
            }
            .alert("No Clothing Detected", isPresented: $showNoClothingAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Tonal couldn't find any clothing in your photos. Try taking clearer photos of the items you want to wear.")
            }
            .alert("Couldn't Pick an Outfit", isPresented: Binding(
                get: { analysisError != nil },
                set: { if !$0 { analysisError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(analysisError ?? "")
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraView { capturedImages in
                    cameraImages += capturedImages
                    showCamera = false
                }
            }
        }
    }

    // MARK: - Camera Button
    var cameraButton: some View {
        Button {
            showCamera = true
        } label: {
            Label("Take Photos", systemImage: "camera")
                .fontWeight(.medium)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Weather Card
    var weatherCard: some View {
        Group {
            if loadingWeather {
                HStack {
                    ProgressView()
                    Text("Getting weather…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            } else if let w = weather {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(weatherEmoji(w.condition))
                            .font(.system(size: 40))
                        VStack(alignment: .leading) {
                            Text("\(w.temperature)°F")
                                .font(.system(size: 32, weight: .bold))
                            Text(w.condition)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Label("\(w.precipitationChance)%", systemImage: "drop.fill")
                                .font(.caption)
                                .foregroundStyle(.blue)
                            Label("\(w.windSpeed) mph", systemImage: "wind")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Label("\(w.humidity)%", systemImage: "humidity.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if w.rainAlert {
                        Label("Rain likely — consider a jacket or umbrella", systemImage: "cloud.rain.fill")
                            .font(.caption)
                            .foregroundStyle(.blue)
                            .padding(.top, 4)
                    }
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            } else if let err = weatherError {
                HStack {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Retry") { Task { await loadWeather() } }
                        .font(.subheadline.weight(.medium))
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    // MARK: - Occasion Picker
    var occasionPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Occasion")
                .font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Occasion.allCases, id: \.self) { occ in
                        Button {
                            selectedOccasion = occ
                        } label: {
                            VStack(spacing: 4) {
                                Text(occ.icon)
                                    .font(.title2)
                                Text(occ.rawValue)
                                    .font(.caption2)
                                    .fontWeight(.medium)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(selectedOccasion == occ ? Color.primary : Color.secondary.opacity(0.1),
                                        in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(selectedOccasion == occ ? Color(UIColor.systemBackground) : .primary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Photo Picker
    var photoPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Clothing Options")
                .font(.headline)

            PhotosPicker(
                selection: $selectedItems,
                maxSelectionCount: 6,
                matching: .images
            ) {
                if selectedImages.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 36))
                            .foregroundStyle(.secondary)
                        Text("Choose from library")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 130)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(selectedImages.indices, id: \.self) { i in
                                Image(uiImage: selectedImages[i])
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 110, height: 140)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            VStack {
                                Image(systemName: "plus")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 80, height: 140)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
            }
            .onChange(of: selectedItems) { _, items in
                Task { await loadImages(from: items) }
            }

            if !selectedImages.isEmpty {
                Button("Clear all photos") {
                    libraryImages = []
                    cameraImages = []
                    selectedItems = []
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Analyze Button
    var analyzeButton: some View {
        Button {
            Task { await analyze() }
        } label: {
            Group {
                if analyzing {
                    HStack(spacing: 10) {
                        ProgressView().tint(.white)
                        Text("Analyzing…")
                    }
                } else {
                    Text("Pick My Outfit")
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.primary, in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(Color(UIColor.systemBackground))
        }
        .disabled(analyzing)
    }

    // MARK: - Actions
    func loadWeather() async {
        loadingWeather = true
        weatherError = nil
        defer { loadingWeather = false }
        do {
            let coords: CLLocationCoordinate2D
            #if targetEnvironment(simulator)
            coords = CLLocationCoordinate2D(latitude: 34.05, longitude: -118.24)
            #else
            coords = try await locationManager.requestLocation()
            #endif
            weather = try await APIService.fetchWeather(lat: coords.latitude, lon: coords.longitude)
        } catch {
            weatherError = locationManager.authorizationStatus == .denied
                ? "Location access is off — enable it in Settings"
                : "Could not load weather"
        }
    }

    func loadImages(from items: [PhotosPickerItem]) async {
        var images: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let img = UIImage(data: data) {
                images.append(img)
            }
        }
        libraryImages = images
    }

    func analyze() async {
        guard let weather = weather else {
            analysisError = "Weather hasn't loaded yet — tap Retry on the weather card first."
            return
        }
        analyzing = true
        analysisError = nil
        defer { analyzing = false }
        do {
            let result = try await APIService.analyzeOutfit(
                googleId: googleId,
                images: selectedImages,
                occasion: selectedOccasion.rawValue,
                weather: weather
            )
            if result.pieces.isEmpty {
                showNoClothingAlert = true
            } else {
                analysis = result
                showResult = true
            }
        } catch {
            analysisError = error.localizedDescription
        }
    }

    func weatherEmoji(_ condition: String) -> String {
        switch condition.lowercased() {
        case let s where s.contains("clear"): return "☀️"
        case let s where s.contains("cloud"): return "⛅"
        case let s where s.contains("fog"): return "🌫️"
        case let s where s.contains("drizzle"): return "🌦️"
        case let s where s.contains("rain"): return "🌧️"
        case let s where s.contains("snow"): return "❄️"
        case let s where s.contains("storm"): return "⛈️"
        default: return "🌤️"
        }
    }
}

// MARK: - Location Manager
class LocationManager: NSObject, CLLocationManagerDelegate, ObservableObject {
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func requestLocation() async throws -> CLLocationCoordinate2D {
        return try await withCheckedThrowingContinuation { cont in
            // Fail any request still in flight so its continuation isn't leaked
            continuation?.resume(throwing: CancellationError())
            self.continuation = cont
            if manager.authorizationStatus == .notDetermined {
                // Location is requested once the user answers the prompt
                manager.requestWhenInUseAuthorization()
            } else {
                manager.requestLocation()
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        guard continuation != nil else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            continuation?.resume(throwing: CLError(.denied))
            continuation = nil
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }
        continuation?.resume(returning: location.coordinate)
        continuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
