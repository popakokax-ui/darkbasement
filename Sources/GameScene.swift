import SpriteKit
import UIKit

final class GameScene: SKScene {

    // MARK: - Настройки
    private let tile: CGFloat = 64
    private let mazeSize = 21
    private let fuseGoal = 4
    private let playerRadius: CGFloat = 11

    private enum State { case playing, won, lost }
    private var state: State = .playing

    // MARK: - Мир
    private var maze: Maze!
    private let cam = SKCameraNode()
    private let player = SKSpriteNode(color: UIColor(white: 0.75, alpha: 1), size: CGSize(width: 22, height: 22))
    private let flashlight = SKLightNode()
    private let creature = SKSpriteNode(color: .black, size: CGSize(width: 38, height: 38))
    private var fuses: [SKSpriteNode] = []
    private var batteries: [SKSpriteNode] = []
    private let exitNode = SKSpriteNode(color: UIColor(red: 0.2, green: 0.95, blue: 0.45, alpha: 1),
                                        size: CGSize(width: 40, height: 40))
    private var exitActive = false

    // MARK: - Состояние игры
    private var fusesCollected = 0
    private var battery: CGFloat = 100
    private var flashOn = true
    private var lastUpdate: TimeInterval = 0
    private var endDate = Date.distantPast

    // MARK: - Существо
    private var creaturePath: [GridPoint] = []
    private var repathTimer: TimeInterval = 0
    private var isChasing = false

    // MARK: - Управление
    private var joystickTouch: UITouch?
    private var joystickOrigin = CGPoint.zero
    private var joystickVector = CGVector.zero
    private let joyRadius: CGFloat = 55

    // MARK: - HUD
    private let joyBase = SKShapeNode(circleOfRadius: 55)
    private let joyKnob = SKShapeNode(circleOfRadius: 24)
    private let fuseLabel = SKLabelNode(fontNamed: "HelveticaNeue-Bold")
    private let batteryTitle = SKLabelNode(fontNamed: "HelveticaNeue-Bold")
    private let batteryBack = SKSpriteNode(color: UIColor(white: 0.2, alpha: 1), size: CGSize(width: 110, height: 10))
    private let batteryFill = SKSpriteNode(color: UIColor(red: 1, green: 0.85, blue: 0.3, alpha: 1),
                                           size: CGSize(width: 110, height: 10))
    private let flashButton = SKShapeNode(circleOfRadius: 38)
    private let flashIcon = SKLabelNode(fontNamed: "HelveticaNeue-Bold")
    private let messageLabel = SKLabelNode(fontNamed: "HelveticaNeue-Bold")
    private let endLabel = SKLabelNode(fontNamed: "HelveticaNeue-Bold")
    private let redOverlay = SKSpriteNode(color: UIColor(red: 0.8, green: 0, blue: 0, alpha: 1), size: CGSize(width: 10, height: 10))

    private var heartbeatTimer: TimeInterval = 0
    private let heavyHaptic = UIImpactFeedbackGenerator(style: .heavy)

    // MARK: - Жизненный цикл
    override func didMove(to view: SKView) {
        view.isMultipleTouchEnabled = true
        startNewGame()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        layoutHUD()
    }

    private func startNewGame() {
        removeAllChildren()
        cam.removeAllChildren()
        camera = cam
        addChild(cam)

        backgroundColor = .black
        state = .playing
        fusesCollected = 0
        battery = 100
        flashOn = true
        exitActive = false
        lastUpdate = 0
        joystickTouch = nil
        joystickVector = .zero
        creaturePath = []
        repathTimer = 0
        isChasing = false
        fuses = []
        batteries = []

        maze = Maze(size: mazeSize)
        buildWorld()
        buildHUD()
        layoutHUD()
        showMessage("Найди все предохранители и выберись наружу")
    }

    // MARK: - Построение мира
    private func center(of p: GridPoint) -> CGPoint {
        CGPoint(x: (CGFloat(p.x) + 0.5) * tile, y: (CGFloat(p.y) + 0.5) * tile)
    }

    private func tileFor(_ point: CGPoint) -> GridPoint {
        GridPoint(x: Int(floor(point.x / tile)), y: Int(floor(point.y / tile)))
    }

