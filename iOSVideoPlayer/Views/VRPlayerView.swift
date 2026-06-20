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

    // Core nodes
    let headNode = SCNNode()
    let cameraBaseNode = SCNNode() // To orient the camera base
    let recenterNode = SCNNode() // To apply reset offsets
    
    let player: AVPlayer
    private let motionMgr = CMMotionManager()
    private let ipd: Float = 0.064
    private var vidMaterial: SCNMaterial?
    var skVideoNode: SKVideoNode?

    private var mainScreenNode: SCNNode?
    private var controlPanelNode: SCNNode?
    private var crosshairNode: SCNNode?
    
    private var referenceAttitude: CMAttitude?
    private var gazeTargetName: String?
    private var gazeStart: Date?

    init(url: URL) {
        self.player = AVPlayer(url: url)

        scene.background.contents = UIColor.black
        
        scene.rootNode.addChildNode(recenterNode)
        recenterNode.addChildNode(cameraBaseNode)
        cameraBaseNode.addChildNode(headNode)
        
        // Setup default base orientation
        cameraBaseNode.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)

        let lc = SCNCamera()
        lc.fieldOfView = 90
        lc.zNear = 0.1
        leftCam.camera = lc
        leftCam.position = SCNVector3(-ipd / 2, 0, 0)
        headNode.addChildNode(leftCam)

        let rc = SCNCamera()
        rc.fieldOfView = 90
        rc.zNear = 0.1
        rightCam.camera = rc
        rightCam.position = SCNVector3(ipd / 2, 0, 0)
        headNode.addChildNode(rightCam)

        let chGeo = SCNSphere(radius: 0.012)
        let chMat = SCNMaterial()
        chMat.diffuse.contents = UIColor.white.withAlphaComponent(0.5)
        chMat.emission.contents = UIColor.white.withAlphaComponent(0.3)
        chGeo.firstMaterial = chMat
        crosshairNode = SCNNode(geometry: chGeo)
        crosshairNode?.position = SCNVector3(0, 0, -2.5)
        headNode.addChildNode(crosshairNode!)

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
        isPlacingTV = false
        mainScreenNode?.removeFromParentNode()
        controlPanelNode?.removeFromParentNode()
        gazeTargetName = nil
        
        // Clear environment
        scene.rootNode.childNodes.forEach {
            if $0 != recenterNode && $0 != mainScreenNode && $0 != controlPanelNode {
                $0.removeFromParentNode()
            }
        }

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
        scene.rootNode.addChildNode(mainScreenNode!)
    }

    // MARK: Mode 2 — 360° / 180° Spherical

    private func buildSpherical() {
        scene.background.contents = UIColor.black
        
        let sphere = SCNSphere(radius: 50)
        sphere.segmentCount = 96
        sphere.firstMaterial = vidMaterial
        let sphereNode = SCNNode(geometry: sphere)
        scene.rootNode.addChildNode(sphereNode)
        
        // Dummy screen node for control panel in 360 mode
        mainScreenNode = SCNNode()
        mainScreenNode?.position = SCNVector3(0, 0, -4)
        scene.rootNode.addChildNode(mainScreenNode!)
    }

    // MARK: Mode 3 — Cinema

    private func buildCinema() {
        scene.background.contents = UIColor(red: 0.08, green: 0.06, blue: 0.12, alpha: 1)

        let room = SCNNode()

        let floorGeo = SCNPlane(width: 10, height: 10)
        floorGeo.firstMaterial?.diffuse.contents = UIColor(red: 0.15, green: 0.1, blue: 0.15, alpha: 1)
        let floorNode = SCNNode(geometry: floorGeo)
        floorNode.eulerAngles.x = -Float.pi / 2
        floorNode.position.y = -1.5
        room.addChildNode(floorNode)

        let bedGeo = SCNBox(width: 2, height: 0.4, length: 2.2, chamferRadius: 0.05)
        bedGeo.firstMaterial?.diffuse.contents = UIColor.darkGray
        let bed = SCNNode(geometry: bedGeo)
        bed.position = SCNVector3(0, -1.3, 0)
        room.addChildNode(bed)

        let tvW: CGFloat = 3.0
        let tvGeo = SCNPlane(width: tvW, height: tvW * (9/16))
        tvGeo.firstMaterial = vidMaterial
        mainScreenNode = SCNNode(geometry: tvGeo)
        mainScreenNode?.position = SCNVector3(0, 0.5, -3.5)
        room.addChildNode(mainScreenNode!)

        let light = SCNLight()
        light.type = .ambient
        light.intensity = 200
        let lNode = SCNNode()
        lNode.light = light
        room.addChildNode(lNode)

        let dl = SCNLight()
        dl.type = .directional
        dl.intensity = 500
        let dlN = SCNNode()
        dlN.light = dl
        dlN.eulerAngles = SCNVector3(-Float.pi / 4, Float.pi / 4, 0)
        room.addChildNode(dlN)

        scene.rootNode.addChildNode(room)
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
        scene.rootNode.addChildNode(mainScreenNode!)

        let stars = SCNParticleSystem()
        stars.particleColor = .white
        stars.particleSize = 0.05
        stars.birthRate = 200
        stars.particleLifeSpan = 10
        stars.emissionDuration = 0
        stars.emitterShape = SCNSphere(radius: 30)
        stars.birthLocation = .volume
        stars.particleVelocity = 0
        stars.isAffectedByGravity = false
        stars.blendMode = .additive
        let starsN = SCNNode()
        starsN.addParticleSystem(stars)
        scene.rootNode.addChildNode(starsN)
    }
    
    // MARK: Control Panel
    private func buildControlPanel() {
        let panel = SCNNode()
        let actions = ["Pause", "Resume", "Move", "Reset"]
        let btnWidth: Float = 0.8
        let spacing: Float = 0.2
        
        for (i, action) in actions.enumerated() {
            let btnGeo = SCNPlane(width: CGFloat(btnWidth), height: 0.3)
            btnGeo.cornerRadius = 0.05
            btnGeo.firstMaterial?.diffuse.contents = UIColor.purple.withAlphaComponent(0.8)
            let btn = SCNNode(geometry: btnGeo)
            btn.name = "btn_\(action)"
            
            let textGeo = SCNText(string: action, extrusionDepth: 0.0)
            textGeo.font = UIFont.boldSystemFont(ofSize: 0.15)
            textGeo.firstMaterial?.diffuse.contents = UIColor.white
            textGeo.alignmentMode = CATextLayerAlignmentMode.center.rawValue
            
            let textNode = SCNNode(geometry: textGeo)
            let (min, max) = textNode.boundingBox
            let tw = Float(max.x - min.x)
            let th = Float(max.y - min.y)
            textNode.position = SCNVector3(-tw/2, -th/2, 0.01)
            btn.addChildNode(textNode)
            
            let xPos = Float(i) * (btnWidth + spacing) - Float(actions.count - 1) * (btnWidth + spacing) / 2.0
            btn.position = SCNVector3(xPos, 0, 0)
            panel.addChildNode(btn)
        }
        
        controlPanelNode = panel
        if let ms = mainScreenNode {
            let h = Float((ms.geometry as? SCNPlane)?.height ?? 2.0)
            panel.position = SCNVector3(0, -h/2 - 0.4, 0.05)
            ms.addChildNode(panel)
        }
    }

    // MARK: Gaze Interaction

    @objc private func tickGaze() {
        let p1 = leftCam.worldPosition
        let fwd = headNode.convertVector(SCNVector3(0, 0, -1), to: nil)
        let p2 = SCNVector3(p1.x + fwd.x * 50, p1.y + fwd.y * 50, p1.z + fwd.z * 50)

        var hitPoint = SCNVector3(0,0,0)
        var currentTarget: String? = nil

        if isPlacingTV {
            currentTarget = "moving_target"
            // Place exactly where looking, 5 units away
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
            let threshold: TimeInterval = isPlacingTV ? 4.0 : 2.0
            
            DispatchQueue.main.async { self.gazeProgress = CGFloat(min(1.0, elapsed / threshold)) }
            
            if elapsed >= threshold {
                executeGazeAction(action: target, point: hitPoint)
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
        case "moving_target":
            isPlacingTV = false
            mainScreenNode?.position = point
            // face the user
            let hPos = headNode.worldPosition
            let dx = hPos.x - point.x
            let dz = hPos.z - point.z
            let dy = hPos.y - point.y
            let yaw = atan2(dx, dz)
            let distXZ = sqrt(dx*dx + dz*dz)
            let pitch = atan2(dy, distXZ)
            mainScreenNode?.eulerAngles = SCNVector3(-pitch, yaw, 0)
        case "btn_Pause":
            player.pause()
        case "btn_Resume":
            player.play()
        case "btn_Move":
            if currentMode != .spherical {
                isPlacingTV = true
            }
        case "btn_Reset":
            referenceAttitude = nil
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
            
            // We use attitude copying to prevent mutating the shared reference
            if self.referenceAttitude == nil {
                self.referenceAttitude = m.attitude.copy() as? CMAttitude
            }
            
            if let ref = self.referenceAttitude, let current = m.attitude.copy() as? CMAttitude {
                current.multiply(byInverseOf: ref)
                let q = current.quaternion
                
                // For Landscape Right orientation, we map Device axes to SceneKit Camera axes:
                // Device pitch/yaw/roll mapped to SCNQuaternion
                self.headNode.orientation = SCNQuaternion(Float(-q.y), Float(q.x), Float(q.z), Float(q.w))
            }
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
            
            // Force Landscape Orientation
            if #available(iOS 16.0, *) {
                guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
                windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                withAnimation { showUI = false }
            }
        }
        .onDisappear {
            // Restore Portrait Orientation
            if #available(iOS 16.0, *) {
                guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
                windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
            }
            
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
