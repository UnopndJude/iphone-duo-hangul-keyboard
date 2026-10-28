import UIKit

final class KeyboardViewController: UIInputViewController {
    private let keyboard = KeyboardView()
    private let session = DocumentSession()
    private var heightConstraint: NSLayoutConstraint?
    private var lastLayoutSize = CGSize.zero
    private lazy var document = ProxyDocument { [weak self] in self?.textDocumentProxy }

    override func viewDidLoad() {
        super.viewDidLoad()
        primaryLanguage = "ko-KR"
        view.backgroundColor = .clear
        view.isOpaque = false
        keyboard.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(keyboard)
        NSLayoutConstraint.activate([
            keyboard.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboard.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keyboard.topAnchor.constraint(equalTo: view.topAnchor),
            keyboard.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
        let height = view.heightAnchor.constraint(equalToConstant: 320)
        height.priority = .defaultHigh
        height.isActive = true
        heightConstraint = height
        keyboard.onAction = { [weak self] action in
            guard let self else { return }
            self.session.apply(action, to: self.document)
            self.refresh()
        }
        keyboard.onMoveCursor = { [weak self] steps in
            guard let self else { return }
            self.session.moveCursor(by: steps, in: self.document)
            self.refresh()
        }
        keyboard.onMoveLine = { [weak self] steps in
            guard let self else { return }
            self.session.moveLine(by: steps, in: self.document)
            self.refresh()
        }
        keyboard.onDismiss = { [weak self] in
            guard let self else { return }
            self.session.finish(in: self.document)
            self.dismissKeyboard()
        }
        keyboard.onHelp = { [weak self] in self?.showHelp() }
        keyboard.onLanguageChange = { [weak self] language in self?.primaryLanguage = language }
        keyboard.nextKeyboardButton.addTarget(self, action: #selector(changeInputMode(_:event:)), for: .allTouchEvents)
        refresh()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        session.synchronize(with: document)
        refresh()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Use the active display, never the keyboard's own height (which would
        // create a shrinking feedback loop during layout).
        let screenHeight = view.window?.windowScene?.screen.bounds.height ?? 844
        let bottom = view.safeAreaInsets.bottom
        let desiredHeight = KeyboardSizing.contentHeight(screenHeight: screenHeight, bottomInset: bottom) + bottom
        if heightConstraint?.constant != desiredHeight { heightConstraint?.constant = desiredHeight }
        if lastLayoutSize != view.bounds.size {
            keyboard.cancelGesture()
            lastLayoutSize = view.bounds.size
        }
        keyboard.needsNextKeyboard = needsInputModeSwitchKey
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        if session.synchronize(with: document) { keyboard.cancelGesture() }
        refresh()
    }

    override func selectionWillChange(_ textInput: UITextInput?) {
        super.selectionWillChange(textInput)
        // Our own insertText may also send this notification. Wait for the
        // resulting context before cancelling another thumb's pending key.
    }

    override func selectionDidChange(_ textInput: UITextInput?) {
        super.selectionDidChange(textInput)
        if session.synchronize(with: document) { keyboard.cancelGesture() }
        refresh()
    }

    override func viewWillDisappear(_ animated: Bool) {
        session.finish(in: document)
        keyboard.cancelGesture()
        super.viewWillDisappear(animated)
    }

    @objc private func changeInputMode(_ sender: UIButton, event: UIEvent) {
        session.finish(in: document)
        handleInputModeList(from: sender, with: event)
    }

    private func refresh() {
        keyboard.update(target: session.target, canUndoModifier: session.canUndoModifier)
        keyboard.needsNextKeyboard = needsInputModeSwitchKey
        switch textDocumentProxy.returnKeyType ?? .default {
        case .go: keyboard.returnKeyTitle = "이동"
        case .search, .google, .yahoo: keyboard.returnKeyTitle = "검색"
        case .next: keyboard.returnKeyTitle = "다음"
        case .send: keyboard.returnKeyTitle = "전송"
        case .done: keyboard.returnKeyTitle = "완료"
        case .join: keyboard.returnKeyTitle = "연결"
        default: keyboard.returnKeyTitle = "줄바꿈"
        }
    }

    private func showHelp() {
        session.finish(in: document)
        let help = UIAlertController(title: "한글·영어 입력 방법", message: "왼쪽 원은 자음, 오른쪽 원은 모음입니다. 원 안의 글자에서 시작하세요.\n\nㅇ: 탭 ㅇ / 좌우 ㅎ / 위 6 / 아래 7\nㅈ: 탭 ㅈ / 위 ㅉ / 좌우 ㅊ / 아래 ~\nㄴ: 탭 ㄴ / 아래 ㄷ / 위 ㄸ / 좌우 ㅌ\nㅣ: 탭 ㅣ / 오른쪽 ㅏ / 왼쪽 ㅓ / 위 ㅗ / 아래 ㅜ\n\n··는 방향으로만 입력합니다. ㅒ: ·· 또는 ㅡ에서 오른쪽으로 밀고 손을 떼지 않은 채 왼쪽으로 되돌리기. ㅖ: 왼쪽으로 밀고 오른쪽으로 되돌리기. ㅑ·ㅕ 후 가운데 ㅣ를 탭해도 됩니다.\n\n영어는 하단 ABC로 전환합니다. 글자를 위로 밀면 대문자, 아래로 밀면 키 오른쪽 아래에 표시된 숫자·기호가 입력됩니다. ⇧는 한 글자 대문자, 길게 누르면 대문자 고정입니다. 넓은 화면에서는 QWERTY가 좌우로 나뉩니다. 한글 버튼으로 돌아옵니다.\n\n자음 원의 빈 방향으로 숫자를 입력합니다. ㄹ 위 1 / 왼쪽 2 / 오른쪽 3 / 아래 4, ㄱ 아래 5, ㅇ 위 6 / 아래 7, ㅅ 왼쪽 8 / 오른쪽 9 / 아래 0. 123에서도 입력합니다. ~도 123 첫 페이지에서 고를 수 있습니다.\n\n모음 원에서 모음과 기호가 번갈아 배치됩니다. 기호: . 탭 마침표 / 왼쪽 쉼표 / 오른쪽 _ / 위·아래 따옴표. ? 탭 물음표 / 위 느낌표 / 오른쪽 -. / 탭 슬래시 / 왼쪽 @ / 오른쪽 =. 중앙은 ㅇ·ㅣ입니다. 원 밖과 중앙 둘레의 좁은 경계에서는 시작할 수 없습니다. 시작한 뒤에는 길게 밀어도 입력됩니다. ··와 ㅡ의 좌우 반전은 ㅒ·ㅖ를 입력합니다. 다른 동작은 시작점으로 돌아와 놓으면 취소합니다.", preferredStyle: .alert)
        help.addAction(UIAlertAction(title: "닫기", style: .default))
        present(help, animated: true)
    }
}

/// Resolve the proxy every time; UIKit can change it when the host field changes.
private final class ProxyDocument: KeyboardDocument {
    private let resolve: () -> (any UITextDocumentProxy)?
    private let unavailableID = UUID()
    init(_ resolve: @escaping () -> (any UITextDocumentProxy)?) { self.resolve = resolve }
    var identifier: UUID { resolve()?.documentIdentifier ?? unavailableID }
    var before: String? { resolve()?.documentContextBeforeInput }
    var after: String? { resolve()?.documentContextAfterInput }
    var selected: String? { resolve()?.selectedText }
    func setMarkedText(_ text: String, selectedRange: NSRange) { resolve()?.setMarkedText(text, selectedRange: selectedRange) }
    func unmarkText() { resolve()?.unmarkText() }
    func insertText(_ text: String) { resolve()?.insertText(text) }
    func adjustTextPosition(byCharacterOffset offset: Int) { resolve()?.adjustTextPosition(byCharacterOffset: offset) }
    func deleteBackward() { resolve()?.deleteBackward() }
}