    private func buildWorld() {
        let worldSize = CGFloat(mazeSize) * tile

        let floorNode = SKSpriteNode(color: UIColor(red: 0.24, green: 0.2, blue: 0.16, alpha: 1),
                                     size: CGSize(width: worldSize, height: worldSize))
        floorNode.anchorPoint = .zero
        floorNode.position = .zero
        floorNode.zPosition = -10
        floorNode.lightingBitMask = 1
        floorNode.shadowedBitMask = 1
        addChild(floorNode)

        // Тёмные пятна на полу, чтобы пространство не выглядело пустым
        for _ in 0..<40 {
            let stain = SKSpriteNode(color: UIColor(red: 0.1, green: 0.08, blue: 0.06, alpha: 1),
                                     size: CGSize(width: CGFloat.random(in: 20...70), height: CGFloat.random(in: 14...50)))
            stain.position = CGPoint(x: CGFloat.random(in: 0...worldSize), y: CGFloat.random(in: 0...worldSize))
            stain.zRotation = CGFloat.random(in: 0...CGFloat.pi)
            stain.zPosition = -9
            stain.lightingBitMask = 1
            addChild(stain)
        }

        for y in 0..<mazeSize {
            for x in 0..<mazeSize where maze.walls[y][x] {
                let wall = SKSpriteNode(color: UIColor(red: 0.4, green: 0.32, blue: 0.24, alpha: 1),
                                        size: CGSize(width: tile, height: tile))
                wall.position = center(of: GridPoint(x: x, y: y))
                wall.zPosition = 1
                wall.lightingBitMask = 1
                wall.shadowCastBitMask = 1
                wall.shadowedBitMask = 1
                addChild(wall)
            }
        }

        let start = GridPoint(x: 1, y: 1)
        let dist = maze.distances(from: start)

        // Игрок
        player.position = center(of: start)
        player.zPosition = 5
        player.lightingBitMask = 0
        addChild(player)

        flashlight.categoryBitMask = 1
        flashlight.lightColor = UIColor(red: 1, green: 0.94, blue: 0.78, alpha: 1)
        flashlight.ambientColor = UIColor(white: 0.035, alpha: 1)
        flashlight.shadowColor = UIColor(white: 0, alpha: 0.92)
        flashlight.falloff = 1.1
        flashlight.isEnabled = true
        flashlight.removeFromParent()
        player.addChild(flashlight)

        // Предметы
        var candidates = maze.freeCells().filter { (dist[$0] ?? 0) >= 8 }
        candidates.shuffle()

        let exitCell = candidates.max { (dist[$0] ?? 0) < (dist[$1] ?? 0) } ?? GridPoint(x: mazeSize - 2, y: mazeSize - 2)
        candidates.removeAll { $0 == exitCell }

        exitNode.position = center(of: exitCell)
        exitNode.zPosition = 2
        exitNode.lightingBitMask = 0
        exitNode.alpha = 0
        exitNode.removeAllActions()
        addChild(exitNode)

        for _ in 0..<fuseGoal {
            guard let cell = candidates.popLast() else { break }
            let fuse = SKSpriteNode(color: UIColor(red: 1, green: 0.85, blue: 0.2, alpha: 1),
                                    size: CGSize(width: 14, height: 22))
            fuse.position = center(of: cell)
            fuse.zPosition = 3
            fuse.lightingBitMask = 1
            let glow = SKSpriteNode(color: UIColor(red: 1, green: 0.8, blue: 0.1, alpha: 1),
                                    size: CGSize(width: 34, height: 34))
            glow.alpha = 0.18
            glow.lightingBitMask = 0
            glow.zPosition = -1
            glow.run(.repeatForever(.sequence([.fadeAlpha(to: 0.4, duration: 0.9),
                                               .fadeAlpha(to: 0.1, duration: 0.9)])))
            fuse.addChild(glow)
            addChild(fuse)
            fuses.append(fuse)
        }

        for _ in 0..<4 {
            guard let cell = candidates.popLast() else { break }
            let cellNode = SKSpriteNode(color: UIColor(red: 0.35, green: 0.9, blue: 0.4, alpha: 1),
                                        size: CGSize(width: 12, height: 20))
            cellNode.position = center(of: cell)
            cellNode.zPosition = 3
            cellNode.lightingBitMask = 1
            addChild(cellNode)
            batteries.append(cellNode)
        }

        // Существо: само по себе чёрное, видны только глаза
        let farCells = maze.freeCells().filter { (dist[$0] ?? 0) >= 14 }
        let creatureCell = farCells.randomElement() ?? exitCell
        creature.position = center(of: creatureCell)
        creature.zPosition = 4
        creature.lightingBitMask = 1
        creature.removeAllChildren()
        for dx in [-7.0, 7.0] {
            let eye = SKSpriteNode(color: UIColor(red: 1, green: 0.1, blue: 0.1, alpha: 1),
                                   size: CGSize(width: 5, height: 5))
            eye.position = CGPoint(x: dx, y: 5)
            eye.zPosition = 1
            eye.lightingBitMask = 0
            creature.addChild(eye)
        }
        creature.removeAllActions()
        creature.run(.repeatForever(.sequence([.scale(to: 1.08, duration: 0.5), .scale(to: 0.94, duration: 0.5)])))
        addChild(creature)

        cam.position = player.position
    }

