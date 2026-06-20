import SwiftUI
import SceneKit
import SpriteKit
import CoreMotion
import AVFoundation
import UIKit

// MARK: - VR Viewing Mode

enum VRMode: String, CaseIterable, Identifiable {
    case sideBySide, spherical, cinema, void
    var id: String { rawValue }

    var label: String {
        switch self {
        case .sideBySide: return "SBS"
        case .spherical: return "360°"
        case .cinema: return "Cinema"
        case .void: return "Void"
        }
    }

    var icon: String {
        switch self {
        case .sideBySide: return "rectangle.split.2x1"
        case .spherical: return "globe"
        case .cinema: return "tv"
        case .void: return "sparkles"
        }
    }

    var subtitle: String {
        switch self {
        case .sideBySide: return "Fixed screen"
        case .spherical: return "Full spherical"
        case .cinema: return "Virtual room"
        case .void: return "Space IMAX"
        }
    }
}

// MARK: - Scene Manager

class VRSceneManager: ObservableObject {
    @Published var currentMode: VRMode = .sideBySide
    @Published var isPlacingTV = false
    @Published var gazeProgress: CGFloat = 0

    let scene = SCNScene()
    let leftCam = SCNNode()
    let rightCam = SCNNode()
    let cameraBaseNode = SCNNode()
    let worldNode = SCNNode()
    
    let player: AVPlayer
    private let motionMgr = CMMotionManager()
    private let ipd: Float = 0.064
    private var vidMaterial: SCNMaterial?
    var skVideoNode: SKVideoNode?

    private var mainScreenNode: SCNNode?
    private var controlPanelNode: SCNNode?
    private var crosshairNode: SCNNode?
    private var muteLabelNode: SKLabelNode?
    private var scaleLabelNode: SKLabelNode?
    @Published var screenScale: Float = 1.0
    
    private var gazeTargetName: String?
    private var gazeStart: Date?

