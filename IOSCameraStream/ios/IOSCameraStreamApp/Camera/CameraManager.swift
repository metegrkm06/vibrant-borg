import Foundation
import AVFoundation
import UIKit
import Combine

enum CameraPositionType: String, CaseIterable, Identifiable {
    case backWide = "1.0x Wide"
    case backUltraWide = "0.5x Ultra Wide"
    case backTelephoto = "2.0x Telephoto"
    case front = "Front Selfie"

    var id: String { rawValue }
}

enum ResolutionPreset: String, CaseIterable, Identifiable {
    case p1080 = "1080p Full HD"
    case p720 = "720p HD"
    case p480 = "480p VGA"
    case p4k = "4K Ultra HD"

    var id: String { rawValue }

    var avPreset: AVCaptureSession.Preset {
        switch self {
        case .p1080: return .hd1920x1080
        case .p720:  return .hd1280x720
        case .p480:  return .vga640x480
        case .p4k:   return .hd4K3840x2160
        }
    }
}

class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    static let shared = CameraManager()

    let session = AVCaptureSession()
    private var videoOutput = AVCaptureVideoDataOutput()
    private var currentInput: AVCaptureDeviceInput?
    private let sessionQueue = DispatchQueue(label: "com.bonaycamera.sessionQueue", qos: .userInteractive)
    private let outputQueue = DispatchQueue(label: "com.bonaycamera.outputQueue", qos: .userInteractive)

    // Persistent static CIContext and ColorSpace for Zero-Allocation, Ultra-Fast Encoding
    private let ciContext = CIContext(options: [
        .useSoftwareRenderer: false,
        .priorityRequestLow: false
    ])
    private let colorSpace = CGColorSpaceCreateDeviceRGB()

    // Published State for SwiftUI
    @Published var selectedPosition: CameraPositionType = .backWide
    @Published var availableCameras: [CameraPositionType] = [.backWide, .front]
    @Published var currentFPS: Int = 60
    @Published var currentResolution: ResolutionPreset = .p1080
    @Published var currentZoom: CGFloat = 1.0
    @Published var isTorchOn: Bool = false
    @Published var torchLevel: Double = 1.0
    @Published var isMirrored: Bool = false
    @Published var rotationAngle: Int = 0 // 0, 90, 180 (upside down fix), 270
    @Published var isGridVisible: Bool = false
    @Published var isRunning: Bool = false
    @Published var focusPoint: CGPoint? = nil
    @Published var exposureBias: Double = 0.0 // -2.0 to +2.0 EV
    @Published var jpegQuality: Double = 0.65 // 0.4 to 0.9

    // Saved Per-Camera Orientations & Mirrors (remembers rotation per lens)
    @Published var cameraRotations: [CameraPositionType: Int] = [
        .front: 0,
        .backWide: 0,
        .backUltraWide: 0,
        .backTelephoto: 0
    ]
    @Published var cameraMirrors: [CameraPositionType: Bool] = [
        .front: true, // front camera mirrored by default like normal webcam
        .backWide: false,
        .backUltraWide: false,
        .backTelephoto: false
    ]

    // Encoder delegate
    var onFrameEncoded: ((Data, UInt64) -> Void)?

    // Stats
    @Published var outputFPS: Double = 0.0
    @Published var outputBitrateKbps: Double = 0.0
    private var frameCounter: Int = 0
    private var byteCounter: Int = 0
    private var lastStatsTime: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()

    override init() {
        super.init()
        discoverAvailableCameras()
        setupSession()
    }

    // ─── Camera Discovery ──────────────────────────────────────────────────────

    func discoverAvailableCameras() {
        var cams: [CameraPositionType] = []

        // 1. Ultra-Wide (iPhone 11 and newer)
        if AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back) != nil {
            cams.append(.backUltraWide)
        }

        // 2. Wide Angle (iPhone 7 Plus, 11, all iPhones)
        if AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil {
            cams.append(.backWide)
        }

        // 3. Telephoto (iPhone 7 Plus, 11 Pro, etc.)
        if AVCaptureDevice.default(.builtInTelephotoCamera, for: .video, position: .back) != nil {
            cams.append(.backTelephoto)
        }

        // 4. Front Camera
        if AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) != nil {
            cams.append(.front)
        }

        DispatchQueue.main.async {
            self.availableCameras = cams
            if !cams.contains(self.selectedPosition), let first = cams.first {
                self.selectedPosition = first
            }
        }
    }

    private func getDevice(for positionType: CameraPositionType) -> AVCaptureDevice? {
        switch positionType {
        case .backUltraWide:
            return AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        case .backWide:
            return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        case .backTelephoto:
            return AVCaptureDevice.default(.builtInTelephotoCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        case .front:
            return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        }
    }

    // ─── Session Setup ─────────────────────────────────────────────────────────

    private func setupSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.session.beginConfiguration()

            if self.session.canSetSessionPreset(self.currentResolution.avPreset) {
                self.session.sessionPreset = self.currentResolution.avPreset
            }

            guard let device = self.getDevice(for: self.selectedPosition),
                  let input = try? AVCaptureDeviceInput(device: device) else {
                self.session.commitConfiguration()
                return
            }

            if self.session.canAddInput(input) {
                self.session.addInput(input)
                self.currentInput = input
            }

            self.videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
            ]
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            self.videoOutput.setSampleBufferDelegate(self, queue: self.outputQueue)

            if self.session.canAddOutput(self.videoOutput) {
                self.session.addOutput(self.videoOutput)
            }

            self.updateConnectionOrientation()
            self.applyFPS(self.currentFPS, on: device)
            self.session.commitConfiguration()
        }
    }

    func start() {
        sessionQueue.async { [weak self] in
            guard let self = self, !self.session.isRunning else { return }
            self.session.startRunning()
            DispatchQueue.main.async {
                self.isRunning = true
                UIApplication.shared.isIdleTimerDisabled = true
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self = self, self.session.isRunning else { return }
            self.session.stopRunning()
            DispatchQueue.main.async {
                self.isRunning = false
            }
        }
    }

    // ─── Camera Switch & Saved Rotation Memory ─────────────────────────────────

    func switchCamera(to positionType: CameraPositionType) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            guard let newDevice = self.getDevice(for: positionType),
                  let newInput = try? AVCaptureDeviceInput(device: newDevice) else { return }

            // 1. Save current rotation & mirror for previous camera
            let prevPos = self.selectedPosition
            DispatchQueue.main.async {
                self.cameraRotations[prevPos] = self.rotationAngle
                self.cameraMirrors[prevPos] = self.isMirrored
            }

            self.session.beginConfiguration()
            if let oldInput = self.currentInput {
                self.session.removeInput(oldInput)
            }

            if self.session.canAddInput(newInput) {
                self.session.addInput(newInput)
                self.currentInput = newInput
            }

            // 2. Restore saved rotation & mirror for new camera
            let savedRot = self.cameraRotations[positionType] ?? 0
            let savedMirror = self.cameraMirrors[positionType] ?? (positionType == .front)

            DispatchQueue.main.async {
                self.selectedPosition = positionType
                self.rotationAngle = savedRot
                self.isMirrored = savedMirror
                self.currentZoom = 1.0
                self.isTorchOn = false
            }

            self.updateConnectionOrientation(angle: savedRot, mirror: savedMirror)
            self.applyFPS(self.currentFPS, on: newDevice)
            self.session.commitConfiguration()
        }
    }

    func setResolution(_ res: ResolutionPreset) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.session.beginConfiguration()
            if self.session.canSetSessionPreset(res.avPreset) {
                self.session.sessionPreset = res.avPreset
                DispatchQueue.main.async { self.currentResolution = res }
            }
            self.session.commitConfiguration()
        }
    }

    func setFPS(_ fps: Int) {
        sessionQueue.async { [weak self] in
            guard let self = self, let device = self.currentInput?.device else { return }
            self.applyFPS(fps, on: device)
            DispatchQueue.main.async { self.currentFPS = fps }
        }
    }

    private func applyFPS(_ fps: Int, on device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            var selectedRange: AVFrameRateRange?
            for range in device.activeFormat.videoSupportedFrameRateRanges {
                if Double(fps) >= range.minFrameRate && Double(fps) <= range.maxFrameRate {
                    selectedRange = range
                    break
                }
            }

            let targetFPS = selectedRange != nil ? Double(fps) : (device.activeFormat.videoSupportedFrameRateRanges.first?.maxFrameRate ?? 30.0)
            let duration = CMTime(value: 1, timescale: CMTimeScale(targetFPS))
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
            device.unlockForConfiguration()
        } catch {
            print("Failed to set FPS: \(error)")
        }
    }

    func setZoom(_ factor: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self = self, let device = self.currentInput?.device else { return }
            do {
                try device.lockForConfiguration()
                let maxZ = min(device.activeFormat.videoMaxZoomFactor, 10.0)
                let clamped = max(1.0, min(factor, maxZ))
                device.videoZoomFactor = clamped
                device.unlockForConfiguration()
                DispatchQueue.main.async { self.currentZoom = clamped }
            } catch {
                print("Failed to set zoom: \(error)")
            }
        }
    }

    func setZoom(_ factor: Double) {
        setZoom(CGFloat(factor))
    }

    func toggleTorch(on: Bool? = nil, level: Double = 1.0) {
        sessionQueue.async { [weak self] in
            guard let self = self, let device = self.currentInput?.device, device.hasTorch else { return }
            do {
                try device.lockForConfiguration()
                let target = on ?? !device.isTorchActive
                if target {
                    let lvl = max(0.1, min(Float(level), 1.0))
                    try device.setTorchModeOn(level: lvl)
                } else {
                    device.torchMode = .off
                }
                device.unlockForConfiguration()
                DispatchQueue.main.async {
                    self.isTorchOn = target
                    self.torchLevel = level
                }
            } catch {
                print("Failed to toggle torch: \(error)")
            }
        }
    }

    func focus(at point: CGPoint) {
        sessionQueue.async { [weak self] in
            guard let self = self, let device = self.currentInput?.device else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusPointOfInterest = point
                    device.focusMode = .continuousAutoFocus
                }
                if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposurePointOfInterest = point
                    device.exposureMode = .continuousAutoExposure
                }
                device.unlockForConfiguration()
                DispatchQueue.main.async {
                    self.focusPoint = point
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        if self.focusPoint == point { self.focusPoint = nil }
                    }
                }
            } catch {
                print("Failed to focus: \(error)")
            }
        }
    }

    func setExposureBias(_ bias: Double) {
        sessionQueue.async { [weak self] in
            guard let self = self, let device = self.currentInput?.device else { return }
            do {
                try device.lockForConfiguration()
                let clamped = max(Double(device.minExposureTargetBias), min(bias, Double(device.maxExposureTargetBias)))
                device.setExposureTargetBias(Float(clamped), completionHandler: nil)
                device.unlockForConfiguration()
                DispatchQueue.main.async { self.exposureBias = clamped }
            } catch {
                print("Failed to set exposure bias: \(error)")
            }
        }
    }

    func toggleMirror() {
        DispatchQueue.main.async {
            self.isMirrored.toggle()
            self.cameraMirrors[self.selectedPosition] = self.isMirrored
            self.sessionQueue.async { self.updateConnectionOrientation() }
        }
    }

    func cycleRotation() {
        DispatchQueue.main.async {
            self.rotationAngle = (self.rotationAngle + 90) % 360
            self.cameraRotations[self.selectedPosition] = self.rotationAngle
            self.sessionQueue.async { self.updateConnectionOrientation() }
        }
    }

    func resetRotation() {
        DispatchQueue.main.async {
            self.rotationAngle = 0
            self.cameraRotations[self.selectedPosition] = 0
            self.sessionQueue.async { self.updateConnectionOrientation() }
        }
    }

    private func updateConnectionOrientation(angle: Int? = nil, mirror: Bool? = nil) {
        guard let conn = videoOutput.connection(with: .video) else { return }
        let currentAngle = angle ?? rotationAngle
        let currentMirror = mirror ?? isMirrored

        if conn.isVideoOrientationSupported {
            switch currentAngle {
            case 90:  conn.videoOrientation = .landscapeRight
            case 180: conn.videoOrientation = .portraitUpsideDown
            case 270: conn.videoOrientation = .landscapeLeft
            default:  conn.videoOrientation = .portrait
            }
        }
        if conn.isVideoMirroringSupported {
            conn.isVideoMirrored = currentMirror
        }
    }

    // ─── AVCaptureVideoDataOutput Sample Delegate ──────────────────────────────

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Ultra-Fast Zero-Allocation JPEG Encoding via Persistent CIContext
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        guard let jpegData = ciContext.jpegRepresentation(
            of: ciImage,
            colorSpace: colorSpace,
            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: CGFloat(jpegQuality)]
        ) else {
            return
        }

        let tsNs = UInt64(time(nil)) * 1_000_000_000 + UInt64(clock())
        onFrameEncoded?(jpegData, tsNs)

        // Measure output stats
        frameCounter += 1
        byteCounter += jpegData.count
        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - lastStatsTime
        if elapsed >= 0.5 {
            let fps = Double(frameCounter) / elapsed
            let kbps = (Double(byteCounter) * 8.0 / 1024.0) / elapsed
            DispatchQueue.main.async {
                self.outputFPS = fps
                self.outputBitrateKbps = kbps
            }
            frameCounter = 0
            byteCounter = 0
            lastStatsTime = now
        }
    }
}
