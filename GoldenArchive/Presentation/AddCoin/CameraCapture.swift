//
//  CameraCapture.swift
//  GoldenArchive
//
//  Presentation layer — a plain capture camera with a guide for the obverse,
//  reverse or edge, tap-to-focus and a live glare warning. Photos are
//  delivered exactly as the sensor pipeline produced them: no filters.
//

import SwiftUI
import AVFoundation
import UIKit

final class CameraSession: NSObject, ObservableObject {
    let session = AVCaptureSession()

    @Published private(set) var isReady = false
    @Published private(set) var failure: String?
    @Published private(set) var glareFraction: Double = 0
    @Published private(set) var isFocusing = false
    @Published private(set) var isCapturing = false

    var onPhoto: ((Data, String) -> Void)?

    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "app.GoldenArchive.camera")
    private let analysisQueue = DispatchQueue(label: "app.GoldenArchive.camera.analysis")
    private var device: AVCaptureDevice?
    private var focusObservation: NSKeyValueObservation?
    private var lastAnalysis = Date.distantPast
    private var configured = false

    func start() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.configured { self.configure() }
            guard self.configured, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .photo
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input),
              session.canAddOutput(photoOutput)
        else {
            session.commitConfiguration()
            DispatchQueue.main.async { self.failure = "The camera could not be started on this device." }
            return
        }
        session.addInput(input)
        session.addOutput(photoOutput)
        photoOutput.isHighResolutionCaptureEnabled = true

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        videoOutput.setSampleBufferDelegate(self, queue: analysisQueue)
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
        session.commitConfiguration()

        if let connection = photoOutput.connection(with: .video), connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
        if let connection = videoOutput.connection(with: .video), connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }

        self.device = device
        focusObservation = device.observe(\.isAdjustingFocus, options: [.new]) { [weak self] device, _ in
            let focusing = device.isAdjustingFocus
            DispatchQueue.main.async { self?.isFocusing = focusing }
        }
        try? device.lockForConfiguration()
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
        device.unlockForConfiguration()

        configured = true
        DispatchQueue.main.async { self.isReady = true }
    }

    /// `point` is in capture-device coordinates (0...1).
    func focus(at point: CGPoint) {
        sessionQueue.async { [weak self] in
            guard let device = self?.device, (try? device.lockForConfiguration()) != nil else { return }
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = point
                if device.isFocusModeSupported(.autoFocus) { device.focusMode = .autoFocus }
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = point
                if device.isExposureModeSupported(.autoExpose) { device.exposureMode = .autoExpose }
            }
            device.unlockForConfiguration()
        }
    }

    func capture() {
        guard isReady, !isCapturing else { return }
        isCapturing = true
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let settings: AVCapturePhotoSettings
            if self.photoOutput.availablePhotoCodecTypes.contains(.jpeg) {
                settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            } else {
                settings = AVCapturePhotoSettings()
            }
            settings.isHighResolutionPhotoEnabled = true
            if self.photoOutput.supportedFlashModes.contains(.off) { settings.flashMode = .off }
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }
}

extension CameraSession: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = photo.fileDataRepresentation()
        DispatchQueue.main.async {
            self.isCapturing = false
            guard let data else {
                self.failure = "The photo could not be captured. Try again."
                return
            }
            self.onPhoto?(data, "image/jpeg")
        }
    }
}

extension CameraSession: AVCaptureVideoDataOutputSampleBufferDelegate {
    /// Samples the luma plane inside the centre circle for blown highlights.
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = Date()
        guard now.timeIntervalSince(lastAnalysis) > 0.35, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastAnalysis = now
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard CVPixelBufferGetPlaneCount(buffer) > 0, let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return }
        let width = CVPixelBufferGetWidthOfPlane(buffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let pixels = base.assumingMemoryBound(to: UInt8.self)
        let cx = width / 2, cy = height / 2
        let radius = Int(Double(min(width, height)) * 0.38)
        var inside = 0, blown = 0
        var y = cy - radius
        while y < cy + radius {
            var x = cx - radius
            while x < cx + radius {
                let dx = x - cx, dy = y - cy
                if dx * dx + dy * dy <= radius * radius, x >= 0, y >= 0, x < width, y < height {
                    inside += 1
                    if pixels[y * stride + x] >= 250 { blown += 1 }
                }
                x += 6
            }
            y += 6
        }
        let fraction = inside > 0 ? Double(blown) / Double(inside) : 0
        DispatchQueue.main.async { self.glareFraction = fraction }
    }
}

// MARK: - Preview

final class CameraPreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    var onTap: ((CGPoint, CGPoint) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap(_:))))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        let point = recognizer.location(in: self)
        onTap?(point, previewLayer.captureDevicePointConverted(fromLayerPoint: point))
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    var onTap: (CGPoint, CGPoint) -> Void

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.onTap = onTap
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        uiView.onTap = onTap
    }
}

// MARK: - Capture screen

struct CameraCaptureView: View {
    let container: AppContainer
    var side: PhotoSide
    var onUse: (Data, String) -> Void
    var onCancel: () -> Void

