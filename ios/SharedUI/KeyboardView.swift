import UIKit

/// Shared by the keyboard extension and the containing app's practice screen.
/// Joystick gestures own one touch; letter and symbol keys allow overlapping thumbs.
public final class KeyboardView: UIView {
    public var onAction: ((KeyboardAction) -> Void)?
    public var onMoveCursor: ((Int) -> Void)?
    public var onMoveLine: ((Int) -> Void)?
    public var onDismiss: (() -> Void)?
    public var onHelp: (() -> Void)?
    public var onLanguageChange: ((String) -> Void)?
    public let nextKeyboardButton: UIButton = OwnedKeyboardButton(type: .system)
    public var needsNextKeyboard = true { didSet { if oldValue != needsNextKeyboard { setNeedsLayout() } } }
    public var returnKeyTitle = "줄바꿈" { didSet { returnButton.setTitle(returnKeyTitle, for: .normal) } }

    private let glassBackground = UIVisualEffectView()
    private let cPad = DirectionPad(pad: .c)
    private let vPad = DirectionPad(pad: .v)
    private var inputSurfaces: [DirectionPad] { [cPad, vPad] }
    private let statusLabel = UILabel()
    private let helpButton = OwnedKeyboardButton(type: .system)
    private let modeButton = OwnedKeyboardButton(type: .system)
    private let languageButton = OwnedKeyboardButton(type: .system)
    private let shiftButton = OwnedKeyboardButton(type: .system)
    private var english = EnglishKeyboard()
    private var englishMode = false
    private var letterButtons: [String: OwnedKeyboardButton] = [:]
    private var englishPunctuationButtons: [OwnedKeyboardButton] = []
    private let symbolPageButton = OwnedKeyboardButton(type: .system)
    private var symbolPage = 0
    private let spaceButton = OwnedKeyboardButton(type: .system)
    private let rightSpaceButton = OwnedKeyboardButton(type: .system)
    private let deleteButton = OwnedKeyboardButton(type: .system)
    private let returnButton = OwnedKeyboardButton(type: .system)
    private let dismissButton = OwnedKeyboardButton(type: .system)
    private var symbolButtons: [OwnedKeyboardButton] = []
    private var symbolMode = false
    private var classifier = AnchoredGesture()
    private var ownerTouch: UITouch?
    private weak var ownerPad: DirectionPad?
    private weak var ownerButton: OwnedKeyboardButton?
    private var typingTouches: Set<OwnedKeyboardButton> = []
    private var lastLayoutBounds: CGRect = .zero
    private var lastSafeArea: UIEdgeInsets = .zero
    private var target: String?
    private var canUndoModifier = false
    private var feedback: UIImpactFeedbackGenerator?
    private var spaceCursor = SpaceCursorGesture()
    private var deleteTimer: Timer?
    private var deleteHoldStarted: CFTimeInterval = 0
    private var lastBlockDelete: CFTimeInterval = 0
    private var didRepeatDelete = false
    private var lastCandidate: String?