    init(url: URL) {
        self.player = AVPlayer(url: url)

        scene.background.contents = UIColor.black
        
        scene.rootNode.addChildNode(worldNode)
        scene.rootNode.addChildNode(cameraBaseNode)
        cameraBaseNode.addChildNode(leftCam)
        cameraBaseNode.addChildNode(rightCam)

        let lc = SCNCamera()
        lc.fieldOfView = 90
        lc.zNear = 0.1
        leftCam.camera = lc
        leftCam.position = SCNVector3(-ipd / 2, 0, 0)

        let rc = SCNCamera()
        rc.fieldOfView = 90
        rc.zNear = 0.1
        rightCam.camera = rc
        rightCam.position = SCNVector3(ipd / 2, 0, 0)

        let chGeo = SCNSphere(radius: 0.012)
        let chMat = SCNMaterial()
        chMat.diffuse.contents = UIColor.white.withAlphaComponent(0.5)
        chMat.emission.contents = UIColor.white.withAlphaComponent(0.3)
        chGeo.firstMaterial = chMat
        crosshairNode = SCNNode(geometry: chGeo)
        crosshairNode?.position = SCNVector3(0, 0, -2.5)
        cameraBaseNode.addChildNode(crosshairNode!)

        setupVideoMaterial()
        applyMode(.sideBySide)
        beginMotion()
        
        // Loop video infinitely
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { [weak self] _ in
            self?.player.seek(to: .zero)
            self?.player.play()
        }
        
        // Gaze tick
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.tickGaze()
        }
    }
    
    deinit {
        stopMotion()
        NotificationCenter.default.removeObserver(self)
    }

    private func setupVideoMaterial() {
        let vNode = SKVideoNode(avPlayer: player)
        vNode.size = CGSize(width: 1920, height: 1080)
        vNode.position = CGPoint(x: 960, y: 540)
        vNode.yScale = -1
        let skScene = SKScene(size: CGSize(width: 1920, height: 1080))
        skScene.addChild(vNode)
        self.skVideoNode = vNode

        let mat = SCNMaterial()
        mat.diffuse.contents = skScene
        mat.isDoubleSided = true
        self.vidMaterial = mat
    }

    func applyMode(_ mode: VRMode) {
        currentMode = mode
        worldNode.childNodes.forEach { $0.removeFromParentNode() }
        mainScreenNode = nil
        controlPanelNode = nil
        gazeTargetName = nil
        gazeStart = nil
        gazeProgress = 0
        isPlacingTV = false
        worldNode.eulerAngles = SCNVector3(0, 0, 0)
        
        switch mode {
        case .sideBySide: buildSBS()
        case .spherical: buildSpherical()
        case .cinema: buildCinema()
        case .void: buildVoid()
        }
        
        buildControlPanel()
        
        // Ensure playback continues when switching modes
        if player.timeControlStatus != .playing {
            player.play()
            skVideoNode?.play()
        }
    }

    // MARK: Mode 1 — Side-by-Side

    private func buildSBS() {
        scene.background.contents = UIColor.black
        
        let plane = SCNPlane(width: 4, height: 2.25)
        plane.firstMaterial = vidMaterial
        mainScreenNode = SCNNode(geometry: plane)
        mainScreenNode?.position = SCNVector3(0, 0, -3)
        worldNode.addChildNode(mainScreenNode!)
    }

    // MARK: Mode 2 — 360° / 180° Spherical

    private func buildSpherical() {
        scene.background.contents = UIColor.black
        
        let sphere = SCNSphere(radius: 50)
        sphere.segmentCount = 96
        let mat = SCNMaterial()
        mat.diffuse.contents = vidMaterial?.diffuse.contents
        mat.isDoubleSided = true
        mat.cullMode = .front
        sphere.firstMaterial = mat
        let sphereNode = SCNNode(geometry: sphere)
        worldNode.addChildNode(sphereNode)
        
        let dummy = SCNPlane(width: 0.1, height: 0.1)
        dummy.firstMaterial?.diffuse.contents = UIColor.clear
        mainScreenNode = SCNNode(geometry: dummy)
        mainScreenNode?.position = SCNVector3(0, 0, -3)
        worldNode.addChildNode(mainScreenNode!)
    }

    // MARK: Mode 3 — Cinema

    private func buildCinema() {
        scene.background.contents = UIColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1)

        let room = SCNNode()

        // Create a literal room box
        let roomGeo = SCNBox(width: 12, height: 8, length: 14, chamferRadius: 0)
        let roomMat = SCNMaterial()
        roomMat.diffuse.contents = UIColor(red: 0.12, green: 0.1, blue: 0.15, alpha: 1)
        roomMat.isDoubleSided = true
        roomGeo.firstMaterial = roomMat
        let roomBoxNode = SCNNode(geometry: roomGeo)
        roomBoxNode.position = SCNVector3(0, 1, 0)
        room.addChildNode(roomBoxNode)

        let bedGeo = SCNBox(width: 3.0, height: 0.6, length: 4.0, chamferRadius: 0.1)
        bedGeo.firstMaterial?.diffuse.contents = UIColor(white: 0.2, alpha: 1)
        let bed = SCNNode(geometry: bedGeo)
        bed.position = SCNVector3(0, -1.5, 0)
        room.addChildNode(bed)

        let tvW: CGFloat = 4.5
        let tvGeo = SCNPlane(width: tvW, height: tvW * (9/16))
        tvGeo.firstMaterial = vidMaterial
        mainScreenNode = SCNNode(geometry: tvGeo)
        mainScreenNode?.position = SCNVector3(0, 0.5, -6.5)
        room.addChildNode(mainScreenNode!)

        let light = SCNLight()
        light.type = .ambient
        light.intensity = 300
        let lNode = SCNNode()
        lNode.light = light
        room.addChildNode(lNode)

        let dl = SCNLight()
        dl.type = .omni
        dl.intensity = 800
        let dlN = SCNNode()
        dlN.light = dl
        dlN.position = SCNVector3(0, 3, 0)
        room.addChildNode(dlN)

        worldNode.addChildNode(room)
    }

    // MARK: Mode 4 — Void Theater

    private func buildVoid() {
        scene.background.contents = UIColor.black

        let screenW: CGFloat = 14
        let screen = SCNPlane(width: screenW, height: screenW * (9/16))
        screen.cornerRadius = 0.5
        screen.firstMaterial = vidMaterial
        mainScreenNode = SCNNode(geometry: screen)
        mainScreenNode?.position = SCNVector3(0, 0, -8)
        worldNode.addChildNode(mainScreenNode!)

        let stars = SCNParticleSystem()
        stars.particleColor = .white
        stars.particleSize = 0.04
        stars.birthRate = 80
        stars.particleLifeSpan = 15
        stars.emissionDuration = 0
        stars.emitterShape = SCNSphere(radius: 40)
        stars.birthLocation = .surface
        stars.particleVelocity = 0
        stars.isAffectedByGravity = false
        stars.blendMode = .additive
        let starsN = SCNNode()
        starsN.addParticleSystem(stars)
        worldNode.addChildNode(starsN)
    }
    
    // MARK: Control Panel
    private func buildControlPanel() {
        let panel = SCNNode()
        let row1 = ["Pause", "Resume", "Mute", "-", "1.0x", "+", "Move", "Reset"]
        let row2 = ["SBS", "360", "Cinema", "Void"]
        let spacing: Float = 0.15
        
        func createRow(actions: [String], yOffset: Float, btnWidth: Float) {
            for (i, action) in actions.enumerated() {
                let btnGeo = SCNPlane(width: CGFloat(btnWidth), height: 0.25)
                btnGeo.cornerRadius = 0.05
                
                let sceneWidth = CGFloat(btnWidth * 250)
                let skScene = SKScene(size: CGSize(width: sceneWidth, height: 60))
                skScene.backgroundColor = UIColor(white: 0.2, alpha: 0.9)
                
                let labelText: String
                if action == "Mute" { labelText = player.isMuted ? "Unmute" : "Mute" }
                else if action == "1.0x" { labelText = String(format: "%.1fx", screenScale) }
                else { labelText = action }
                
                let label = SKLabelNode(text: labelText)
                label.fontName = "HelveticaNeue-Bold"
                label.fontSize = 24
                label.fontColor = .white
                label.verticalAlignmentMode = .center
                label.horizontalAlignmentMode = .center
                label.position = CGPoint(x: sceneWidth / 2, y: 30)
                label.yScale = -1 // Fix upside down text
                skScene.addChild(label)
                
                if action == "Mute" { self.muteLabelNode = label }
                if action == "1.0x" { self.scaleLabelNode = label }
                
                let mat = SCNMaterial()
                mat.diffuse.contents = skScene
                mat.isDoubleSided = true
                btnGeo.firstMaterial = mat
                
                let btn = SCNNode(geometry: btnGeo)
                btn.name = "btn_\(action)"
                
                let totalWidth = Float(actions.count) * btnWidth + Float(actions.count - 1) * spacing
                let xPos = Float(i) * (btnWidth + spacing) - totalWidth / 2.0 + btnWidth / 2.0
                btn.position = SCNVector3(xPos, yOffset, 0)
                panel.addChildNode(btn)
            }
        }
        
        createRow(actions: row1, yOffset: 0, btnWidth: 0.6)
        createRow(actions: row2, yOffset: -0.35, btnWidth: 0.8)
        
        controlPanelNode = panel
        if let ms = mainScreenNode {
            let h = Float((ms.geometry as? SCNPlane)?.height ?? 2.0)
            panel.position = SCNVector3(0, -h/2 - 0.4, 0.05)
            ms.addChildNode(panel)
        }
    }

    // MARK: Gaze Interaction

    @objc private func tickGaze() {
        let p1 = cameraBaseNode.presentation.worldPosition
        let fwd = cameraBaseNode.presentation.worldFront
        let p2 = SCNVector3(p1.x + fwd.x * 50, p1.y + fwd.y * 50, p1.z + fwd.z * 50)

        var hitPoint = SCNVector3(0,0,0)
        var currentTarget: String? = nil

        if isPlacingTV {
            currentTarget = "moving_target"
            hitPoint = SCNVector3(p1.x + fwd.x * 5, p1.y + fwd.y * 5, p1.z + fwd.z * 5)
        } else {
            let hits = scene.rootNode.hitTestWithSegment(from: p1, to: p2, options: nil)
            if let hit = hits.first, let name = hit.node.name, name.starts(with: "btn_") {
                currentTarget = name
                hitPoint = hit.worldCoordinates
            }
        }

        if currentTarget != gazeTargetName {
            gazeTargetName = currentTarget
            gazeStart = Date()
            crosshairNode?.geometry?.firstMaterial?.diffuse.contents = UIColor.white.withAlphaComponent(0.5)
            DispatchQueue.main.async { self.gazeProgress = 0 }
        }

        if let target = gazeTargetName, let start = gazeStart {
            let elapsed = Date().timeIntervalSince(start)
            let threshold: TimeInterval = 2.5
            
            DispatchQueue.main.async { self.gazeProgress = CGFloat(min(1.0, elapsed / threshold)) }
            
            if elapsed >= threshold {
                if isPlacingTV {
                    let front = cameraBaseNode.presentation.worldFront
                    let pitch = asin(front.y)
                    let yaw = atan2(-front.x, -front.z)
                    
                    SCNTransaction.begin()
                    SCNTransaction.animationDuration = 0.5
                    worldNode.eulerAngles = SCNVector3(pitch, yaw, 0)
                    SCNTransaction.commit()
                    
                    isPlacingTV = false
                    gazeStart = nil
                    gazeProgress = 0
                } else {
                    executeGazeAction(action: target, point: hitPoint)
                }
                gazeTargetName = nil
                gazeStart = nil
                crosshairNode?.geometry?.firstMaterial?.diffuse.contents = UIColor.white.withAlphaComponent(0.5)
                DispatchQueue.main.async { self.gazeProgress = 0 }
            } else {
                let ratio = CGFloat(elapsed / threshold)
                crosshairNode?.geometry?.firstMaterial?.diffuse.contents = UIColor(red: 1-ratio, green: 1, blue: 1-ratio, alpha: 0.8)
            }
        }
    }
    
    private func executeGazeAction(action: String, point: SCNVector3) {
        switch action {
        case "btn_Pause":
            player.pause()
        case "btn_Resume":
            player.play()
        case "btn_Mute":
            player.isMuted.toggle()
            muteLabelNode?.text = player.isMuted ? "Unmute" : "Mute"
        case "btn_-", "btn_+", "btn_1.0x":
            if currentMode != .spherical {
                if action == "btn_-" && screenScale > 0.5 { screenScale -= 0.1 }
                else if action == "btn_+" && screenScale < 3.0 { screenScale += 0.1 }
                else if action == "btn_1.0x" { screenScale = 1.0 }
                
                scaleLabelNode?.text = String(format: "%.1fx", screenScale)
                mainScreenNode?.scale = SCNVector3(screenScale, screenScale, screenScale)
            }
        case "btn_Move":
            if currentMode != .spherical {
                isPlacingTV = true
            }
        case "btn_Reset":
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.5
            worldNode.eulerAngles = SCNVector3(0, 0, 0)
            SCNTransaction.commit()
        case "btn_SBS":
            applyMode(.sideBySide)
        case "btn_360":
            applyMode(.spherical)
        case "btn_Cinema":
            applyMode(.cinema)
        case "btn_Void":
            applyMode(.void)
        default:
            break
        }
    }

    // MARK: Motion Tracking

    func beginMotion() {
        guard motionMgr.isDeviceMotionAvailable else { return }
        motionMgr.deviceMotionUpdateInterval = 1.0 / 60.0
        motionMgr.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self = self, let m = motion else { return }
            
            let q = m.attitude.quaternion
            let qx = Float(q.x)
            let qy = Float(q.y)
            let qz = Float(q.z)
            let qw = Float(q.w)
            
            self.cameraBaseNode.orientation = SCNQuaternion(x: qy, y: -qx, z: qz, w: qw)
        }
    }

    func stopMotion() {
        motionMgr.stopDeviceMotionUpdates()
    }
}