    // MARK: - HUD
    private func buildHUD() {
        joyBase.strokeColor = UIColor(white: 1, alpha: 0.35)
        joyBase.fillColor = UIColor(white: 1, alpha: 0.06)
        joyBase.zPosition = 50
        joyBase.isHidden = true
        cam.addChild(joyBase)

        joyKnob.strokeColor = UIColor(white: 1, alpha: 0.5)
        joyKnob.fillColor = UIColor(white: 1, alpha: 0.2)
        joyKnob.zPosition = 51
        joyKnob.isHidden = true
        cam.addChild(joyKnob)

        fuseLabel.fontSize = 18
        fuseLabel.fontColor = UIColor(red: 1, green: 0.85, blue: 0.2, alpha: 1)
        fuseLabel.horizontalAlignmentMode = .left
        fuseLabel.zPosition = 60
        cam.addChild(fuseLabel)
        updateFuseLabel()

        batteryTitle.text = "ФОНАРЬ"
        batteryTitle.fontSize = 12
        batteryTitle.fontColor = UIColor(white: 0.8, alpha: 1)
        batteryTitle.horizontalAlignmentMode = .left
        batteryTitle.zPosition = 60
        cam.addChild(batteryTitle)

        batteryBack.anchorPoint = CGPoint(x: 0, y: 0.5)
        batteryBack.zPosition = 60
        cam.addChild(batteryBack)

        batteryFill.anchorPoint = CGPoint(x: 0, y: 0.5)
        batteryFill.zPosition = 61
        cam.addChild(batteryFill)

        flashButton.strokeColor = UIColor(white: 1, alpha: 0.6)
        flashButton.lineWidth = 2
        flashButton.zPosition = 60
        cam.addChild(flashButton)

        flashIcon.text = "💡"
        flashIcon.fontSize = 30
        flashIcon.verticalAlignmentMode = .center
        flashIcon.horizontalAlignmentMode = .center
        flashIcon.zPosition = 1
        flashIcon.removeFromParent()
        flashButton.addChild(flashIcon)
        applyFlashButtonLook()

        messageLabel.fontSize = 18
        messageLabel.fontColor = .white
        messageLabel.zPosition = 60
        messageLabel.alpha = 0
        cam.addChild(messageLabel)

        endLabel.fontSize = 30
        endLabel.fontColor = .white
        endLabel.numberOfLines = 3
        endLabel.preferredMaxLayoutWidth = 700
        endLabel.horizontalAlignmentMode = .center
        endLabel.verticalAlignmentMode = .center
        endLabel.zPosition = 90
        endLabel.alpha = 0
        cam.addChild(endLabel)

        redOverlay.zPosition = 80
        redOverlay.alpha = 0
        cam.addChild(redOverlay)
    }

    private func layoutHUD() {
        guard cam.parent != nil else { return }
        let w = size.width
        let h = size.height
        fuseLabel.position = CGPoint(x: -w / 2 + 80, y: h / 2 - 40)
        batteryTitle.position = CGPoint(x: w / 2 - 200, y: h / 2 - 40)
        batteryBack.position = CGPoint(x: w / 2 - 200, y: h / 2 - 56)
        batteryFill.position = batteryBack.position
        flashButton.position = CGPoint(x: w / 2 - 110, y: -h / 2 + 80)
        messageLabel.position = CGPoint(x: 0, y: h / 2 - 90)
        endLabel.position = .zero
        redOverlay.size = CGSize(width: w * 1.5, height: h * 1.5)
    }