    public override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        backgroundColor = .clear
        isOpaque = false
        isMultipleTouchEnabled = true
        accessibilityIdentifier = "three-pad-keyboard"
        glassBackground.isUserInteractionEnabled = false
        glassBackground.isAccessibilityElement = false
        glassBackground.layer.cornerRadius = 24
        glassBackground.layer.cornerCurve = .continuous
        glassBackground.clipsToBounds = true
        addSubview(glassBackground)
        updateGlassBackground()
        NotificationCenter.default.addObserver(self, selector: #selector(updateGlassBackground),
            name: UIAccessibility.reduceTransparencyStatusDidChangeNotification, object: nil)
        statusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        statusLabel.textColor = Palette.muted
        statusLabel.adjustsFontSizeToFitWidth = true
        statusLabel.minimumScaleFactor = 0.75
        statusLabel.accessibilityIdentifier = "gesture-status"
        addSubview(statusLabel)
        for pad in inputSurfaces {
            pad.isUserInteractionEnabled = false
            pad.performAction = { [weak self] action in self?.emit(action) }
            addSubview(pad)
        }
        configureButton(helpButton, title: "", label: "입력 방법")
        helpButton.setImage(UIImage(systemName: "info.circle"), for: .normal)
        helpButton.addTarget(self, action: #selector(showHelp), for: .touchUpInside)
        configureButton(nextKeyboardButton as! OwnedKeyboardButton, title: "", label: "다음 키보드")
        nextKeyboardButton.setImage(UIImage(systemName: "globe"), for: .normal)
        nextKeyboardButton.accessibilityIdentifier = "next-keyboard"
        configureButton(modeButton, title: "123", label: "숫자와 기호")
        modeButton.addTarget(self, action: #selector(toggleMode), for: .touchUpInside)
        configureButton(languageButton, title: "ABC", label: "영어로 전환")
        languageButton.accessibilityIdentifier = "key-language"
        languageButton.addTarget(self, action: #selector(toggleLanguage), for: .touchUpInside)
        configureButton(shiftButton, title: "", label: "대문자 전환")
        shiftButton.accessibilityIdentifier = "key-shift"
        shiftButton.accessibilityHint = "탭하면 한 글자 대문자. 길게 누르거나 동작 메뉴를 사용하면 대문자 고정."
        shiftButton.addTarget(self, action: #selector(toggleShift), for: .touchUpInside)
        let capsLock = UILongPressGestureRecognizer(target: self, action: #selector(holdShift(_:)))
        capsLock.minimumPressDuration = 0.45
        capsLock.cancelsTouchesInView = true
        capsLock.delegate = shiftButton
        shiftButton.addGestureRecognizer(capsLock)
        shiftButton.accessibilityCustomActions = [UIAccessibilityCustomAction(name: "대문자 고정 전환") { [weak self] _ in
            guard let self else { return false }
            self.cancelGesture()
            self.english.toggleCapsLock(); self.updateEnglishKeys(); self.updateIdleStatus()
            return true
        }]
        for letter in EnglishKeyboard.rows.flatMap({ $0 }) {
            let button = OwnedKeyboardButton(type: .system)
            configureButton(button, title: letter, label: letter)
            button.accessibilityIdentifier = "english-\(letter)"
            button.setFlickSymbol(EnglishKeyboard.flickSymbols[letter], letter: letter)
            if let symbol = EnglishKeyboard.flickSymbols[letter] {
                button.accessibilityHint = "위로 밀면 \(letter.uppercased()), 아래로 밀면 \(symbol) 입력"
                button.accessibilityCustomActions = [
                    UIAccessibilityCustomAction(name: "대문자 \(letter.uppercased()) 입력") { [weak self] _ in
                        guard let self, self.englishMode, !self.symbolMode else { return false }
                        self.insertEnglishUppercase(letter); return true
                    },
                    UIAccessibilityCustomAction(name: "아래로 밀어 \(symbol) 입력") { [weak self] _ in
                        guard let self, self.englishMode, !self.symbolMode else { return false }
                        self.emit(.literal(symbol)); return true
                    }
                ]
            }
            button.addAction(UIAction { [weak self] _ in self?.insertEnglish(letter) }, for: .touchUpInside)
            button.isHidden = true
            letterButtons[letter] = button
        }
        for value in ["'", "."] {
            let button = OwnedKeyboardButton(type: .system)
            configureButton(button, title: value, label: value)
            button.accessibilityIdentifier = "english-\(value)"
            button.addAction(UIAction { [weak self] _ in self?.emit(.literal(value)) }, for: .touchUpInside)
            button.isHidden = true
            englishPunctuationButtons.append(button)
        }
        shiftButton.isHidden = true
        configureButton(symbolPageButton, title: "#+=", label: "괄호·계산·통화 보기")
        symbolPageButton.accessibilityIdentifier = "key-symbol-page"
        symbolPageButton.addTarget(self, action: #selector(nextSymbolPage), for: .touchUpInside)
        symbolPageButton.isHidden = true
        configureButton(spaceButton, title: "공백", label: "공백")
        spaceButton.backgroundColor = Palette.control
        spaceButton.addTarget(self, action: #selector(insertSpace), for: .touchUpInside)
        configureButton(rightSpaceButton, title: "space", label: "오른쪽 공백")
        rightSpaceButton.accessibilityIdentifier = "english-space-right"
        rightSpaceButton.addTarget(self, action: #selector(insertSpace), for: .touchUpInside)
        rightSpaceButton.isHidden = true
        configureButton(deleteButton, title: "", label: "한 단계 지우기")
        deleteButton.setImage(UIImage(systemName: "delete.left"), for: .normal)
        deleteButton.addTarget(self, action: #selector(deleteCharacter), for: .touchUpInside)
        configureButton(dismissButton, title: "", label: "키보드 내리기")
        dismissButton.accessibilityIdentifier = "key-dismiss"
        dismissButton.setImage(UIImage(systemName: "keyboard.chevron.compact.down"), for: .normal)
        dismissButton.addTarget(self, action: #selector(dismissKeyboard), for: .touchUpInside)
        configureButton(returnButton, title: returnKeyTitle, label: "줄바꿈")
        returnButton.addTarget(self, action: #selector(insertReturn), for: .touchUpInside)
        for index in SymbolKeyboard.pages[0].indices {
            let button = OwnedKeyboardButton(type: .system)
            configureButton(button, title: "", label: "")
            button.accessibilityIdentifier = "symbol-\(index)"
            button.addAction(UIAction { [weak self] _ in self?.insertSymbol(at: index) }, for: .touchUpInside)
            button.isHidden = true
            symbolButtons.append(button)
        }
        updateEnglishKeys()
        updateSymbolKeys()
        updateModeControls()
    }

    @objc private func updateGlassBackground() {
        if UIAccessibility.isReduceTransparencyEnabled {
            glassBackground.effect = nil
            glassBackground.backgroundColor = .secondarySystemBackground
        } else {
            glassBackground.backgroundColor = .clear
            if #available(iOS 26.0, *) {
                glassBackground.effect = UIGlassEffect(style: .regular)
            } else {
                glassBackground.effect = UIBlurEffect(style: .systemThinMaterial)
            }
        }
    }

    private func configureButton(_ button: OwnedKeyboardButton, title: String, label: String) {
        button.keyboard = self
        button.setTitle(title, for: .normal)
        button.setTitleColor(Palette.ink, for: .normal)
        button.tintColor = Palette.ink
        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.7
        button.backgroundColor = Palette.control
        button.layer.cornerRadius = 8
        button.layer.borderColor = Palette.line.cgColor
        button.layer.borderWidth = 0.5
        button.accessibilityLabel = label
        button.accessibilityIdentifier = "key-\(label)"
        addSubview(button)
    }

    public func update(target: String?, canUndoModifier: Bool) {
        self.target = target
        self.canUndoModifier = canUndoModifier
        if ownerTouch == nil { updateIdleStatus() }
    }

    public func cancelGesture() {
        spaceCursor = SpaceCursorGesture()
        stopDeleteHold()
        // Stop a pending long press too when the keyboard rotates or changes mode.
        for recognizer in shiftButton.gestureRecognizers ?? [] {
            recognizer.isEnabled = false
            recognizer.isEnabled = true
        }
        classifier.cancel()
        ownerTouch = nil
        ownerPad?.preview = nil
        ownerPad = nil
        lastCandidate = nil
        ownerButton?.cancelTracking(with: nil)
        ownerButton = nil
        let activeTypingButtons = Array(typingTouches)
        typingTouches.removeAll()
        for button in activeTypingButtons { button.cancelTracking(with: nil) }
        updateIdleStatus()
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            cancelGesture()
            feedback = nil
        } else if #available(iOS 17.5, *) {
            // Bind feedback to the visible keyboard, including extension windows.
            feedback = UIImpactFeedbackGenerator(style: .medium, view: self)
        } else {
            feedback = UIImpactFeedbackGenerator(style: .medium)
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        glassBackground.frame = bounds
        if bounds != lastLayoutBounds || safeAreaInsets != lastSafeArea {
            cancelGesture()
            lastLayoutBounds = bounds
            lastSafeArea = safeAreaInsets
        }
        let inset: CGFloat = 6
        // Fill the keyboard surface supplied by the host. A fixed width cap
        // and extra horizontal safe-area subtraction left wide devices with
        // unused strips on both sides. Keep only the normal key-edge gutter.
        let width = bounds.width - inset * 2
        guard width > 0 else { return }
        let left = bounds.minX + inset
        let metrics = KeyboardSizing.metrics(width: width, height: bounds.height, bottomInset: safeAreaInsets.bottom)
        let compact = metrics.header == 0
        let header = metrics.header
        let bottom = metrics.bottom
        let barHeight = metrics.barHeight
        let top: CGFloat = 4
        let gap: CGFloat = 6
        helpButton.frame = CGRect(x: left + width - 30, y: top, width: 30, height: header)
        helpButton.isHidden = compact
        statusLabel.isHidden = compact
        helpButton.backgroundColor = .clear
        helpButton.layer.borderWidth = 0
        statusLabel.frame = CGRect(x: left + 2, y: top, width: width - 36, height: header)
        let barY = metrics.barY
        let padY = metrics.padY
        let padHeight = metrics.padHeight
        let reserved = metrics.reserved
        let diameter = metrics.diameter
        let circleY = padY + reserved + (padHeight - reserved - diameter) / 2
        cPad.frame = CGRect(x: left, y: circleY, width: diameter, height: diameter)
        vPad.frame = CGRect(x: left + width - diameter, y: circleY, width: diameter, height: diameter)
        cPad.isHidden = symbolMode || englishMode
        vPad.isHidden = symbolMode || englishMode
        nextKeyboardButton.isHidden = !needsNextKeyboard

        let showEnglish = englishMode && !symbolMode
        for button in letterButtons.values { button.isHidden = !showEnglish }
        for button in englishPunctuationButtons { button.isHidden = !showEnglish }
        shiftButton.isHidden = !showEnglish
        rightSpaceButton.isHidden = true
        if showEnglish {
            symbolPageButton.isHidden = true
            for button in symbolButtons { button.isHidden = true }
            languageButton.isHidden = false
            layoutEnglish(in: CGRect(x: left, y: padY, width: width, height: bounds.height - bottom - padY), compact: compact)
            return
        }

        if symbolMode {
            languageButton.isHidden = true
            layoutSymbols(in: CGRect(x: left, y: padY, width: width, height: bounds.height - bottom - padY), compact: compact)
            return
        }

        symbolPageButton.isHidden = true
        for button in symbolButtons { button.isHidden = true }
        languageButton.isHidden = false
        dismissButton.isHidden = onDismiss == nil
        var controls: [UIButton] = [modeButton, languageButton, spaceButton, deleteButton, returnButton]
        if onDismiss != nil { controls.append(dismissButton) }
        if needsNextKeyboard { controls.insert(nextKeyboardButton, at: 0) }
        let fixed = min(compact ? 52 : 48, (width - gap * CGFloat(controls.count - 1)) / CGFloat(controls.count))
        let spaceWidth = width - CGFloat(controls.count - 1) * (fixed + gap)
        var x = left
        for button in controls {
            let itemWidth = button === spaceButton ? spaceWidth : fixed
            button.frame = CGRect(x: x, y: barY, width: itemWidth, height: barHeight)
            button.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
            x += itemWidth + gap
        }
    }

    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01, isUserInteractionEnabled, bounds.contains(point) else { return nil }
        // Further fingers cannot activate a button while another contact owns input.
        if ownerTouch != nil || ownerButton != nil { return self }
        if !symbolMode && !englishMode, inputSurfaces.contains(where: { !$0.isHidden && $0.frame.contains(point) }) { return self }
        return super.hitTest(point, with: event)
    }

    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard ownerTouch == nil, ownerButton == nil, !symbolMode, !englishMode else { return }
        // Deterministic ownership when two touches enter in the same event.
        guard let touch = touches.min(by: { $0.timestamp < $1.timestamp }) else { return }
        let location = touch.location(in: self)
        guard let pad = inputSurfaces.first(where: {
            !$0.isHidden && ($0.fixedKey != nil ? $0.frame.contains(location) : AnchoredGesture.symbol(pad: $0.pad, at: location, bounds: $0.frame) != nil)
        }) else { return }
        ownerTouch = touch
        ownerPad = pad
        if let key = pad.fixedKey { classifier.begin(key: key, at: location, bounds: pad.frame) }
        else { classifier.begin(pad: pad.pad, at: location, bounds: pad.frame) }
        feedback?.prepare()
        updatePreview()
    }

    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = ownerTouch, touches.contains(touch) else { return }
        // Coalesced samples retain an excursion even when a fast move returns to its origin.
        for sample in event?.coalescedTouches(for: touch) ?? [touch] {
            classifier.move(to: sample.location(in: self))
        }
        updatePreview()
    }

    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = ownerTouch, touches.contains(touch) else { return }
        classifier.move(to: touch.location(in: self))
        // A quick reversal can be delivered only in touchesEnded. Give its
        // final candidate the same feedback as a move sample.
        updatePreview()
        let action = classifier.end(at: touch.location(in: self))
        ownerPad?.preview = nil
        ownerPad = nil
        ownerTouch = nil
        lastCandidate = nil
        // The joystick already gives feedback when its candidate changes.
        if let action { emit(action, giveFeedback: false) }
        else { statusLabel.text = "이번 움직임은 취소했어요" }
    }

    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let ownerTouch, touches.contains(ownerTouch) else { return }
        cancelGesture()
    }

    private func updatePreview() {
        guard let pad = ownerPad else { return }
        let preview = classifier.preview
        pad.selectedBase = classifier.base
        pad.preview = preview
        pad.gestureOriginInKeyboard = preview.origin
        switch preview.kind {
        case .tap, .direction:
            let candidate = classifier.candidate
            let key = pad.fixedKey ?? JoystickMapping.keys(pad.pad).first { $0.label == classifier.base }
            let hints = JoystickMapping.directions.compactMap { direction, arrow in key?.outputs[direction].map { arrow + $0 } }.joined(separator: " ")
            statusLabel.text = candidate.map { "놓으면 \($0) · \(hints)" } ?? "\(hints) · 놓으면 취소"
            if candidate != lastCandidate, candidate != nil {
                feedback?.impactOccurred()
                feedback?.prepare()
                lastCandidate = candidate
            }
        case .uncertain:
            statusLabel.text = "방향을 더 분명히 밀어 주세요 · 놓으면 취소"
        case .cancel:
            statusLabel.text = "이번 움직임은 취소됩니다"
        }
    }

    private func updateIdleStatus() {
        if symbolMode {
            statusLabel.text = "\(symbolPage + 1)/\(SymbolKeyboard.pages.count) · \(SymbolKeyboard.pageTitles[symbolPage])"
        } else if englishMode {
            statusLabel.text = english.letterCase == .locked
                ? "영어 · 대문자 고정 · ⇧를 누르면 해제"
                : "영어 · ⇧ 한 글자 대문자 · 길게 누르면 고정"
        } else {
            statusLabel.text = "ABC 영어 · 123 숫자 · ~는 ㅈ에서 아래로"
        }
    }

    private func layoutEnglish(in area: CGRect, compact: Bool) {
        let layout = EnglishLayout.make(in: area, needsGlobe: needsNextKeyboard, needsDismiss: onDismiss != nil)
        var buttons: [String: UIButton] = letterButtons.mapValues { $0 as UIButton }
        buttons.merge(["shift": shiftButton, "delete": deleteButton, "mode": modeButton,
                       "language": languageButton, "space": spaceButton, "space-right": rightSpaceButton,
                       "quote": englishPunctuationButtons[0], "period": englishPunctuationButtons[1],
                       "return": returnButton, "globe": nextKeyboardButton, "dismiss": dismissButton]) { _, new in new }
        for (key, button) in buttons {
            guard let frame = layout.frames[key] else { button.isHidden = true; continue }
            button.isHidden = false
            button.frame = frame
            button.titleLabel?.font = .systemFont(ofSize: letterButtons[key] == nil ? 15 : compact ? 19 : 22, weight: .medium)
        }
    }

    private func layoutSymbols(in area: CGRect, compact: Bool) {
        let layout = SymbolLayout.make(in: area, needsGlobe: needsNextKeyboard, needsDismiss: onDismiss != nil)
        var buttons: [String: UIButton] = ["page": symbolPageButton, "delete": deleteButton,
            "mode": modeButton, "space": spaceButton, "space-right": rightSpaceButton,
            "return": returnButton, "globe": nextKeyboardButton, "dismiss": dismissButton]
        for (index, button) in symbolButtons.enumerated() { buttons["symbol-\(index)"] = button }
        for (key, button) in buttons {
            guard let frame = layout.frames[key] else { button.isHidden = true; continue }
            button.isHidden = false
            button.frame = frame
            button.titleLabel?.font = .systemFont(ofSize: key.hasPrefix("symbol-") ? (compact ? 19 : 22) : 15, weight: .medium)
        }
    }

    private func updateSymbolKeys() {
        for (index, button) in symbolButtons.enumerated() {
            let symbol = SymbolKeyboard.pages[symbolPage][index]
            button.setTitle(symbol, for: .normal)
            button.accessibilityLabel = SymbolKeyboard.accessibilityLabel(for: symbol)
            button.accessibilityValue = symbol
        }
        let next = (symbolPage + 1) % SymbolKeyboard.pages.count
        symbolPageButton.setTitle(symbolPage == 0 ? "#+=" : "123", for: .normal)
        symbolPageButton.accessibilityLabel = "\(SymbolKeyboard.pageTitles[next]) 보기"
        symbolPageButton.accessibilityValue = "현재 \(symbolPage + 1) / \(SymbolKeyboard.pages.count) 페이지"
    }

    private func insertSymbol(at index: Int) {
        guard symbolMode, SymbolKeyboard.pages[symbolPage].indices.contains(index) else { return }
        emit(.literal(SymbolKeyboard.pages[symbolPage][index]))
    }

    private func updateEnglishKeys() {
        let upper = english.letterCase != .lower
        for (letter, button) in letterButtons {
            let shown = upper ? letter.uppercased() : letter
            button.setTitle(shown, for: .normal)
            button.accessibilityLabel = shown
        }
        let icon = english.letterCase == .locked ? "capslock.fill" : upper ? "shift.fill" : "shift"
        shiftButton.setImage(UIImage(systemName: icon), for: .normal)
        shiftButton.accessibilityValue = english.letterCase == .locked ? "대문자 고정" : upper ? "다음 한 글자 대문자" : "소문자"
        shiftButton.backgroundColor = upper ? UIColor.systemTeal.withAlphaComponent(0.2) : Palette.control
    }

    private func updateModeControls() {
        modeButton.setTitle(symbolMode ? (englishMode ? "ABC" : "한글") : "123", for: .normal)
        modeButton.accessibilityLabel = symbolMode ? (englishMode ? "영어 입력" : "한글 입력") : "숫자와 기호"
        languageButton.setTitle(englishMode ? "한글" : "ABC", for: .normal)
        languageButton.accessibilityLabel = englishMode ? "한글로 전환" : "영어로 전환"
        spaceButton.setTitle(englishMode ? "space" : "공백", for: .normal)
        rightSpaceButton.setTitle(englishMode ? "space" : "공백", for: .normal)
        updateSymbolKeys()
        updateIdleStatus()
        setNeedsLayout()
    }

    private func insertEnglish(_ letter: String) {
        guard englishMode, !symbolMode, let action = english.input(letter) else { return }
        updateEnglishKeys()
        emit(action)
    }

    @objc private func toggleLanguage() {
        cancelGesture()
        emit(.commit)
        englishMode.toggle()
        symbolMode = false
        symbolPage = 0
        english.resetShift()
        updateEnglishKeys()
        updateModeControls()
        onLanguageChange?(englishMode ? "en-US" : "ko-KR")
    }

    @objc private func toggleShift() {
        cancelGesture()
        english.toggleShift()
        updateEnglishKeys()
        updateIdleStatus()
    }

    @objc private func holdShift(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }
        english.toggleCapsLock()
        updateEnglishKeys()
        updateIdleStatus()
    }

    private func emit(_ action: KeyboardAction, giveFeedback: Bool = true) {
        if giveFeedback, action != .commit { feedback?.impactOccurred() }
        onAction?(action)
        updateIdleStatus()
    }

    fileprivate func insertEnglishUppercase(_ letter: String) {
        guard englishMode, !symbolMode, let action = english.inputUppercase(letter) else { return }
        updateEnglishKeys()
        emit(action)
    }

    fileprivate func insertEnglishFlick(_ symbol: String) {
        guard englishMode, !symbolMode else { return }
        emit(.literal(symbol))
    }

    fileprivate func acquire(_ button: OwnedKeyboardButton) -> Bool {
        guard ownerTouch == nil, ownerButton == nil else { return false }
        if (englishMode || symbolMode) && button !== deleteButton && !isSpace(button) && isIndependentTypingKey(button) {
            // Separate letter/symbol contacts may overlap. A mode/page/Shift control still
            // waits until they end so it cannot change pending key meanings.
            typingTouches.insert(button)
            feedback?.prepare()
            return true
        }
        guard typingTouches.isEmpty else { return false }
        ownerButton = button
        feedback?.prepare()
        return true
    }

    fileprivate func release(_ button: OwnedKeyboardButton) {
        if button === deleteButton { stopDeleteHold(); didRepeatDelete = false }
        if isSpace(button) { spaceCursor = SpaceCursorGesture() }
        if ownerButton === button { ownerButton = nil }
        typingTouches.remove(button)
    }

    private func isIndependentTypingKey(_ button: OwnedKeyboardButton) -> Bool {
        (symbolMode ? symbolButtons.contains { $0 === button }
            : letterButtons.values.contains { $0 === button } || englishPunctuationButtons.contains { $0 === button })
            || button === spaceButton || button === rightSpaceButton || button === deleteButton || button === returnButton
    }

    @objc private func showHelp() { onHelp?() }
    @objc private func dismissKeyboard() { cancelGesture(); onDismiss?() }
    private func isSpace(_ button: OwnedKeyboardButton) -> Bool {
        button === spaceButton || button === rightSpaceButton
    }

    fileprivate func beginSpaceDrag(_ button: OwnedKeyboardButton, at point: CGPoint) {
        if isSpace(button) { spaceCursor.begin(at: point) }
    }

    fileprivate func moveSpaceDrag(_ button: OwnedKeyboardButton, to point: CGPoint) {
        guard isSpace(button) else { return }
        let steps = spaceCursor.move(to: point)
        let lineSteps = spaceCursor.takeVerticalSteps()
        if steps != 0 { feedback?.impactOccurred(); feedback?.prepare(); onMoveCursor?(steps) }
        if lineSteps != 0 { feedback?.impactOccurred(); feedback?.prepare(); onMoveLine?(lineSteps) }
    }

    @objc private func insertSpace() {
        if !spaceCursor.suppressesSpace { emit(.literal(" ")) }
    }
    @objc private func deleteCharacter() {
        if !didRepeatDelete { emit(.delete) }
    }

    fileprivate func beginDeleteHold(_ button: OwnedKeyboardButton) {
        guard button === deleteButton else { return }
        stopDeleteHold()
        didRepeatDelete = false
        deleteHoldStarted = CACurrentMediaTime()
        lastBlockDelete = 0
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, self.window != nil else { return }
            let now = CACurrentMediaTime()
            let elapsed = now - self.deleteHoldStarted
            guard elapsed >= 0.4 else { return }
            self.didRepeatDelete = true
            if elapsed >= 2 {
                guard now - self.lastBlockDelete >= 0.3 else { return }
                self.lastBlockDelete = now
                self.emit(.deleteBlock)
            } else {
                self.emit(.delete)
            }
        }
        deleteTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    fileprivate func leaveDeleteButton(_ button: OwnedKeyboardButton) {
        if button === deleteButton { stopDeleteHold() }
    }

    private func stopDeleteHold() {
        deleteTimer?.invalidate()
        deleteTimer = nil
    }
    @objc private func insertReturn() { emit(.literal("\n")) }
    @objc private func nextSymbolPage() {
        guard symbolMode else { return }
        cancelGesture()
        symbolPage = (symbolPage + 1) % SymbolKeyboard.pages.count
        updateSymbolKeys()
        updateIdleStatus()
        setNeedsLayout()
    }
    @objc private func toggleMode() {
        cancelGesture()
        if !symbolMode { emit(.commit) }
        symbolPage = 0
        symbolMode.toggle()
        updateModeControls()
    }
}

/// UIButton retains normal iOS touch-up and globe-menu behavior, with shared ownership.
private final class OwnedKeyboardButton: UIButton, UIGestureRecognizerDelegate {
    weak var keyboard: KeyboardView?
    private var ownsTouch = false
    private var flickSymbol: String?
    private var flickOrigin = CGPoint.zero
    private var flickDirection = 0
    private var flickLetter: String?
    private let flickHint = UILabel()

    func setFlickSymbol(_ symbol: String?, letter: String) {
        flickSymbol = symbol
        flickLetter = letter
        flickHint.text = symbol
        flickHint.font = .systemFont(ofSize: 9, weight: .semibold)
        flickHint.textColor = .secondaryLabel
        flickHint.textAlignment = .right
        flickHint.isUserInteractionEnabled = false
        flickHint.isAccessibilityElement = false
        addSubview(flickHint)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        flickHint.frame = CGRect(x: max(0, bounds.width - 15), y: max(0, bounds.height - 13), width: 12, height: 12)
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // A rejected second-finger Shift touch must not later enable Caps Lock.
        ownsTouch && super.gestureRecognizerShouldBegin(gestureRecognizer)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard keyboard?.acquire(self) == true else { return }
        ownsTouch = true
        flickDirection = 0
        if let touch = touches.first { flickOrigin = touch.location(in: self) }
        super.touchesBegan(touches, with: event)
        keyboard?.beginDeleteHold(self)
        if let touch = touches.first { keyboard?.beginSpaceDrag(self, at: touch.location(in: keyboard)) }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if ownsTouch {
            if flickSymbol != nil, let touch = touches.first {
                let location = touch.location(in: self)
                let dx = location.x - flickOrigin.x, dy = location.y - flickOrigin.y
                if flickDirection == 0 { flickDirection = EnglishKeyboard.flickDirection(dx: dx, dy: dy) }
            }
            if let touch = touches.first { keyboard?.moveSpaceDrag(self, to: touch.location(in: keyboard)) }
            super.touchesMoved(touches, with: event)
            if let touch = touches.first, !bounds.contains(touch.location(in: self)) {
                keyboard?.leaveDeleteButton(self)
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard ownsTouch else { return }
        if let touch = touches.first {
            keyboard?.moveSpaceDrag(self, to: touch.location(in: keyboard))
            if flickSymbol != nil {
                let location = touch.location(in: self)
                let dx = location.x - flickOrigin.x, dy = location.y - flickOrigin.y
                if flickDirection == 0 { flickDirection = EnglishKeyboard.flickDirection(dx: dx, dy: dy) }
            }
        }
        if flickDirection != 0, let symbol = flickSymbol, let letter = flickLetter {
            super.cancelTracking(with: event)
            if flickDirection < 0 { keyboard?.insertEnglishUppercase(letter) }
            else { keyboard?.insertEnglishFlick(symbol) }
        } else {
            super.touchesEnded(touches, with: event)
        }
        ownsTouch = false
        keyboard?.release(self)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard ownsTouch else { return }
        super.touchesCancelled(touches, with: event)
        ownsTouch = false
        keyboard?.release(self)
    }

    override func cancelTracking(with event: UIEvent?) {
        super.cancelTracking(with: event)
        ownsTouch = false
        keyboard?.release(self)
    }
}

private enum Palette {
    static let ink = UIColor.label
    static let muted = UIColor.secondaryLabel
    static let control = UIColor.secondarySystemGroupedBackground.withAlphaComponent(0.88)
    static let line = UIColor.separator.withAlphaComponent(0.45)
    static let blue = UIColor.systemTeal
    static let gold = UIColor.systemOrange
}

private final class DirectionPad: UIView {
    let pad: Pad
    let fixedKey: JoystickMapping.Key?
    var performAction: ((KeyboardAction) -> Void)?
    var preview: GesturePreview? { didSet { setNeedsDisplay() } }
    var selectedBase: String?
    var gestureOriginInKeyboard = CGPoint.zero { didSet { setNeedsDisplay() } }

    init(pad: Pad, fixedKey: JoystickMapping.Key? = nil) {
        self.pad = pad
        self.fixedKey = fixedKey
        super.init(frame: .zero)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
        isAccessibilityElement = true
        accessibilityTraits = [.button]
        accessibilityIdentifier = fixedKey.map { "punctuation-" + $0.label } ?? "pad-\(pad.rawValue)"
        accessibilityLabel = fixedKey.map { "기호 " + $0.label } ?? (pad == .c ? "자음 원형 입력판" : "모음 원형 입력판")
        accessibilityHint = "글자에서 시작합니다. 동작 메뉴에서 글자와 방향을 선택하세요."
        let keys = fixedKey.map { [$0] } ?? JoystickMapping.keys(pad)
        accessibilityCustomActions = keys.flatMap { key in
            ([(Direction.tap, "탭")] + JoystickMapping.directions).compactMap { direction, arrow in
                guard let value = key.outputs[direction], let action = key.action(direction) else { return nil }
                return UIAccessibilityCustomAction(name: "\(key.label) \(arrow) \(value)") { [weak self] _ in
                    self?.performAction?(action); return self != nil
                }
            }
        }
        if pad == .v && fixedKey == nil {
            accessibilityCustomActions?.append(contentsOf: ["ㅒ", "ㅖ"].map { vowel in
                UIAccessibilityCustomAction(name: "방향 반전으로 \(vowel) 입력") { [weak self] _ in
                    self?.performAction?(.jamo(vowel)); return self != nil
                }
            })
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func accessibilityActivate() -> Bool {
        guard let action = fixedKey?.action(.tap) else { return false }
        performAction?(action); return true
    }
    private func drawKey(_ key: JoystickMapping.Key, at center: CGPoint, size: CGFloat,
                         accent: UIColor, hints: Bool, offset: CGFloat) {
        let active = preview != nil && selectedBase == key.label
        text(key.label, at: center, size: size, color: active ? accent : Palette.ink, weight: .semibold)
        guard hints else { return }
        for (direction, _) in JoystickMapping.directions {
            guard let value = key.outputs[direction] else { continue }
            let dx: CGFloat = direction == .e ? offset : direction == .w ? -offset : 0
            let dy: CGFloat = direction == .s ? offset : direction == .n ? -offset : 0
            text(value, at: CGPoint(x: center.x + dx, y: center.y + dy), size: 10, color: value.allSatisfy(\.isNumber) ? accent : Palette.muted, weight: value.allSatisfy(\.isNumber) ? .bold : .regular)
        }
    }
    override func draw(_ rect: CGRect) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        if let key = fixedKey {
            let path = UIBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 10)
            (preview == nil ? Palette.control : UIColor.systemTeal.withAlphaComponent(0.2)).setFill(); path.fill()
            Palette.line.setStroke(); path.lineWidth = 1; path.stroke()
            drawKey(key, at: CGPoint(x: bounds.midX, y: bounds.midY), size: 20,
                    accent: Palette.blue, hints: true, offset: 15)
            return
        }
        let circle = JoystickMapping.circle(in: bounds).insetBy(dx: 1, dy: 1)
        let origin = CGPoint(x: circle.midX, y: circle.midY)
        let radius = circle.width / 2
        let hub = bounds.width * JoystickMapping.hubRatio
        let ringStart = hub + JoystickMapping.hubGap
        let accent = pad == .c ? Palette.blue : Palette.gold
        let outer = UIBezierPath(ovalIn: circle)
        UIColor.secondarySystemGroupedBackground.withAlphaComponent(0.65).setFill(); outer.fill()
        accent.withAlphaComponent(0.4).setStroke(); outer.lineWidth = 1; outer.stroke()
        let keys = JoystickMapping.keys(pad)
        let ring = JoystickMapping.ringKeys(pad)
        let step = 2 * CGFloat.pi / CGFloat(ring.count)
        for (ringIndex, key) in ring.enumerated() {
            let angle = -CGFloat.pi / 2 + CGFloat(ringIndex) * step
            let start = angle - step / 2 + 0.026, end = angle + step / 2 - 0.026
            let wedge = UIBezierPath(arcCenter: origin, radius: radius - 2, startAngle: start, endAngle: end, clockwise: true)
            wedge.addArc(withCenter: origin, radius: ringStart, startAngle: end, endAngle: start, clockwise: false)
            wedge.close()
            let active = preview != nil && selectedBase == key.label
            accent.withAlphaComponent(active ? 0.24 : 0.045).setFill(); wedge.fill()
            Palette.line.setStroke(); wedge.lineWidth = 0.5; wedge.stroke()
            guard let index = keys.firstIndex(where: { $0.label == key.label }) else { continue }
            let center = JoystickMapping.center(pad: pad, index: index, bounds: bounds)
            drawKey(key, at: center, size: bounds.width < 180 ? 19 : 23,
                    accent: accent, hints: true, offset: min(19, bounds.width * 0.105))
        }
        let centerDisc = UIBezierPath(ovalIn: CGRect(x: origin.x - hub, y: origin.y - hub, width: hub * 2, height: hub * 2))
        let active = preview != nil && selectedBase == JoystickMapping.centralKey(pad)?.label
        (active ? accent.withAlphaComponent(0.24) : UIColor.tertiarySystemGroupedBackground.withAlphaComponent(0.85)).setFill()
        centerDisc.fill(); accent.withAlphaComponent(0.5).setStroke(); centerDisc.lineWidth = 1; centerDisc.stroke()
        if let key = JoystickMapping.centralKey(pad) {
            drawKey(key, at: origin, size: 24, accent: accent, hints: true, offset: min(19, hub - 6))
        }
    }
    private func text(_ string: String, at center: CGPoint, size: CGFloat, color: UIColor, weight: UIFont.Weight = .regular) {
        let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color]
        let extent = (string as NSString).size(withAttributes: attributes)
        (string as NSString).draw(at: CGPoint(x: center.x - extent.width / 2, y: center.y - extent.height / 2), withAttributes: attributes)
    }
}