// MARK: - Dual-Eye Container (UIKit)

class VRContainerView: UIView {
    let leftView = SCNView()
    let rightView = SCNView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black

        for v in [leftView, rightView] {
            v.backgroundColor = .black
            v.antialiasingMode = .multisampling4X
            v.isPlaying = true
            v.autoenablesDefaultLighting = false
            v.allowsCameraControl = false
            addSubview(v)
        }

        // Center divider
        let div = UIView()
        div.backgroundColor = .black
        div.tag = 999
        addSubview(div)
    }

    required init?(coder: NSCoder) { fatalError() }

    func attach(_ mgr: VRSceneManager) {
        leftView.scene = mgr.scene
        rightView.scene = mgr.scene
        leftView.pointOfView = mgr.leftCam
        rightView.pointOfView = mgr.rightCam
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let half = bounds.width / 2
        let dw: CGFloat = 2
        leftView.frame = CGRect(x: 0, y: 0, width: half - dw / 2, height: bounds.height)
        rightView.frame = CGRect(x: half + dw / 2, y: 0, width: half - dw / 2, height: bounds.height)
        viewWithTag(999)?.frame = CGRect(x: half - dw / 2, y: 0, width: dw, height: bounds.height)
    }
}

// MARK: - UIViewRepresentable Bridge