    @StateObject private var camera = CameraSession()
    @State private var captured: (data: Data, type: String, image: UIImage, report: PhotoQualityReport?)?
    @State private var focusPoint: CGPoint?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let captured {
                review(captured)
            } else {
                live
            }
        }
        .statusBar(hidden: true)
        .onAppear {
            camera.onPhoto = { data, type in
                guard let image = UIImage(data: data) else { return }
                captured = (data, type, image, container.photoProcessor.analyze(data))
            }
            camera.start()
        }
        .onDisappear { camera.stop() }
    }

    private var live: some View {
        GeometryReader { proxy in
            ZStack {
                CameraPreview(session: camera.session) { layerPoint, devicePoint in
                    focusPoint = layerPoint
                    camera.focus(at: devicePoint)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { focusPoint = nil }
                }
                .ignoresSafeArea()

                CaptureGuide(side: side, size: proxy.size)
                    .allowsHitTesting(false)

                if let focusPoint {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(GAColor.brightCoin, lineWidth: 2)
                        .frame(width: 72, height: 72)
                        .position(focusPoint)
                        .allowsHitTesting(false)
                }

                VStack(spacing: 10) {
                    HStack {
                        Button("Cancel", action: onCancel)
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(minWidth: 44, minHeight: 44)
                        Spacer()
                        Text(side.title.uppercased())
                            .font(.subheadline.weight(.heavy))
                            .tracking(1.2)
                            .foregroundColor(GAColor.gold)
                        Spacer()
                        Color.clear.frame(width: 60, height: 44)
                    }
                    .padding(.horizontal)
                    Text(guideText)
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.black.opacity(0.55)))
                    if camera.glareFraction > 0.03 {
                        Label("Glare detected — tilt the light or the coin", systemImage: "sun.max.fill")
                            .font(.footnote.weight(.bold))
                            .foregroundColor(GAColor.text)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(GAColor.ember))
                            .transition(.opacity)
                    }
                    Spacer()
                    if let failure = camera.failure {
                        Text(failure)
                            .font(.footnote)
                            .foregroundColor(.white)
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.6)))
                    }
                    Text(camera.isFocusing ? "Focusing…" : "Tap to focus")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.85))
                    Button {
                        camera.capture()
                    } label: {
                        ZStack {
                            Circle().strokeBorder(Color.white, lineWidth: 4).frame(width: 78, height: 78)
                            Circle().fill(camera.isCapturing ? GAColor.silver : GAColor.gold).frame(width: 62, height: 62)
                        }
                    }
                    .disabled(!camera.isReady || camera.isCapturing)
                    .accessibilityLabel("Capture \(side.title.lowercased())")
                    .padding(.bottom, 24)
                }
                .padding(.top, 8)
                .animation(.easeInOut(duration: 0.2), value: camera.glareFraction > 0.03)
            }
        }
    }

    private var guideText: String {
        switch side {
        case .edge: return "Hold the coin edge-on inside the band. Plain background, diffuse light."
        default: return "Fill the circle with the coin on a matte, neutral surface."
        }
    }

    private func review(_ shot: (data: Data, type: String, image: UIImage, report: PhotoQualityReport?)) -> some View {
        VStack(spacing: 16) {
            Text("Check the \(side.title.lowercased())")
                .font(GAFont.title(.title3))
                .foregroundColor(.white)
                .padding(.top, 20)
            Image(uiImage: shot.image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: .infinity)
                .accessibilityLabel("Captured photo")
            VStack(alignment: .leading, spacing: 6) {
                if let report = shot.report, !report.notes.isEmpty {
                    ForEach(report.notes, id: \.self) { note in
                        Label(note, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(GAColor.brightCoin)
                    }
                } else if let report = shot.report {
                    Label("\(report.pixelWidth)×\(report.pixelHeight) px · no glare or blur detected", systemImage: "checkmark.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(GAColor.success)
                }
                Text("Saved unfiltered. The original is kept even if you crop later.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.75))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            HStack(spacing: 12) {
                Button("Retake") { captured = nil }
                    .buttonStyle(.ga(.outline))
                Button("Use Photo") { onUse(shot.data, shot.type) }
                    .buttonStyle(.gaPrimary)
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
    }
}

/// Dims everything outside the guide shape.
struct CaptureGuide: View {
    var side: PhotoSide
    var size: CGSize

    var body: some View {
        let guide = guideRect
        ZStack {
            Path { path in
                path.addRect(CGRect(origin: .zero, size: size))
                if side == .edge {
                    path.addRoundedRect(in: guide, cornerSize: CGSize(width: 18, height: 18))
                } else {
                    path.addEllipse(in: guide)
                }
            }
            .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))
            Group {
                if side == .edge {
                    RoundedRectangle(cornerRadius: 18).strokeBorder(GAColor.gold, lineWidth: 3)
                } else {
                    Circle().strokeBorder(GAColor.gold, lineWidth: 3)
                }
            }
            .frame(width: guide.width, height: guide.height)
            .position(x: guide.midX, y: guide.midY)
        }
        .ignoresSafeArea()
    }

    private var guideRect: CGRect {
        let width = size.width * (side == .edge ? 0.86 : 0.78)
        let height = side == .edge ? size.width * 0.28 : width
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2 - 20, width: width, height: height)
    }
}