    private func updateFuseLabel() {
        fuseLabel.text = "ПРЕДОХРАНИТЕЛИ  \(fusesCollected)/\(fuseGoal)"
    }

    private func showMessage(_ text: String) {
        messageLabel.removeAllActions()
        messageLabel.text = text
        messageLabel.alpha = 1
        messageLabel.run(.sequence([.wait(forDuration: 3.5), .fadeOut(withDuration: 0.8)]))
    }

    private func applyFlashButtonLook() {
        flashButton.fillColor = flashOn ? UIColor(red: 1, green: 0.85, blue: 0.3, alpha: 0.35)
                                        : UIColor(white: 0.2, alpha: 0.5)
    }

    // MARK: - Фонарик
    private func setFlash(_ on: Bool) {
        if on && battery <= 0 { return }
        flashOn = on
        flashlight.falloff = on ? 1.1 : 5.0
        applyFlashButtonLook()
    }

    private func updateFlashlight(_ dt: TimeInterval) {
        if flashOn {
            battery -= CGFloat(dt) * 3.5
            if battery <= 0 {
                battery = 0
                setFlash(false)
                showMessage("Батарея села…")
            }
        }
        batteryFill.xScale = max(battery / 100, 0.001)
        if flashOn && battery < 20 && Int.random(in: 0..<10) == 0 {
            flashlight.lightColor = UIColor(red: 0.5, green: 0.47, blue: 0.4, alpha: 1)
        } else {
            flashlight.lightColor = UIColor(red: 1, green: 0.94, blue: 0.78, alpha: 1)
        }
    }

    // MARK: - Движение
    private func canStand(at p: CGPoint, radius r: CGFloat) -> Bool {
        let minX = Int(floor((p.x - r) / tile)), maxX = Int(floor((p.x + r) / tile))
        let minY = Int(floor((p.y - r) / tile)), maxY = Int(floor((p.y + r) / tile))
        for gy in minY...maxY {
            for gx in minX...maxX where maze.isWall(GridPoint(x: gx, y: gy)) {
                return false
            }
        }
        return true
    }

    private func movePlayer(_ dt: TimeInterval) {
        let speed: CGFloat = 165
        let step = speed * CGFloat(dt)
        var p = player.position
        let tryX = CGPoint(x: p.x + joystickVector.dx * step, y: p.y)
        if canStand(at: tryX, radius: playerRadius) { p = tryX }
        let tryY = CGPoint(x: p.x, y: p.y + joystickVector.dy * step)
        if canStand(at: tryY, radius: playerRadius) { p = tryY }
        player.position = p
    }

    private func updateCreature(_ dt: TimeInterval) {
        repathTimer -= dt
        if repathTimer <= 0 {
            repathTimer = 0.35
            let cTile = tileFor(creature.position)
            let pTile = tileFor(player.position)
            let toPlayer = maze.path(from: cTile, to: pTile)
            let sight = flashOn ? 10 : 5
            if toPlayer.count <= sight && (cTile == pTile || !toPlayer.isEmpty) {
                isChasing = true
                creaturePath = toPlayer
            } else {
                isChasing = false
                if creaturePath.isEmpty, let goal = maze.freeCells().randomElement() {
                    creaturePath = maze.path(from: cTile, to: goal)
                }
            }
        }

        let speed = 85 + 15 * Double(fusesCollected) + (isChasing ? 25 : 0)
        var target: CGPoint?
        if let next = creaturePath.first {
            target = center(of: next)
        } else if isChasing {
            target = player.position
        }
        if let t = target {
            let dx = t.x - creature.position.x
            let dy = t.y - creature.position.y
            let dist = max(hypot(dx, dy), 0.001)
            let step = min(CGFloat(speed * dt), dist)
            creature.position.x += dx / dist * step
            creature.position.y += dy / dist * step
            if dist <= step + 0.5, !creaturePath.isEmpty {
                creaturePath.removeFirst()
            }
        }

        if hypot(creature.position.x - player.position.x, creature.position.y - player.position.y) < 26 {
            lose()
        }
    }