struct VRSceneRepresentable: UIViewRepresentable {
    let manager: VRSceneManager

    func makeUIView(context: Context) -> VRContainerView {
        let v = VRContainerView()
        v.attach(manager)
        return v
    }

    func updateUIView(_ uiView: VRContainerView, context: Context) {
        uiView.leftView.pointOfView = manager.leftCam
        uiView.rightView.pointOfView = manager.rightCam
    }
}

// MARK: - Mode Selector Button

struct VRModeButton: View {
    let mode: VRMode
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: mode.icon)
                    .font(.system(size: 18))
                Text(mode.label)
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundColor(isActive ? .cyan : .white.opacity(0.8))
            .frame(width: 58, height: 48)
            .background(isActive ? Color.white.opacity(0.12) : Color.clear)
            .cornerRadius(10)
        }
    }
}

// MARK: - VR Player View

struct VRPlayerView: View {
    let url: URL
    let title: String
    @StateObject private var mgr: VRSceneManager
    @Environment(\.presentationMode) var presentationMode
    @State private var showUI = true

    init(url: URL, title: String) {
        self.url = url
        self.title = title
        self._mgr = StateObject(wrappedValue: VRSceneManager(url: url))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            sceneLayer
            if showUI { overlayLayer }
            if mgr.isPlacingTV { placingHint }
        }
        .statusBar(hidden: true)
        .onTapGesture { withAnimation { showUI.toggle() } }
        .onAppear {
            mgr.player.play()
            mgr.skVideoNode?.play()
            UIApplication.shared.isIdleTimerDisabled = true
            
            // Force Landscape Orientation
            if #available(iOS 16.0, *) {
                guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
                windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
            }
            UIDevice.current.setValue(UIInterfaceOrientation.landscapeRight.rawValue, forKey: "orientation")
            UIViewController.attemptRotationToDeviceOrientation()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                withAnimation { showUI = false }
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            
            // Restore Portrait Orientation
            if #available(iOS 16.0, *) {
                guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
                windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
            }
            UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
            UIViewController.attemptRotationToDeviceOrientation()
            
            mgr.stopMotion()
            mgr.player.pause()
        }
    }

    private var sceneLayer: some View {
        VRSceneRepresentable(manager: mgr)
            .ignoresSafeArea()
    }

    private var overlayLayer: some View {
        VStack {
            topBar
            Spacer()
            gazeBar
            modeBar
        }
        .padding()
        .transition(.opacity)
    }

    private var topBar: some View {
        HStack {
            closeButton
            titleLabel
            Spacer()
            modeLabel
        }
    }

    private var closeButton: some View {
        Button(action: {
            mgr.player.pause()
            presentationMode.wrappedValue.dismiss()
        }) {
            Image(systemName: "xmark.circle.fill")
                .font(.title2)
                .foregroundColor(.white)
                .padding(8)
                .background(Color.black.opacity(0.5))
                .clipShape(Circle())
        }
    }

    private var titleLabel: some View {
        Text(title)
            .font(.caption)
            .foregroundColor(.white)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.5))
            .cornerRadius(8)
    }

    private var modeLabel: some View {
        Text(mgr.currentMode.subtitle)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.purple.opacity(0.6))
            .cornerRadius(12)
    }

    private var gazeBar: some View {
        Group {
            if mgr.gazeProgress > 0 {
                HStack(spacing: 6) {
                    Circle()
                        .fill(mgr.isPlacingTV ? Color.green : Color.cyan)
                        .frame(width: 8, height: 8)
                    Text(mgr.isPlacingTV ? "Look at new spot..." : "Triggering Action...")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(mgr.isPlacingTV ? Color.green.opacity(0.6) : Color.cyan.opacity(0.6))
                            .frame(width: geo.size.width * mgr.gazeProgress)
                    }
                    .frame(height: 6)
                    .background(Color.white.opacity(0.15))
                    .cornerRadius(4)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.6))
                .cornerRadius(12)
            }
        }
    }

    private var modeBar: some View {
        HStack(spacing: 10) {
            ForEach(VRMode.allCases) { mode in
                VRModeButton(mode: mode, isActive: mgr.currentMode == mode) {
                    mgr.applyMode(mode)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.6))
        .cornerRadius(16)
    }

    private var placingHint: some View {
        VStack {
            Spacer()
            Text("📍 Look where you want the screen, hold for 4s")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.green)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.85))
                .cornerRadius(10)
                .padding(.bottom, 80)
        }
        .transition(.opacity)
    }
}
