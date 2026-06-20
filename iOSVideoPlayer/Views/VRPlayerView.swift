import SwiftUI
import SceneKit
import SpriteKit
import CoreMotion
import AVFoundation
import UIKit

// MARK: - VR Viewing Mode

enum VRMode: Int, CaseIterable, Identifiable {
    case sideBySide = 0
    case spherical = 1
    case cinema = 2
    case voidTheater = 3

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .sideBySide: return "SBS"
        case .spherical: return "360°"
        case .cinema: return "Cinema"
        case .voidTheater: return "Void"
        }
    }

    var icon: String {
        switch self {
        case .sideBySide: return "rectangle.split.2x1"
        case .spherical: return "globe"
        case .cinema: return "tv"
        case .voidTheater: return "sparkles"
        }
    }

    var subtitle: String {
        switch self {
        case .sideBySide: return "Cardboard"
        case .spherical: return "360° / 180°"
        case .cinema: return "Room + TV"
        case .voidTheater: return "Space IMAX"
        }
    }
}

// MARK: - VR Scene Manager

class VRSceneManager: ObservableObject {
    let player: AVPlayer
    let scene = SCNScene()
    let headNode = SCNNode()
    let leftCam = SCNNode()
    let rightCam = SCNNode()

    @Published var currentMode: VRMode = .sideBySide
    @Published var gazeProgress: CGFloat = 0
    @Published var isPlacingTV = false

    private let motionMgr = CMMotionManager()
    private let ipd: Float = 0.064
    private var vidMaterial: SCNMaterial?
    var skVideoNode: SKVideoNode?

    // Cinema-specific
    private var tvNode: SCNNode?
    private var btnNode: SCNNode?
    private var crosshairNode: SCNNode?
    private var gazeTimer: Timer?
    private var gazeStart: Date?
    private var placeStart: Date?

    init(url: URL) {
        self.player = AVPlayer(url: url)
        buildCameras()
        buildVideoMaterial()
        applyMode(.sideBySide)
        beginMotion()
    }

    deinit {
        motionMgr.stopDeviceMotionUpdates()
        gazeTimer?.invalidate()
        player.pause()
    }

    // MARK: Cameras

    private func buildCameras() {
        let makeCamera: () -> SCNCamera = {
            let c = SCNCamera()
            c.fieldOfView = 90
            c.zNear = 0.01
            c.zFar = 200
            return c
        }
        leftCam.camera = makeCamera()
        leftCam.position = SCNVector3(-ipd / 2, 0, 0)
        rightCam.camera = makeCamera()
        rightCam.position = SCNVector3(ipd / 2, 0, 0)

        headNode.addChildNode(leftCam)
        headNode.addChildNode(rightCam)
        scene.rootNode.addChildNode(headNode)
    }

    // MARK: Video Material

    private func buildVideoMaterial() {
        let vNode = SKVideoNode(avPlayer: player)
        vNode.size = CGSize(width: 1920, height: 1080)
        vNode.position = CGPoint(x: 960, y: 540)
        vNode.yScale = -1

        let skScene = SKScene(size: CGSize(width: 1920, height: 1080))
        skScene.scaleMode = .aspectFit
        skScene.addChild(vNode)

        let mat = SCNMaterial()
        mat.diffuse.contents = skScene
        mat.isDoubleSided = true
        mat.lightingModel = .constant
        self.vidMaterial = mat
        self.skVideoNode = vNode
    }

    // MARK: Scene Switching

    func applyMode(_ mode: VRMode) {
        // Clear everything except headNode
        for child in scene.rootNode.childNodes where child !== headNode {
            child.removeFromParentNode()
        }
        // Remove cinema crosshair from headNode
        crosshairNode?.removeFromParentNode()
        crosshairNode = nil
        tvNode = nil
        btnNode = nil
        gazeTimer?.invalidate()
        gazeTimer = nil
        gazeStart = nil
        placeStart = nil
        gazeProgress = 0
        isPlacingTV = false

        switch mode {
        case .sideBySide: buildSBS()
        case .spherical:  buildSpherical()
        case .cinema:     buildCinema()
        case .voidTheater: buildVoid()
        }

        currentMode = mode
        scene.background.contents = UIColor.black
    }

