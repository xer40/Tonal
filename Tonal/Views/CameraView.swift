import SwiftUI
import AVFoundation
import Combine

// MARK: - CameraView

struct CameraView: View {
    var onCapture: ([UIImage]) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = CameraModel()
    @State private var showPermissionAlert = false

    var body: some View {
        ZStack {
            CameraPreviewLayer(session: camera.session)
                .ignoresSafeArea()

            VStack {
                if !camera.capturedImages.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(camera.capturedImages.enumerated()), id: \.offset) { idx, img in
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: img)
                                        .resizable().scaledToFill()
                                        .frame(width: 64, height: 64)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                    Button {
                                        camera.capturedImages.remove(at: idx)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.white)
                                            .background(Circle().fill(Color.black.opacity(0.6)))
                                            .font(.system(size: 18))
                                    }
                                    .offset(x: 6, y: -6)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.top, 60)
                    .transition(.move(edge: .top).combined(with: .opacity))
                } else {
                    Spacer().frame(height: 60)
                }

                Spacer()

                VStack(spacing: 20) {
                    if !camera.capturedImages.isEmpty {
                        Text("\(camera.capturedImages.count) photo\(camera.capturedImages.count == 1 ? "" : "s") added")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.85))
                    }

                    HStack(spacing: 40) {
                        Button {
                            camera.flipCamera()
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath.camera")
                                .font(.system(size: 26))
                                .foregroundStyle(.white)
                                .frame(width: 56, height: 56)
                                .background(.ultraThinMaterial, in: Circle())
                        }

                        Button {
                            camera.capturePhoto()
                        } label: {
                            ZStack {
                                Circle().fill(.white).frame(width: 76, height: 76)
                                Circle().stroke(.white.opacity(0.4), lineWidth: 3).frame(width: 88, height: 88)
                            }
                        }
                        .disabled(camera.capturedImages.count >= 8)

                        Button {
                            onCapture(camera.capturedImages)
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(camera.capturedImages.isEmpty ? .white.opacity(0.3) : .white)
                                .frame(width: 56, height: 56)
                                .background(
                                    camera.capturedImages.isEmpty
                                        ? AnyShapeStyle(.ultraThinMaterial)
                                        : AnyShapeStyle(Color.black.opacity(0.75)),
                                    in: Circle()
                                )
                        }
                        .disabled(camera.capturedImages.isEmpty)
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .overlay(alignment: .topLeading) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(.leading, 16)
            .padding(.top, 8)
        }
        .onAppear { camera.checkPermission { showPermissionAlert = true } }
        .onDisappear { camera.session.stopRunning() }
        .alert("Camera Access Needed", isPresented: $showPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) { dismiss() }
        } message: {
            Text("Please allow camera access in Settings so Tonal can photograph your clothes.")
        }
        .animation(.spring(duration: 0.3), value: camera.capturedImages.count)
    }
}

// MARK: - CameraModel

@MainActor
final class CameraModel: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    @Published var capturedImages: [UIImage] = []

    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private var position: AVCaptureDevice.Position = .back

    func checkPermission(onDenied: @escaping () -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setUp()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted { Task { @MainActor in self?.setUp() } }
                else { Task { @MainActor in onDenied() } }
            }
        default:
            onDenied()
        }
    }

    private func setUp() {
        session.beginConfiguration()
        session.sessionPreset = .photo
        session.inputs.forEach { session.removeInput($0) }

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else { session.commitConfiguration(); return }

        session.addInput(input)
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()

        Task.detached { [weak self] in await self?.session.startRunning() }
    }

    func flipCamera() {
        position = position == .back ? .front : .back
        setUp()
    }

    func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        output.capturePhoto(with: settings, delegate: self)
    }

    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let img = UIImage(data: data) else { return }
        Task { @MainActor in
            self.capturedImages.append(img)
        }
    }
}

// MARK: - CameraPreviewLayer

struct CameraPreviewLayer: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
