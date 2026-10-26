import UIKit

/// A containing app for installation guidance and an offline keyboard practice area.
final class HostViewController: UIViewController {
    private var model = ThreePadModel()
    private let keyboard = KeyboardView()
    private let scenery = ScenicBackdropView()
    private let titleLabel = UILabel()
    private let mode = UISegmentedControl(items: ["앱 안에서 연습", "설치한 키보드 테스트"])
    private let guidance = UILabel()
    private let output = UITextView()
    private let systemInput = UITextView()
    private let topBar = UIStackView()
    private let body = UIStackView()
    private var keyboardHeight: NSLayoutConstraint!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        scenery.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scenery)
        NSLayoutConstraint.activate([
            scenery.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scenery.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scenery.topAnchor.constraint(equalTo: view.topAnchor),
            scenery.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        titleLabel.text = "세 판 · 한글·영어 키보드"
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true

        let helpButton = UIButton(type: .system)
        helpButton.setTitle("설치 안내", for: .normal)
        helpButton.addTarget(self, action: #selector(showInstallation), for: .touchUpInside)
        topBar.axis = .horizontal
        topBar.alignment = .center
        topBar.addArrangedSubview(titleLabel)
        topBar.addArrangedSubview(helpButton)
        helpButton.setContentHuggingPriority(.required, for: .horizontal)

        mode.selectedSegmentIndex = 0
        mode.accessibilityIdentifier = "practice-mode"
        mode.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        guidance.font = .preferredFont(forTextStyle: .caption1)
        guidance.adjustsFontForContentSizeCategory = true
        guidance.textColor = .secondaryLabel
        guidance.numberOfLines = 2

        configureTextView(output)
        output.isEditable = false
        output.accessibilityLabel = "연습 입력 결과"
        output.accessibilityIdentifier = "practice-output"
        output.text = ""
        configureTextView(systemInput)
        systemInput.accessibilityLabel = "설치한 키보드 테스트 입력란"
        systemInput.accessibilityIdentifier = "system-test-field"
        systemInput.autocorrectionType = .no
        systemInput.spellCheckingType = .no
        systemInput.smartQuotesType = .no
        systemInput.smartDashesType = .no
        systemInput.isHidden = true

        keyboard.needsNextKeyboard = false
        keyboard.accessibilityIdentifier = "practice-keyboard"
        keyboard.onAction = { [weak self] action in
            guard let self else { return }
            _ = self.model.apply(action)
            self.refreshPractice()
        }
        keyboard.onHelp = { [weak self] in self?.showGestureHelp() }

        body.axis = .vertical
        body.spacing = 8
        body.translatesAutoresizingMaskIntoConstraints = false
        [topBar, mode, guidance, output, systemInput, keyboard].forEach(body.addArrangedSubview)
        view.addSubview(body)
        keyboardHeight = keyboard.heightAnchor.constraint(equalToConstant: 320)
        // A stack view temporarily applies a zero height to a hidden arranged view.
        keyboardHeight.priority = .defaultHigh
        keyboardHeight.isActive = true
        for textView in [output, systemInput] {
            let minimumHeight = textView.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
            minimumHeight.priority = .defaultHigh
            minimumHeight.isActive = true
        }
        NSLayoutConstraint.activate([
            body.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            body.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            body.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            body.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -8)
        ])
        refreshPractice()
        modeChanged()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let isCompact = view.bounds.width > view.bounds.height
        keyboardHeight.constant = KeyboardSizing.contentHeight(screenHeight: view.bounds.height, bottomInset: 0)
        guidance.isHidden = isCompact
        topBar.isHidden = isCompact
    }

    override func viewWillTransition(to size: CGSize,
                                     with coordinator: UIViewControllerTransitionCoordinator) {
        keyboard.cancelGesture()
        super.viewWillTransition(to: size, with: coordinator)
    }

    private func configureTextView(_ textView: UITextView) {
        textView.font = .preferredFont(forTextStyle: .title2)
        textView.adjustsFontForContentSizeCategory = true
        textView.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 0.08, alpha: 0.30)
                : UIColor(white: 1, alpha: 0.26)
        }
        textView.layer.cornerRadius = 14
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 10, bottom: 12, right: 10)
        textView.setContentHuggingPriority(.defaultLow, for: .vertical)
    }

    private func refreshPractice() {
        output.text = model.text
        if !output.text.isEmpty {
            output.scrollRangeToVisible(NSRange(location: (output.text as NSString).length, length: 0))
        }
        keyboard.update(target: model.target, canUndoModifier: model.canUndoModifier)
    }

    @objc private func modeChanged() {
        keyboard.cancelGesture()
        let isPractice = mode.selectedSegmentIndex == 0
        if isPractice { systemInput.resignFirstResponder() }
        output.isHidden = !isPractice
        keyboard.isHidden = !isPractice
        systemInput.isHidden = isPractice
        guidance.text = isPractice
            ? "ABC는 영어, 한글은 원형 자판입니다. 123에서 숫자·기호를 입력하세요."
            : "입력란을 누르고 지구본 키에서 ‘세 판’을 선택하세요. 먼저 설정에서 키보드를 추가해야 합니다."
        if !isPractice { systemInput.becomeFirstResponder() }
    }

    @objc private func showInstallation() {
        let alert = UIAlertController(
            title: "아이폰에 키보드 추가",
            message: "1. 설정 → 일반 → 키보드 → 키보드로 이동합니다.\n2. ‘새로운 키보드 추가’에서 ‘세 판’을 선택합니다.\n3. 입력 화면의 지구본 키를 길게 눌러 ‘세 판’을 선택합니다.\n\n‘전체 접근 허용’은 필요하지 않습니다. 암호 입력란과 일부 앱에서는 iOS가 기본 키보드를 사용합니다.",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "확인", style: .default))
        present(alert, animated: true)
    }

    private func showGestureHelp() {
        let alert = UIAlertController(
            title: "세 판 사용법",
            message: "왼쪽 자음 원 · 오른쪽 모음 원\n\nㅇ: 탭 ㅇ / 좌우 ㅎ\nㅈ: 탭 ㅈ / 위 ㅉ / 좌우 ㅊ / 아래 ~\nㄴ: 탭 ㄴ / 아래 ㄷ / 위 ㄸ / 좌우 ㅌ\nㅣ: 탭 ㅣ / 위 ㅗ / 아래 ㅜ / 왼쪽 ㅓ / 오른쪽 ㅏ\n\n··는 방향으로만 입력합니다. ㅒ는 ㅑ+ㅣ, ㅖ는 ㅕ+ㅣ로 입력합니다.\n\n영어는 하단 ABC로 전환합니다. ⇧는 한 글자 대문자, 길게 누르면 대문자 고정입니다. 넓은 화면에서는 QWERTY가 좌우로 나뉩니다. 한글 버튼으로 돌아옵니다.\n\n숫자와 기호는 하단 123에서 입력합니다. 첫 페이지에는 0–9와 ~가 있습니다. #+=로 괄호·계산·통화 페이지를 엽니다. 123으로 첫 페이지에 돌아옵니다. 회전해도 페이지와 키 순서는 유지됩니다. 넓은 화면은 중앙 여백과 양쪽 공백 키를 제공합니다.\n\n기호: . 탭 마침표 / 왼쪽 쉼표 / 위·아래 따옴표. ? 탭 물음표 / 위 느낌표. / 탭 슬래시 / 왼쪽 @. 중앙은 ㅇ·ㅣ입니다. 원 밖과 중앙 둘레의 좁은 경계는 입력하지 않습니다. 손을 떼기 전까지 시작 글자가 고정됩니다.",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "확인", style: .default))
        present(alert, animated: true)
    }
}