    // MARK: Mode 1 — Side-by-Side

    private func buildSBS() {
        headNode.position = SCNVector3(0, 0, 0)

        let plane = SCNPlane(width: 4, height: 2.25)
        plane.firstMaterial = vidMaterial
        let node = SCNNode(geometry: plane)
        node.position = SCNVector3(0, 0, -5)
        scene.rootNode.addChildNode(node)
    }

    // MARK: Mode 2 — 360° / 180° Spherical

    private func buildSpherical() {
        headNode.position = SCNVector3(0, 0, 0)

        let sphere = SCNSphere(radius: 50)
        sphere.segmentCount = 96
        sphere.firstMaterial = vidMaterial
        let node = SCNNode(geometry: sphere)
        node.scale = SCNVector3(-1, 1, 1)
        scene.rootNode.addChildNode(node)
    }

    // MARK: Mode 3 — Virtual Cinema

    private func buildCinema() {
        headNode.position = SCNVector3(0, 1.2, 0)

        let darkWall = UIColor(red: 0.08, green: 0.06, blue: 0.12, alpha: 1)
        let darkFloor = UIColor(red: 0.12, green: 0.10, blue: 0.08, alpha: 1)

        func wallMat(_ color: UIColor) -> SCNMaterial {
            let m = SCNMaterial()
            m.diffuse.contents = color
            m.lightingModel = .constant
            return m
        }

        // Floor
        let floorGeo = SCNPlane(width: 8, height: 7)
        floorGeo.firstMaterial = wallMat(darkFloor)
        let floorN = SCNNode(geometry: floorGeo)
        floorN.eulerAngles.x = -.pi / 2
        floorN.position = SCNVector3(0, 0, -2.5)
        scene.rootNode.addChildNode(floorN)

        // Back wall
        let backGeo = SCNPlane(width: 8, height: 4)
        backGeo.firstMaterial = wallMat(darkWall)
        let backN = SCNNode(geometry: backGeo)
        backN.position = SCNVector3(0, 2, -6)
        scene.rootNode.addChildNode(backN)

        // Ceiling
        let ceilGeo = SCNPlane(width: 8, height: 7)
        ceilGeo.firstMaterial = wallMat(UIColor(red: 0.05, green: 0.04, blue: 0.08, alpha: 1))
        let ceilN = SCNNode(geometry: ceilGeo)
        ceilN.eulerAngles.x = .pi / 2
        ceilN.position = SCNVector3(0, 4, -2.5)
        scene.rootNode.addChildNode(ceilN)

        // Left wall
        let lwGeo = SCNPlane(width: 7, height: 4)
        lwGeo.firstMaterial = wallMat(darkWall)
        let lwN = SCNNode(geometry: lwGeo)
        lwN.eulerAngles.y = .pi / 2
        lwN.position = SCNVector3(-4, 2, -2.5)
        scene.rootNode.addChildNode(lwN)

        // Right wall
        let rwGeo = SCNPlane(width: 7, height: 4)
        rwGeo.firstMaterial = wallMat(darkWall)
        let rwN = SCNNode(geometry: rwGeo)
        rwN.eulerAngles.y = -.pi / 2
        rwN.position = SCNVector3(4, 2, -2.5)
        scene.rootNode.addChildNode(rwN)

        // Bed
        let bedGeo = SCNBox(width: 2, height: 0.4, length: 2.2, chamferRadius: 0.05)
        let bedMat = SCNMaterial()
        bedMat.diffuse.contents = UIColor(red: 0.35, green: 0.25, blue: 0.20, alpha: 1)
        bedMat.lightingModel = .constant
        bedGeo.firstMaterial = bedMat
        let bedN = SCNNode(geometry: bedGeo)
        bedN.position = SCNVector3(0, 0.2, 0)
        scene.rootNode.addChildNode(bedN)

        // TV Screen (3m wide, 16:9)
        let tvW: CGFloat = 3.0
        let tvH: CGFloat = 1.6875
        let tvGeo = SCNPlane(width: tvW, height: tvH)
        tvGeo.firstMaterial = vidMaterial
        let tv = SCNNode(geometry: tvGeo)
        tv.position = SCNVector3(0, 2.2, -5.8)
        tv.name = "tvScreen"
        scene.rootNode.addChildNode(tv)
        self.tvNode = tv

        // TV frame glow
        let glowGeo = SCNPlane(width: tvW + 0.2, height: tvH + 0.2)
        let glowMat = SCNMaterial()
        glowMat.diffuse.contents = UIColor(red: 0.1, green: 0.2, blue: 0.4, alpha: 1)
        glowMat.lightingModel = .constant
        glowGeo.firstMaterial = glowMat
        let glowN = SCNNode(geometry: glowGeo)
        glowN.position = SCNVector3(0, 2.2, -5.82)
        scene.rootNode.addChildNode(glowN)

        // TV light casting into the room
        let tvLight = SCNLight()
        tvLight.type = .omni
        tvLight.color = UIColor(red: 0.3, green: 0.4, blue: 0.7, alpha: 1)
        tvLight.intensity = 250
        tvLight.attenuationStartDistance = 1
        tvLight.attenuationEndDistance = 6
        let lightN = SCNNode()
        lightN.light = tvLight
        lightN.position = SCNVector3(0, 2.2, -5.5)
        scene.rootNode.addChildNode(lightN)

        // Reposition button (below TV)
        let btnGeo = SCNBox(width: 0.5, height: 0.12, length: 0.02, chamferRadius: 0.03)
        let btnMat = SCNMaterial()
        btnMat.diffuse.contents = UIColor(red: 0.15, green: 0.45, blue: 1.0, alpha: 0.8)
        btnMat.lightingModel = .constant
        btnGeo.firstMaterial = btnMat
        let btn = SCNNode(geometry: btnGeo)
        btn.position = SCNVector3(0, 2.2 - Float(tvH) / 2 - 0.2, -5.78)
        btn.name = "repositionBtn"
        scene.rootNode.addChildNode(btn)
        self.btnNode = btn

        // Crosshair (small sphere at gaze center)
        let chGeo = SCNSphere(radius: 0.012)
        let chMat = SCNMaterial()
        chMat.diffuse.contents = UIColor.white.withAlphaComponent(0.5)
        chMat.lightingModel = .constant
        chMat.writesToDepthBuffer = false
        chMat.readsFromDepthBuffer = false
        chGeo.firstMaterial = chMat
        let ch = SCNNode(geometry: chGeo)
        ch.position = SCNVector3(0, 0, -3)
        ch.renderingOrder = 100
        headNode.addChildNode(ch)
        self.crosshairNode = ch

        // Ambient
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.color = UIColor(white: 0.04, alpha: 1)
        let ambN = SCNNode()
        ambN.light = ambient
        scene.rootNode.addChildNode(ambN)

        // Start gaze loop
        gazeTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.tickGaze()
        }
    }

    // MARK: Gaze Detection (Cinema)

    private func tickGaze() {
        guard currentMode == .cinema else { return }

        let fwd = headNode.convertVector(SCNVector3(0, 0, -1), to: nil)
        let hPos = headNode.worldPosition

        // Normalize forward
        let fLen = sqrtf(fwd.x * fwd.x + fwd.y * fwd.y + fwd.z * fwd.z)
        let fN = SCNVector3(fwd.x / fLen, fwd.y / fLen, fwd.z / fLen)

        if isPlacingTV {
            handlePlacing(forward: fN, headPos: hPos)
        } else {
            handleGazing(forward: fN, headPos: hPos)
        }
    }

    private func handleGazing(forward fN: SCNVector3, headPos hPos: SCNVector3) {
        guard let btn = btnNode else { return }
        let bPos = btn.worldPosition

        // Direction to button
        let toB = SCNVector3(bPos.x - hPos.x, bPos.y - hPos.y, bPos.z - hPos.z)
        let bLen = sqrtf(toB.x * toB.x + toB.y * toB.y + toB.z * toB.z)
        guard bLen > 0.001 else { return }
        let bN = SCNVector3(toB.x / bLen, toB.y / bLen, toB.z / bLen)

        let dot = fN.x * bN.x + fN.y * bN.y + fN.z * bN.z
        let lookingAtBtn = dot > 0.98

        if lookingAtBtn {
            if gazeStart == nil { gazeStart = Date() }
            let elapsed = Date().timeIntervalSince(gazeStart!)
            let prog = min(elapsed / 4.0, 1.0)
            gazeProgress = CGFloat(prog)

            // Pulse crosshair cyan
            crosshairNode?.geometry?.firstMaterial?.diffuse.contents =
                UIColor(red: 0.2, green: CGFloat(0.6 + prog * 0.4), blue: 1.0, alpha: CGFloat(0.5 + prog * 0.5))
            crosshairNode?.scale = SCNVector3(1 + Float(prog) * 0.6, 1 + Float(prog) * 0.6, 1)

            // Pulse button
            btn.geometry?.firstMaterial?.diffuse.contents =
                UIColor(red: CGFloat(0.15 + prog * 0.85), green: CGFloat(0.45 - prog * 0.2), blue: CGFloat(1.0 - prog * 0.7), alpha: 0.9)

            if prog >= 1.0 {
                // Enter placement mode
                isPlacingTV = true
                gazeStart = nil
                gazeProgress = 0
                crosshairNode?.geometry?.firstMaterial?.diffuse.contents =
                    UIColor(red: 1.0, green: 0.5, blue: 0.1, alpha: 0.8)
                btn.geometry?.firstMaterial?.diffuse.contents =
                    UIColor(red: 1.0, green: 0.5, blue: 0.1, alpha: 0.9)
            }
        } else {
            gazeStart = nil
            gazeProgress = 0
            crosshairNode?.geometry?.firstMaterial?.diffuse.contents = UIColor.white.withAlphaComponent(0.5)
            crosshairNode?.scale = SCNVector3(1, 1, 1)
            btn.geometry?.firstMaterial?.diffuse.contents =
                UIColor(red: 0.15, green: 0.45, blue: 1.0, alpha: 0.8)
        }
    }

    private func handlePlacing(forward fN: SCNVector3, headPos hPos: SCNVector3) {
        if placeStart == nil { placeStart = Date() }
        let elapsed = Date().timeIntervalSince(placeStart!)
        let prog = min(elapsed / 4.0, 1.0)
        gazeProgress = CGFloat(prog)

        // Green pulse on crosshair
        crosshairNode?.geometry?.firstMaterial?.diffuse.contents =
            UIColor(red: CGFloat(0.2 - prog * 0.2), green: CGFloat(0.6 + prog * 0.4), blue: CGFloat(0.2), alpha: CGFloat(0.6 + prog * 0.4))
        crosshairNode?.scale = SCNVector3(1 + Float(prog) * 0.8, 1 + Float(prog) * 0.8, 1)

        if prog >= 1.0 {
            // Place TV 4m from head in gaze direction
            let dist: Float = 4.0
            let newPos = SCNVector3(
                hPos.x + fN.x * dist,
                hPos.y + fN.y * dist,
                hPos.z + fN.z * dist
            )

            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.8

            tvNode?.position = newPos
            // Orient TV to face viewer (rotate around Y only)
            let dx = hPos.x - newPos.x
            let dz = hPos.z - newPos.z
            tvNode?.eulerAngles = SCNVector3(0, atan2(dx, dz), 0)

            // Move button below new TV position
            if let btn = btnNode {
                let tvH = Float((tvNode?.geometry as? SCNPlane)?.height ?? 1.6875)
                btn.position = SCNVector3(newPos.x, newPos.y - tvH / 2 - 0.2, newPos.z)
                btn.eulerAngles = tvNode?.eulerAngles ?? SCNVector3(0, 0, 0)
                // Push button slightly toward viewer
                btn.position.x += fN.x * (-0.03)
                btn.position.z += fN.z * (-0.03)
            }

            SCNTransaction.commit()

            // Reset state
            isPlacingTV = false
            placeStart = nil
            gazeProgress = 0
            crosshairNode?.geometry?.firstMaterial?.diffuse.contents = UIColor.white.withAlphaComponent(0.5)
            crosshairNode?.scale = SCNVector3(1, 1, 1)
            btnNode?.geometry?.firstMaterial?.diffuse.contents =
                UIColor(red: 0.15, green: 0.45, blue: 1.0, alpha: 0.8)
        }
    }

    // MARK: Mode 4 — Void Theater

    private func buildVoid() {
        headNode.position = SCNVector3(0, 0, 0)

        // Giant IMAX-style screen
        let screenW: CGFloat = 14
        let screenH: CGFloat = 7.875 // 16:9
        let screenGeo = SCNPlane(width: screenW, height: screenH)
        screenGeo.firstMaterial = vidMaterial
        let screenN = SCNNode(geometry: screenGeo)
        screenN.position = SCNVector3(0, 0, -9)
        scene.rootNode.addChildNode(screenN)

        // Glow plane behind screen
        let glowGeo = SCNPlane(width: screenW + 1.5, height: screenH + 1.5)
        let glowMat = SCNMaterial()
        glowMat.diffuse.contents = UIColor(red: 0.05, green: 0.02, blue: 0.15, alpha: 1)
        glowMat.lightingModel = .constant
        glowGeo.firstMaterial = glowMat
        let glowN = SCNNode(geometry: glowGeo)
        glowN.position = SCNVector3(0, 0, -9.1)
        scene.rootNode.addChildNode(glowN)

        // Edge glow light
        let screenLight = SCNLight()
        screenLight.type = .omni
        screenLight.color = UIColor(red: 0.2, green: 0.1, blue: 0.5, alpha: 1)
        screenLight.intensity = 300
        screenLight.attenuationStartDistance = 2
        screenLight.attenuationEndDistance = 12
        let sLightN = SCNNode()
        sLightN.light = screenLight
        sLightN.position = SCNVector3(0, 0, -8)
        scene.rootNode.addChildNode(sLightN)

        // Star particles
        let stars = SCNParticleSystem()
        stars.birthRate = 30
        stars.particleLifeSpan = 200
        stars.warmupDuration = 200
        stars.particleSize = 0.04
        stars.particleSizeVariation = 0.03
        stars.particleColor = .white
        stars.particleColorVariation = SCNVector4(0.1, 0.1, 0.3, 0)
        stars.emitterShape = SCNSphere(radius: 60)
        stars.birthLocation = .volume
        stars.particleVelocity = 0
        stars.isAffectedByGravity = false
        stars.blendMode = .additive
        let starsN = SCNNode()
        starsN.addParticleSystem(stars)
        scene.rootNode.addChildNode(starsN)

        // Far nebula background sphere
        let nebGeo = SCNSphere(radius: 90)
        nebGeo.segmentCount = 32
        let nebMat = SCNMaterial()
        nebMat.diffuse.contents = UIColor(red: 0.02, green: 0.01, blue: 0.05, alpha: 1)
        nebMat.lightingModel = .constant
        nebMat.isDoubleSided = true
        nebGeo.firstMaterial = nebMat
        let nebN = SCNNode(geometry: nebGeo)
        scene.rootNode.addChildNode(nebN)
    }

    // MARK: Motion Tracking

    func beginMotion() {
        guard motionMgr.isDeviceMotionAvailable else { return }
        motionMgr.deviceMotionUpdateInterval = 1.0 / 60.0
        motionMgr.startDeviceMotionUpdates(using: .xArbitraryCorrectedZVertical, to: .main) { [weak self] motion, _ in
            guard let self = self, let m = motion else { return }
            let q = m.attitude.quaternion
            self.headNode.orientation = SCNQuaternion(
                Float(-q.y), Float(q.x), Float(q.z), Float(q.w)
            )
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                withAnimation { showUI = false }
            }
        }
        .onDisappear {
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
            if mgr.currentMode == .cinema && mgr.gazeProgress > 0 {
                HStack(spacing: 6) {
                    Circle()
                        .fill(mgr.isPlacingTV ? Color.green : Color.cyan)
                        .frame(width: 8, height: 8)
                    Text(mgr.isPlacingTV ? "Look at new spot..." : "Hold gaze...")
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
            Text("🎯 Look where you want the TV, hold for 4s")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.orange)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.75))
                .cornerRadius(10)
                .padding(.bottom, 80)
        }
        .transition(.opacity)
    }
}