    private func collectItems() {
        for fuse in fuses where fuse.parent != nil {
            if hypot(fuse.position.x - player.position.x, fuse.position.y - player.position.y) < 24 {
                fuse.removeFromParent()
                fusesCollected += 1
                updateFuseLabel()
                if fusesCollected >= fuseGoal {
                    exitActive = true
                    exitNode.alpha = 1
                    exitNode.run(.repeatForever(.sequence([.fadeAlpha(to: 0.4, duration: 0.6),
                                                           .fadeAlpha(to: 1, duration: 0.6)])))
                    showMessage("Выход открыт! Найди зелёный свет")
                } else {
                    showMessage("Предохранитель найден. Существо стало быстрее…")
                }
            }
        }
        for cell in batteries where cell.parent != nil {
            if hypot(cell.position.x - player.position.x, cell.position.y - player.position.y) < 22 {
                cell.removeFromParent()
                battery = min(100, battery + 40)
                showMessage("Батарейка +40")
            }
        }
        if exitActive,
           hypot(exitNode.position.x - player.position.x, exitNode.position.y - player.position.y) < 28 {
            win()
        }
    }

    private func updateFear(_ dt: TimeInterval) {
        let d = hypot(creature.position.x - player.position.x, creature.position.y - player.position.y) / tile
        let fear = max(0, min(1, (6 - d) / 6))
        redOverlay.alpha = CGFloat(fear) * 0.4
        if d < 7 {
            heartbeatTimer -= dt
            if heartbeatTimer <= 0 {
                heartbeatTimer = max(0.28, Double(d) * 0.12)
                heavyHaptic.impactOccurred()
            }
        }
    }

    // MARK: - Конец игры
    private func lose() {
        guard state == .playing else { return }
        state = .lost
        endDate = Date()
        joystickVector = .zero
        redOverlay.alpha = 0.6
        endLabel.text = "ТЕБЯ ПОЙМАЛИ\nКоснись экрана, чтобы начать заново"
        endLabel.alpha = 1
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    private func win() {
        guard state == .playing else { return }
        state = .won
        endDate = Date()
        joystickVector = .zero
        redOverlay.alpha = 0
        endLabel.text = "ТЫ ВЫБРАЛСЯ!\nКоснись экрана, чтобы сыграть ещё"
        endLabel.alpha = 1
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    // MARK: - Цикл
    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdate == 0 ? 0 : min(currentTime - lastUpdate, 1.0 / 20.0)
        lastUpdate = currentTime
        guard state == .playing, dt > 0 else { return }
        movePlayer(dt)
        updateFlashlight(dt)
        updateCreature(dt)
        collectItems()
        updateFear(dt)
        cam.position = player.position
    }

    // MARK: - Касания
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if state != .playing {
            if Date().timeIntervalSince(endDate) > 0.8 { startNewGame() }
            return
        }
        for t in touches {
            let p = t.location(in: cam)
            if hypot(p.x - flashButton.position.x, p.y - flashButton.position.y) < 55 {
                setFlash(!flashOn)
                continue
            }
            if p.x < 0, joystickTouch == nil {
                joystickTouch = t
                joystickOrigin = p
                joyBase.position = p
                joyKnob.position = p
                joyBase.isHidden = false
                joyKnob.isHidden = false
                joystickVector = .zero
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let j = joystickTouch, touches.contains(j) else { return }
        let p = j.location(in: cam)
        var dx = p.x - joystickOrigin.x
        var dy = p.y - joystickOrigin.y
        let len = hypot(dx, dy)
        if len > joyRadius {
            dx = dx / len * joyRadius
            dy = dy / len * joyRadius
        }
        joyKnob.position = CGPoint(x: joystickOrigin.x + dx, y: joystickOrigin.y + dy)
        joystickVector = CGVector(dx: dx / joyRadius, dy: dy / joyRadius)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        releaseJoystick(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        releaseJoystick(touches)
    }

    private func releaseJoystick(_ touches: Set<UITouch>) {
        guard let j = joystickTouch, touches.contains(j) else { return }
        joystickTouch = nil
        joystickVector = .zero
        joyBase.isHidden = true
        joyKnob.isHidden = true
    }
}
