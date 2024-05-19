import UIKit
import CoreHaptics
import SwiftUI

class KeyCap: UIButton, UIInputViewAudioFeedback, UITextInputTraits {
    enum KeyType: Equatable {
        case character
        case space
        case backspace
        case custom(() -> Void)

        static func == (lhs: KeyCap.KeyType, rhs: KeyCap.KeyType) -> Bool {
            switch (lhs, rhs) {
            case (.character, .character), (.space, .space), (.backspace, .backspace):
                return true
            case (.custom(_), .custom(_)):
                // 클로저 비교는 가능하지 않으므로, 동일성을 확인할 수 있는 다른 방법이 필요
                // 예: 클로저를 감싸는 객체의 identity를 비교
                return false
            default:
                return false
            }
        }
    }

    var defaultCharacter: String
    var slideUpCharacter: String?
    var slideDownCharacter: String?
    var slideLeftCharacter: String?
    var slideRightCharacter: String?
    var slideUpRightCharacter: String?
    var slideDownLeftCharacter: String?
    var slideLeftRightCharacter: String?
    var slideRightLeftCharacter: String?
    var keyType: KeyType
    private var deleteTimer: Timer?
    var currentHangul: HangulMaker?
    private var slideUpLabel: UILabel!
    private var slideDownLabel: UILabel!
    private var slideLeftLabel: UILabel!
    private var slideRightLabel: UILabel!
    var enableInputClicksWhenVisible: Bool {
        return true
    }
    weak var delegate: KeyboardViewControllerDelegate?
    
    init(defaultCharacter: String, slideUpCharacter: String? = nil, slideDownCharacter: String? = nil, slideLeftCharacter: String? = nil, slideRightCharacter: String? = nil,slideUpRightCharacter: String? = nil, slideDownLeftCharacter: String? = nil, slideLeftRightCharacter: String? = nil, slideRightLeftCharacter: String? = nil, keyType: KeyType = .character) {
        self.defaultCharacter = defaultCharacter
        self.slideUpCharacter = slideUpCharacter
        self.slideDownCharacter = slideDownCharacter
        self.slideLeftCharacter = slideLeftCharacter
        self.slideRightCharacter = slideRightCharacter
        self.slideUpRightCharacter = slideUpRightCharacter
        self.slideDownLeftCharacter = slideDownLeftCharacter
        self.slideLeftRightCharacter = slideLeftRightCharacter
        self.slideRightLeftCharacter = slideRightLeftCharacter

        self.keyType = keyType
        super.init(frame: .zero)
        self.setupButton()
    }

    required init?(coder: NSCoder) {
        self.defaultCharacter = ""
        self.slideUpCharacter = nil
        self.slideDownCharacter = nil
        self.slideLeftCharacter = nil
        self.slideRightCharacter = nil
        self.slideUpRightCharacter = nil
        self.slideDownLeftCharacter = nil
        self.slideLeftRightCharacter = nil
        self.slideRightLeftCharacter = nil
        self.keyType = .character
        super.init(coder: coder)
        self.setupButton()
    }

    private var initialTouchPoint: CGPoint?
    private var intermediateDirection: UISwipeGestureRecognizer.Direction?
    private var panGesture: UIPanGestureRecognizer!
    private var isDualDrag = false
    private var hasInsertedText = false
    private var lastCharacter: String?
    var inputText: String?
    private var temporaryLabel: UILabel?
    private let thresholdDistance: CGFloat = 5.0  // 슬라이드 감도
    private let cursorThreshold: CGFloat = 10
    private var pendingDualSwipe: (UISwipeGestureRecognizer.Direction, UISwipeGestureRecognizer.Direction)? // 플래그 변경
    private var repeatTimer: Timer?
    private var lastDirection: String?
    private var lastMoveAmount: Int?
    private var accumulatedTranslation: CGFloat = 0  // 누적 이동 거리
    private func setupButton() {
        switch keyType {
        case .character, .custom(_):
            self.setTitle(defaultCharacter, for: .normal)
        case .space:
            self.setTitle("␣", for: .normal)
        case .backspace:
            self.setTitle("⌫", for: .normal)
        }
        self.backgroundColor = .systemGray2
        self.translatesAutoresizingMaskIntoConstraints = false
        setupSlideLabels()
        self.addTarget(self, action: #selector(keyPressed), for: .touchUpInside)
        self.addTarget(self, action: #selector(touchDown), for: .touchDown)
        self.addTarget(self, action: #selector(touchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])

        setupDragGesture()
        setupLongPressGesture()
    }
    @objc private func touchDown() {
        self.backgroundColor = .systemGray4 // 터치 시 색상
    }

    @objc private func touchUp() {
        switch keyType {
        case .backspace:
            self.backgroundColor = .systemGray2 // 백스페이스 버튼의 기본 색상
        case .space:
            self.backgroundColor = .white // 스페이스 버튼의 기본 색상
        case .custom(_):
            self.backgroundColor = .systemGray2 // 커스텀 버튼의 기본 색상
        default:
            self.backgroundColor = .white// 일반 문자 버튼의 기본 색상
            
        }
    }
    private func setupSlideLabels() {
           slideUpLabel = createSlideLabel(with: slideUpCharacter)
           slideDownLabel = createSlideLabel(with: slideDownCharacter)
           slideLeftLabel = createSlideLabel(with: slideLeftCharacter)
           slideRightLabel = createSlideLabel(with: slideRightCharacter)

           // Add labels to the button
           addSubview(slideUpLabel)
           addSubview(slideDownLabel)
           addSubview(slideLeftLabel)
           addSubview(slideRightLabel)
       }

       private func createSlideLabel(with text: String?) -> UILabel {
           let label = UILabel()
           label.text = text
           label.textAlignment = .center
           label.font = UIFont.systemFont(ofSize: 12)
           label.textColor = UIColor.gray.withAlphaComponent(0.5)
           label.translatesAutoresizingMaskIntoConstraints = true
           return label
       }

    override func layoutSubviews() {
            super.layoutSubviews()
            slideUpLabel.frame = CGRect(x: bounds.midX - 10, y: -4, width: 20, height: 20)
            slideDownLabel.frame = CGRect(x: bounds.midX - 10, y: bounds.height-17, width: 20, height: 20)
            slideLeftLabel.frame = CGRect(x: 5, y: bounds.midY - 10, width: 20, height: 20)
            slideRightLabel.frame = CGRect(x: bounds.width-23, y: bounds.midY - 10, width: 20, height: 20)
        }
    
    private func setupDragGesture() {
        panGesture = UIPanGestureRecognizer(target: self, action: #selector(handleDrag(_:)))
        self.addGestureRecognizer(panGesture)
    }
    private func setupLongPressGesture() {
            let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
            longPressGesture.minimumPressDuration = 0.5 // 길게 눌렀을 때를 인식하는 시간 (0.5초)
            self.addGestureRecognizer(longPressGesture)
        }

    @objc private func handleDrag(_ gesture: UIPanGestureRecognizer) {
        let touchPoint = gesture.location(in: self)
        
        switch gesture.state {
        case .began:
            initialTouchPoint = touchPoint
            intermediateDirection = nil
            isDualDrag = false
            hasInsertedText = false
            pendingDualSwipe = nil
            lastDirection = nil
            accumulatedTranslation = 0
            
        case .changed:
            guard let initialPoint = initialTouchPoint, !hasInsertedText else { return }
            let deltaX = touchPoint.x - initialPoint.x
            let deltaY = touchPoint.y - initialPoint.y
            
            let absDeltaX = abs(deltaX)
            let absDeltaY = abs(deltaY)
            let translation = gesture.translation(in: self).x
            let deltaDirection = translation > 0 ? "right" : "left"
            accumulatedTranslation += translation
            
            if intermediateDirection == nil {
                // 첫 번째 방향 결정
                if absDeltaX > absDeltaY && absDeltaX > thresholdDistance {
                    intermediateDirection = (deltaX > 0 ? .right : .left)
                } else if absDeltaY > thresholdDistance {
                    intermediateDirection = (deltaY > 0 ? .down : .up)
                }
            } else if keyType == .backspace {
                handleBackspaceSwipe(gesture: gesture)
            } else if keyType == .space {
                handleSpaceSwipe(translation: translation, gesture:  gesture)
            } else {
                // 두 번째 방향 결정
                let newDirection: UISwipeGestureRecognizer.Direction
                if absDeltaX > absDeltaY && absDeltaX > thresholdDistance {
                    newDirection = (deltaX > 0 ? .right : .left)
                } else if absDeltaY > thresholdDistance {
                    newDirection = (deltaY > 0 ? .down : .up)
                } else {
                    return
                }
                
                if newDirection != intermediateDirection {
                    pendingDualSwipe = (intermediateDirection!, newDirection)
                    isDualDrag = true
                    showSlideCharacterLabel(character: getCharacterForDualSwipe(firstDirection: intermediateDirection!, secondDirection: newDirection))
                } else {
                    showSlideCharacterLabel(character: getCharacterForDirection(direction: newDirection))
                }
            }
            
        case .ended, .cancelled:
            if let dualSwipeDirections = pendingDualSwipe {
                handleDualSwipe(firstDirection: dualSwipeDirections.0, secondDirection: dualSwipeDirections.1)
            } else if let direction = intermediateDirection {
                handleSingleSwipe(direction: direction)
            }
            
            if keyType == .backspace {
                stopRepeatTimer()
            }
            
            if keyType == .space {
                resetGestureState()
            }
            
            intermediateDirection = nil
            initialTouchPoint = nil
            isDualDrag = false
            pendingDualSwipe = nil
            hideSlideCharacter()
            
        default:
            break
        }
    }

    private func handleBackspaceSwipe(gesture: UIPanGestureRecognizer) {
        if intermediateDirection == .down {
            if gesture.state == .changed {
                startRepeatTimer()
            }
        }
    }

    private func handleSpaceSwipe(translation: CGFloat, gesture: UIPanGestureRecognizer) {
        while abs(accumulatedTranslation) >= cursorThreshold {
            let cursorOffset = accumulatedTranslation > 0 ? 1 : -1
            moveCursor(direction: cursorOffset)
            accumulatedTranslation -= CGFloat(cursorOffset) * cursorThreshold
        }
        
        lastDirection = translation > 0 ? "right" : "left"
        gesture.setTranslation(.zero, in: self)
    }

    private func resetGestureState() {
        accumulatedTranslation = 0
        lastDirection = nil
        initialTouchPoint = nil
        intermediateDirection = nil
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            switch keyType {
            case .backspace:
                startDeleteTimer()
            case .character:
                break
            case .space:
                break
            case .custom(_):
                break
            }

        case .ended, .cancelled:
            // 손을 뗄 때 타이머 중지
            stopDeleteTimer()
        default:
            break
        }
    }
    private func startRepeatTimer() {
        
        stopRepeatTimer() // Ensure any existing timer is stopped
        repeatTimer = Timer.scheduledTimer(timeInterval: 0.3, target: self, selector: #selector(deleteWordRepeatedly), userInfo: nil, repeats: true)
    }

    private func stopRepeatTimer() {
        repeatTimer?.invalidate()
        repeatTimer = nil
    }

    @objc private func deleteWordRepeatedly() {
        UIDevice.current.playInputClick()
        vibrateDevice()
        deleteWord()
    }

        private func startDeleteTimer() {
            deleteTimer = Timer.scheduledTimer(timeInterval: 0.07, target: self, selector: #selector(deleteCharacter), userInfo: nil, repeats: true)
        }

        private func stopDeleteTimer() {
            deleteTimer?.invalidate()
            deleteTimer = nil
        }

        @objc private func deleteCharacter() {
            UIDevice.current.playInputClick()
            vibrateDevice()
            deleteText()
        }
    private func handleSingleSwipe(direction: UISwipeGestureRecognizer.Direction) {
        UIDevice.current.playInputClick()
        vibrateDevice()
        var characterToInsert: String? = nil

        switch direction {
        case .up:
            switch keyType {
        case .backspace:
            
           deleteText()

           default:
               characterToInsert = slideUpCharacter
           }
        case .down:
            switch keyType {
                case .backspace:
                                
                   deleteWord()

                   default:
                       characterToInsert = slideDownCharacter
                   }
        case .left:
            characterToInsert = slideLeftCharacter
        case .right:
            characterToInsert = slideRightCharacter
        default:
            break
        }

        if let character = characterToInsert, !hasInsertedText {
            print("Inserted1")
            insertText(character)
            hasInsertedText = true
            lastCharacter = character
            showSlideCharacterLabel(character: character)
        }
    }

    private func handleDualSwipe(firstDirection: UISwipeGestureRecognizer.Direction, secondDirection: UISwipeGestureRecognizer.Direction) {
        UIDevice.current.playInputClick()
        vibrateDevice()
        var characterToInsert: String? = nil

        switch (firstDirection, secondDirection) {
        case (.up, .right):
            characterToInsert = slideUpRightCharacter
        case (.down, .left):
            characterToInsert = slideDownLeftCharacter
        case (.left, .right):
            characterToInsert = slideLeftRightCharacter
        case (.right, .left):
            characterToInsert = slideRightLeftCharacter
        default:
            break
        }

        if let character = characterToInsert, !hasInsertedText {
            print("Inserted2")
            insertText(character)
            hasInsertedText = true
            lastCharacter = character
            showSlideCharacterLabel(character: character)
        }
    }
    private func getCharacterForDirection(direction: UISwipeGestureRecognizer.Direction) -> String? {
        switch direction {
        case .up:
            return slideUpCharacter
        case .down:
            return slideDownCharacter
        case .left:
            return slideLeftCharacter
        case .right:
            return slideRightCharacter
        default:
            return nil
        }
    }
    private func showSlideCharacter(direction: UISwipeGestureRecognizer.Direction) {
        var character: String? = nil

        switch direction {
        case .up:
            character = slideUpCharacter
        case .down:
            character = slideDownCharacter
        case .left:
            character = slideLeftCharacter
        case .right:
            character = slideRightCharacter
        default:
            character = nil
        }

        showSlideCharacterLabel(character: character)
    }

    private func showDualSlideCharacter(char: String) {
        showSlideCharacterLabel(character: char)
    }
    private func getCharacterForDualSwipe(firstDirection: UISwipeGestureRecognizer.Direction, secondDirection: UISwipeGestureRecognizer.Direction) -> String? {
            switch (firstDirection, secondDirection) {
            case (.up, .right):
                return slideUpRightCharacter
            case (.down, .left):
                return slideDownLeftCharacter
            case (.left, .right):
                return slideLeftRightCharacter
            case (.right, .left):
                return slideRightLeftCharacter
            default:
                return nil
            }
        }
    private func showSlideCharacterLabel(character: String?) {
        if let char = character {
            if temporaryLabel == nil {
                temporaryLabel = UILabel()
                temporaryLabel?.font = UIFont.systemFont(ofSize: 22)
                temporaryLabel?.textAlignment = .center
                temporaryLabel?.backgroundColor = UIColor.white.withAlphaComponent(1)
                temporaryLabel?.layer.cornerRadius = 5
                temporaryLabel?.layer.masksToBounds = true
                addSubview(temporaryLabel!)
            }

            temporaryLabel?.text = char
            temporaryLabel?.frame = CGRect(
                x: self.bounds.midX - 20,
                y: self.bounds.minY - 0,
                width: 40,
                height: 40
            )
            temporaryLabel?.isHidden = false
        }
    }

    private func hideSlideCharacter() {
        temporaryLabel?.isHidden = true
    }

    @objc func keyPressed() {
        UIDevice.current.playInputClick()
        vibrateDevice()

        switch keyType {
        case .character:
            insertText(defaultCharacter)
            delegate?.updateDecomposableState(isDecomposable: true)
        case .backspace:
            deleteText()
        case .space:
            insertSpace(defaultCharacter)
            delegate?.updateDecomposableState(isDecomposable: false)
        case .custom(let action):
            action()
        }

        hideSlideCharacter()
    }
    private func moveCursor(direction offset: Int) {
        guard let keyboardVC = findKeyboardViewController() else { return }
        keyboardVC.textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
        UIDevice.current.playInputClick()
        vibrateDevice()
        
    }
    
    private func findKeyboardViewController() -> KeyboardViewController? {
        var nextResponder: UIResponder? = self
        while let responder = nextResponder {
            if let keyboardVC = responder as? KeyboardViewController {
                return keyboardVC
            }
            nextResponder = responder.next
        }
        return nil
    }

    fileprivate func insertText(_ text: String) {
            guard !text.isEmpty else { return }
            var nextResponder: UIResponder? = self
            while let responder = nextResponder {
                if let inputViewController = responder as? KeyboardViewController {
                    inputViewController.processInput(text)
                    break
                }
                nextResponder = responder.next
            }
        }
        fileprivate func deleteText() {
            var nextResponder: UIResponder? = self
            while let responder = nextResponder {
                if let inputViewController = responder as? KeyboardViewController {
                    inputViewController.deleteBackward()
                    
                    break
                }
                nextResponder = responder.next
            }
        }

    fileprivate func insertSpace(_ text: String) {
            guard !text.isEmpty else { return }
            var nextResponder: UIResponder? = self
            while let responder = nextResponder {
                if let inputViewController = responder as? KeyboardViewController {
                    inputViewController.processInput(" ")
                    
                    break
                }
                nextResponder = responder.next
            }
        }

        fileprivate func deleteAll() {
            var nextResponder: UIResponder? = self
            while let responder = nextResponder {
                if let inputViewController = responder as? KeyboardViewController {
                    inputViewController.deleteAllText()
                    break
                }
                nextResponder = responder.next
            }
        }

        fileprivate func deleteWord() {
            var nextResponder: UIResponder? = self
            while let responder = nextResponder {
                if let inputViewController = responder as? KeyboardViewController {
                    inputViewController.deleteWord()
                    break
                }
                nextResponder = responder.next
            }
        }

        fileprivate func deleteLine() {
            var nextResponder: UIResponder? = self
            while let responder = nextResponder {
                if let inputViewController = responder as? KeyboardViewController {
                    inputViewController.deleteLine()
                    break
                }
                nextResponder = responder.next
            }
        }
    private func vibrateDevice() {
        let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        }
}

import UIKit
protocol KeyboardViewControllerDelegate: AnyObject {
    func updateDecomposableState(isDecomposable: Bool)
    func requestDecomposableState() -> Bool
    func requestPreviousCharacter() -> Character?
    func requestJustPreviousCharacter() -> Character?
}

extension KeyboardViewController: KeyboardViewControllerDelegate {
    func updateDecomposableState(isDecomposable: Bool) {
            self.isDecomposable = isDecomposable
            print("Decomposable state updated to: \(self.isDecomposable)")
        }
    
    func requestDecomposableState() -> Bool {
        return isDecomposable
    }

    func requestPreviousCharacter() -> Character? {
        guard let proxy = textDocumentProxy as? UITextDocumentProxy,
              let documentContext = proxy.documentContextBeforeInput, !documentContext.isEmpty else {
            return nil
        }
        
        // 커서가 시작 부분에 있을 때 예외 처리
        let endIndex = documentContext.endIndex
        guard endIndex > documentContext.startIndex else {
            return " "
        }
        
        let indexBeforeCursor = documentContext.index(before: endIndex)
        
        // 문서의 첫 번째 문자인지 확인
        guard indexBeforeCursor != documentContext.startIndex else {
            return nil // 첫 번째 문자일 경우 nil 반환
        }
        
        let realTextIndex = documentContext.index(before: indexBeforeCursor)
        return documentContext[realTextIndex]
    }
    func requestJustPreviousCharacter() -> Character? {
        guard let proxy = textDocumentProxy as? UITextDocumentProxy,
              let documentContext = proxy.documentContextBeforeInput, !documentContext.isEmpty else {
            return nil
        }
        
        // 커서가 시작 부분에 있을 때 예외 처리
        let endIndex = documentContext.endIndex
        guard endIndex > documentContext.startIndex else {
            return " "
        }
        
        let indexBeforeCursor = documentContext.index(before: endIndex)
        
//        // 문서의 첫 번째 문자인지 확인
//        guard indexBeforeCursor != documentContext.startIndex else {
//            return nil // 첫 번째 문자일 경우 nil 반환
//        }

        return documentContext[indexBeforeCursor]
    }

}
class KeyboardViewController: UIInputViewController {
    var characterButtons: [KeyCap] = []
    var keyCaps: [KeyCap] = []
    var currentHangul = HangulMaker()
    private let hapticGenerator = UIImpactFeedbackGenerator(style: .light)
    private var deleteTimer: Timer?
    var lastDocumentContext: String?
    var isDecomposable: Bool = false  // 입력 시 자소 분리 가능 상태
    weak var delegate: KeyboardViewControllerDelegate?
    var lastCursorPosition: Int?
    private var lexicon: UILexicon?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        configureKeyCaps()
        setupKeyboardLayout()
        hapticGenerator.prepare()
        currentHangul.delegate = self
        loadLexicon()
        }
    private func loadLexicon() {
        requestSupplementaryLexicon { (lexicon) in
            self.lexicon = lexicon
            if let lexicon = self.lexicon {
                print("Lexicon loaded with \(lexicon.entries.count) entries")
                for entry in lexicon.entries {
                    print("Lexicon entry: \(entry.userInput) -> \(entry.documentText)")
                }
            } else {
                print("Failed to load lexicon")
            }
        }
    }
    
    // 오타 교정 사전 정의
    let customCorrections: [String: String] = [
        "과아수쇗": "과일 주스",
        // 더 많은 교정 쌍을 여기에 추가
    ]

    private func correctTextIfNeeded() {
        guard let proxy = textDocumentProxy as? UITextDocumentProxy else {
            print("Text document proxy not available")
            return
        }
        
        let documentContext = proxy.documentContextBeforeInput ?? ""
        var words = documentContext.split { $0.isWhitespace || $0.isNewline }.map { String($0) }
        
        // 만약 documentContextBeforeInput이 비어있고 documentContextAfterInput에 내용이 있다면
        if words.isEmpty, let afterContext = proxy.documentContextAfterInput {
            words = afterContext.split { $0.isWhitespace || $0.isNewline }.map { String($0) }
        }
        
        guard let lastWord = words.last else {
            print("No last word found")
            return
        }
        
        print("Document context: \(lastWord)")
        
        // 사용자 정의 오타 교정
        if let correctedText = customCorrections[lastWord] {
            print("사용자 정의 교정어: \(lastWord) -> \(correctedText)")  // 콘솔 로그 추가
            for _ in 0..<lastWord.count {
                proxy.deleteBackward()
            }
            proxy.insertText(correctedText)
            return
        }
        
        // UILexicon을 이용한 기본 교정
        if let lexicon = lexicon {
            for entry in lexicon.entries {
                if entry.userInput == lastWord {
                    let correctedText = entry.documentText
                    print("자동 교정어: \(entry.userInput) -> \(correctedText)")  // 콘솔 로그 추가
                    for _ in 0..<lastWord.count {
                        proxy.deleteBackward()
                    }
                    proxy.insertText(correctedText)
                    break
                }
            }
        }
    }
private func saveCurrentCursorPosition() {
             if let proxy = textDocumentProxy as? UITextDocumentProxy {
                 let currentPosition = proxy.documentContextBeforeInput?.count ?? 0
                 lastCursorPosition = currentPosition
             }
         }

         // 커서 위치 변경 확인
     private func hasCursorPositionChanged() -> Bool {
         if let proxy = textDocumentProxy as? UITextDocumentProxy {
             let currentPosition = proxy.documentContextBeforeInput?.count ?? 0
             return currentPosition != lastCursorPosition
         }
         return false
     }
    
    override func textWillChange(_ textInput: UITextInput?) {
        super.textWillChange(textInput)
        // 입력이 화면에 나타나기 전에 필요한 사전 처리를 수행합니다.
        // 예: 입력 버퍼 초기화, 상태 업데이트 등
    }
    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        // 입력이 화면에 반영된 후에 호출됩니다.
        // 여기서 checkAndCallAfterDelete 함수를 호출하여 문서 컨텍스트의 변경을 감지하고 처리합니다.
        checkAndCallAfterDelete()
    }


    private func checkAndCallAfterDelete() {
        guard let proxy = textDocumentProxy as? UITextDocumentProxy else { return }
        let currentContext = proxy.documentContextBeforeInput ?? ""

        // 커서가 이동하거나 키보드가 해제된 경우 함수를 호출
        if lastDocumentContext != currentContext {
            currentHangul.afterDelete()
            isDecomposable = false  // 커서 이동이나 다른 입력 발생 시 자소 분리 상태 해제
        }

        lastDocumentContext = currentContext
    }

    func configureKeyCaps() {
        keyCaps = [
                   KeyCap(
                    defaultCharacter: "ㄱ", slideUpCharacter: "ㄲ", slideDownCharacter: "ㅋ",
                          slideLeftCharacter: "ㅋ",
                          slideRightCharacter: "ㅋ",
                         slideUpRightCharacter: "ㄲ",
                         slideDownLeftCharacter: "ㅋ",
                          slideLeftRightCharacter: "ㅋ",
                          slideRightLeftCharacter: "ㅋ"
                         ),
                   KeyCap(defaultCharacter: "ㄴ",
                          slideUpCharacter: "ㄸ",
                          slideDownCharacter: "ㄷ",
                          slideLeftCharacter: "ㅌ",
                          slideRightCharacter: "ㅌ"),
                   KeyCap(defaultCharacter: "ㅢ",
                          slideUpCharacter: "ㅚ",
                          slideDownCharacter: "ㅟ",
                          slideLeftCharacter: "ㅝ",
                          slideRightCharacter: "ㅘ",
                         slideUpRightCharacter: "ㅝ"),
                   KeyCap(defaultCharacter: "⌫", keyType: .backspace),
                   KeyCap(defaultCharacter: "ㄹ",
                          slideUpCharacter: "^",
                          slideDownCharacter: "_",
                          slideLeftCharacter: "=", slideRightCharacter: "-"),
                   KeyCap(defaultCharacter: "ㅁ",
                          slideUpCharacter: "ㅃ",
                          slideDownCharacter: "ㅂ",
                          slideLeftCharacter: "ㅍ", slideRightCharacter: "ㅍ"),
                   KeyCap(defaultCharacter: "ㅣ",
                          slideUpCharacter: "ㅗ",
                          slideDownCharacter: "ㅜ",
                          slideLeftCharacter: "ㅓ", slideRightCharacter: "ㅏ",
                         slideUpRightCharacter: "ㅘ", slideDownLeftCharacter: "ㅝ"),
                   KeyCap(defaultCharacter: "!",
                          slideUpCharacter: "?",
                          slideDownCharacter: ";",
                          slideLeftCharacter: "~"),
                   KeyCap(defaultCharacter: "ㅅ", slideUpCharacter: "ㅆ", slideDownCharacter: "2",
                          slideLeftCharacter: "1", slideRightCharacter: "3"),
                   KeyCap(defaultCharacter: "ㅇ",
                          slideUpCharacter: "💩",
                          slideDownCharacter: "5",
                          slideLeftCharacter: "4", slideRightCharacter: "6"),
                   KeyCap(defaultCharacter: "ㅡ",
                          slideUpCharacter: "ㅙ",
                          slideDownCharacter: "ㅞ",
                          slideLeftCharacter: "ㅔ", slideRightCharacter: "ㅐ",
                          slideUpRightCharacter: "ㅙ",
                          slideDownLeftCharacter: "ㅞ",
                         slideLeftRightCharacter: "ㅖ",
                         slideRightLeftCharacter: "ㅒ"),
                   KeyCap(defaultCharacter: "😘",
                          slideUpCharacter: "🥰",
                          slideDownCharacter: "💤",
                          slideLeftCharacter: "😍",
                          slideDownLeftCharacter: "😴",
                          slideLeftRightCharacter: "🫶"
                          ),
                   KeyCap(defaultCharacter: "ㅈ",
                          slideUpCharacter: "ㅉ",
                          slideDownCharacter: "~",
                          slideLeftCharacter: "ㅊ", slideRightCharacter: "ㅊ"),
                   KeyCap(defaultCharacter: "ㅎ",
                          slideUpCharacter: "0",
                          slideDownCharacter: "8",
                          slideLeftCharacter: "7", slideRightCharacter: "9"),
                   KeyCap(defaultCharacter: "",
                          slideUpCharacter: "ㅛ",
                          slideDownCharacter: "ㅠ",
                          slideLeftCharacter: "ㅕ",
                          slideRightCharacter: "ㅑ",
                          slideUpRightCharacter: "ㅛ",
                          slideDownLeftCharacter: "ㅠ",
                         slideLeftRightCharacter: "ㅖ",
                         slideRightLeftCharacter: "ㅒ"),
                   KeyCap(defaultCharacter: "🤓",
                          slideUpCharacter: "💨",
                          slideDownCharacter: "🥺",
                          slideLeftCharacter: "🥹",
                          slideDownLeftCharacter: "💝",
                         slideLeftRightCharacter: "💗")
               ]


        assignButtonTitles()
    }
    func setupKeyboardLayout() {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.distribution = .fillEqually
        stackView.alignment = .fill
        stackView.spacing = 2 // 간격을 줄임
        stackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stackView)

        // 키보드의 전체 높이를 적절하게 설정 (예: 235 포인트)
        let keyboardHeight: CGFloat = 235
        view.heightAnchor.constraint(equalToConstant: keyboardHeight).isActive = true

        NSLayoutConstraint.activate([
            stackView.leftAnchor.constraint(equalTo: view.leftAnchor, constant: 5),
            stackView.rightAnchor.constraint(equalTo: view.rightAnchor, constant: -5),
            stackView.topAnchor.constraint(equalTo: view.topAnchor, constant: 5),
            stackView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -5)
        ])
        
        let numberOfRows = 5
        let numberOfButtonsPerRow = 4
        for row in 0..<numberOfRows {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.distribution = .fillEqually
            rowStack.alignment = .fill
            rowStack.spacing = 3 // 간격을 줄임
            rowStack.layoutMargins = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 4) // 원하는 여백으로 변경
            rowStack.isLayoutMarginsRelativeArrangement = true
            stackView.addArrangedSubview(rowStack)

            if row == 4 {
                for col in 0..<5 {
                    if col == 0 {
                        // 5행 1열에 숫자 키패드로 전환하는 버튼을 추가
                        let numberPadButton = KeyCap(defaultCharacter: "#", keyType: .custom(switchToNumberPad))
                        numberPadButton.setTitle("123", for: .normal)
                                              
                        setupButtonAppearance(button: numberPadButton)
                        rowStack.addArrangedSubview(numberPadButton)
                        numberPadButton.widthAnchor.constraint(equalTo: rowStack.widthAnchor, multiplier: 10/105.5).isActive = true
                        numberPadButton.heightAnchor.constraint(equalTo: stackView.heightAnchor, multiplier: 18 / 105.5).isActive = true
                        numberPadButton.backgroundColor = .systemGray2
                        continue
                    } else if col == 2 {
                        let spaceButton = KeyCap(defaultCharacter: " ", keyType: .space)
                        spaceButton.setTitle("space", for: .normal)
                        rowStack.addArrangedSubview(spaceButton)
                        spaceButton.widthAnchor.constraint(equalTo: rowStack.widthAnchor, multiplier: 45/105.5).isActive = true
                        spaceButton.heightAnchor.constraint(equalTo: stackView.heightAnchor, multiplier: 18 / 105.5).isActive = true
                        spaceButton.backgroundColor = .white
                        spaceButton.layer.cornerRadius = 5
                        spaceButton.setTitleColor(.black, for: .normal)
                        spaceButton.setTitleColor(.black, for: .highlighted)
                        spaceButton.titleLabel?.font = .systemFont(ofSize: 16)
                        spaceButton.layer.shadowColor = UIColor.black.cgColor
                        spaceButton.layer.shadowOffset = CGSize(width: 0, height: 1)
                        spaceButton.layer.shadowOpacity = 0.5
                        spaceButton.layer.shadowRadius = 0
                        continue
                    } else if col == 4 {
                        let returnButton = KeyCap(defaultCharacter: "\n", keyType: .custom(handleReturn))
                        returnButton.setTitle("return", for: .normal)
                        returnButton.backgroundColor = .systemGray2
                        returnButton.layer.cornerRadius = 5
                        returnButton.titleLabel?.font = .systemFont(ofSize: 15)
                        returnButton.setTitleColor(.black, for: .normal)
                        returnButton.setTitleColor(.black, for: .highlighted)
                        returnButton.layer.shadowColor = UIColor.black.cgColor
                        returnButton.layer.shadowOffset = CGSize(width: 0, height: 1)
                        returnButton.layer.shadowOpacity = 0.5
                        returnButton.layer.shadowRadius = 0
                        rowStack.addArrangedSubview(returnButton)
                        returnButton.heightAnchor.constraint(equalTo: stackView.heightAnchor, multiplier: 18 / 105.5).isActive = true
                        returnButton.widthAnchor.constraint(equalTo: rowStack.widthAnchor, multiplier: 22/105.5).isActive = true
                        continue
                    }
                    
                    let button = KeyCap(defaultCharacter: "")
                    setupButtonAppearance(button: button)
                    rowStack.addArrangedSubview(button)
                    button.heightAnchor.constraint(equalTo: stackView.heightAnchor, multiplier: 18 / 105.5).isActive = true
                    button.widthAnchor.constraint(equalTo: rowStack.widthAnchor, multiplier: 11/105.5).isActive = true
                }
            } else {
                for col in 0..<numberOfButtonsPerRow {
                    let button = keyCaps[(row * numberOfButtonsPerRow + col) % keyCaps.count]

                    setupButtonAppearance(button: button)
                    rowStack.addArrangedSubview(button)
                    button.heightAnchor.constraint(equalTo: stackView.heightAnchor, multiplier: 20.5 / 105.5).isActive = true
                    button.widthAnchor.constraint(equalTo: rowStack.widthAnchor, multiplier: 27/105.5).isActive = true
                    if row != 4 && col == 3 { // 마지막 열
                        button.widthAnchor.constraint(equalTo: rowStack.widthAnchor, multiplier: 19/105.5).isActive = true
                    }
                    
                    characterButtons.append(button)
                    if row == 0 && col == 3 {
                        button.backgroundColor = .systemGray2
                        button.titleLabel?.font = UIFont.systemFont(ofSize: 28, weight: .light)
                    }
                }
            }
        }
    }

    @objc func switchToNumberPad() {
        // 숫자 키패드로 전환하는 액션 구현
        print("Switching to number pad")
    }
    func setupButtonAppearance(button: KeyCap) {
        button.backgroundColor = .white
        button.layer.cornerRadius = 5
        button.setTitleColor(.black, for: .normal)
        button.setTitleColor(.black, for: .highlighted)
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOffset = CGSize(width: 0, height: 1)
        button.layer.shadowOpacity = 0.5
        button.layer.shadowRadius = 0
        button.titleLabel?.font = UIFont.systemFont(ofSize: 16)
    }
    
    @objc func handleReturn() {
        currentHangul.afterDelete()
        textDocumentProxy.insertText("\n")
    }

    func assignButtonTitles() {
        for (index, button) in characterButtons.enumerated() {
            if index < keyCaps.count {
                let keyCap = keyCaps[index]
                button.defaultCharacter = keyCap.defaultCharacter
                button.setTitle(keyCap.defaultCharacter, for: .normal)
                button.slideUpCharacter = keyCap.slideUpCharacter
                button.slideDownCharacter = keyCap.slideDownCharacter
                button.slideLeftCharacter = keyCap.slideLeftCharacter
                button.slideRightCharacter = keyCap.slideRightCharacter
                button.slideUpRightCharacter = keyCap.slideUpRightCharacter
                button.slideDownLeftCharacter = keyCap.slideDownLeftCharacter
                button.slideLeftRightCharacter = keyCap.slideLeftRightCharacter
                button.slideRightLeftCharacter = keyCap.slideRightLeftCharacter
                button.keyType = keyCap.keyType
            }
        }
    }

    func processInput(_ input: String) {
        var cursorTemp = lastCursorPosition ?? -1
        if hasCursorPositionChanged() && delegate?.requestDecomposableState() != true && isDecomposable != true{
              currentHangul.afterDelete()
              delegate?.updateDecomposableState(isDecomposable: false)
          }
          for character in input {
              let result = currentHangul.commit(character)
              if result == 1 {
                  textDocumentProxy.deleteBackward()
              } else if result == 2 {
                  textDocumentProxy.deleteBackward()
              }
          }
          if currentHangul.textStorage != "" {
              let result = currentHangul.textStorage
              textDocumentProxy.insertText(result)
              print("Checking for text correction")
              correctTextIfNeeded()
          }

          saveCurrentCursorPosition()
      }

    func deleteBackward() {
        let prevState = currentHangul.state
        
        currentHangul.delete()
        
        if prevState == 0 {
            textDocumentProxy.deleteBackward()
        } else if prevState == 1 {
            if currentHangul.state == 0 {
                textDocumentProxy.deleteBackward()
            } else if currentHangul.state == 2{
                textDocumentProxy.deleteBackward()
                textDocumentProxy.deleteBackward()
                textDocumentProxy.insertText(currentHangul.textStorage)
            }
            else if currentHangul.state == 3 {
                textDocumentProxy.deleteBackward()
                textDocumentProxy.deleteBackward()
                textDocumentProxy.insertText(currentHangul.textStorage)
            }
            else {
                textDocumentProxy.insertText(currentHangul.textStorage)
            }
        } else if prevState == 2 {
            if currentHangul.state == 1 {
                textDocumentProxy.deleteBackward()
                textDocumentProxy.insertText(currentHangul.textStorage)
            } else if currentHangul.state == 3{
                textDocumentProxy.deleteBackward()
                textDocumentProxy.deleteBackward()
                textDocumentProxy.insertText(currentHangul.textStorage)
                currentHangul.state = 3
                
            } else {
                textDocumentProxy.insertText(currentHangul.textStorage)
            }
        } else if prevState == 3 {
            if currentHangul.state == 2 {
                textDocumentProxy.deleteBackward()
                textDocumentProxy.insertText(currentHangul.textStorage)
            } else if currentHangul.state == 3 {
                textDocumentProxy.deleteBackward()
                textDocumentProxy.insertText(currentHangul.textStorage)
            } else {
                textDocumentProxy.insertText(currentHangul.textStorage)
            }
        }
    }
    func deleteAllText() {
        if let documentContext = textDocumentProxy.documentContextBeforeInput {
            for _ in documentContext {
                currentHangul.afterDelete()
                textDocumentProxy.deleteBackward()
            }
        }
    }
    func deleteWord() {
        guard let documentContext = textDocumentProxy.documentContextBeforeInput, !documentContext.isEmpty else {
            print("Document context is empty or nil")
            return
        }
        print("Current document context: '\(documentContext)'")

        // 연속된 같은 특수문자 포함하여 한글 자음, 모음, 숫자, 영문을 구분하는 정규 표현식
        let pattern = "[가-힣]+|[ㄱ-ㅎ]+|[ㅏ-ㅣ]+|\\d+|[A-Za-z]+|((\\p{Punct})\\2*)"
        let regex = try! NSRegularExpression(pattern: pattern, options: [])

        let results = regex.matches(in: documentContext, options: [], range: NSRange(documentContext.startIndex..., in: documentContext))

        if let lastResult = results.last, let range = Range(lastResult.range, in: documentContext) {
            let wordToDelete = documentContext[range]
            deleteCharacters(count: wordToDelete.count)
        } else {
            // 매칭 결과가 없을 경우 가장 마지막 문자 삭제
            deleteCharacters(count: 1)
        }

        // 공백 또는 줄바꿈 문자가 마지막에 있을 경우 추가로 삭제 처리
        if documentContext.hasSuffix(" ") || documentContext.hasSuffix("\n") {
            deleteCharacters(count: 1)
        }
    }

    private func deleteCharacters(count: Int) {
        for _ in 0..<count {
            currentHangul.afterDelete()
            textDocumentProxy.deleteBackward()
        }
    }

    
        func deleteLine() {
            if let documentContext = textDocumentProxy.documentContextBeforeInput {
                let lines = documentContext.split(separator: "\n")
                if let lastLine = lines.last {
                    for _ in lastLine {
                        currentHangul.afterDelete()
                        textDocumentProxy.deleteBackward()
                    }
                }

            }
        }

}

import Foundation

class HangulMaker {
    private var cho: Character = "\u{0000}"
    private var jun: Character = "\u{0000}"
    private var jon: Character = "\u{0000}"
    private var jonFlag: Character = "\u{0000}"
    private var doubleJonFlag: Character = "\u{0000}"
    var junFlag: Character = "\u{0000}"
    var textDocumentProxy: UITextInput?
    private let chos: [Int] = [0x3131, 0x3132, 0x3134, 0x3137, 0x3138, 0x3139, 0x3141, 0x3142, 0x3143, 0x3145, 0x3146, 0x3147, 0x3148, 0x3149, 0x314a, 0x314b, 0x314c, 0x314d, 0x314e]
    private let juns: [Int] = [0x314f, 0x3150, 0x3151, 0x3152, 0x3153, 0x3154, 0x3155, 0x3156, 0x3157, 0x3158, 0x3159, 0x315a, 0x315b, 0x315c, 0x315d, 0x315e, 0x315f, 0x3160, 0x3161, 0x3162, 0x3163]
    private let jons: [Int] = [0x0000, 0x3131, 0x3132, 0x3133, 0x3134, 0x3135, 0x3136, 0x3137, 0x3139, 0x313a, 0x313b, 0x313c, 0x313d, 0x313e, 0x313f, 0x3140, 0x3141, 0x3142, 0x3144, 0x3145, 0x3146, 0x3147, 0x3148, 0x314a, 0x314b, 0x314c, 0x314d, 0x314e]
    
    weak var delegate: KeyboardViewControllerDelegate?

    func getPrevText() -> Character {
            guard let delegate = delegate else { return "\u{0000}"}
            let isDecomposable = delegate.requestDecomposableState()
            let previousCharacter = delegate.requestPreviousCharacter()
        let justPreviousCharacter = delegate.requestJustPreviousCharacter()
            print("Is decomposable: \(isDecomposable)")
            if let character = previousCharacter {
                print("Previous character: \(character)")
                return character
            }else{ return "\u{0000}"}
            
        }
    
    func updateDecomposableState(newState: Bool) {
            delegate?.updateDecomposableState(isDecomposable: newState)
        }
    func requestDecomposable() -> Bool {
        guard let delegate = delegate else { return true}
        let isDecomposable = delegate.requestDecomposableState()
        return isDecomposable
    }
    func decomposeKoreanCharacter(_ character: Character) -> (cho: String, jung: String, jong: String) {
        let hangulSyllables = "가".unicodeScalars.first!.value..."\u{D7A3}".unicodeScalars.first!.value
        let initialConsonants = ["ㄱ", "ㄲ", "ㄴ", "ㄷ", "ㄸ", "ㄹ", "ㅁ", "ㅂ", "ㅃ", "ㅅ", "ㅆ", "ㅇ", "ㅈ", "ㅉ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ"]
        let medialVowels = ["ㅏ", "ㅐ", "ㅑ", "ㅒ", "ㅓ", "ㅔ", "ㅕ", "ㅖ", "ㅗ", "ㅘ", "ㅙ", "ㅚ", "ㅛ", "ㅜ", "ㅝ", "ㅞ", "ㅟ", "ㅠ", "ㅡ", "ㅢ", "ㅣ"]
        let finalConsonants = ["", "ㄱ", "ㄲ", "ㄳ", "ㄴ", "ㄵ", "ㄶ", "ㄷ", "ㄹ", "ㄺ", "ㄻ", "ㄼ", "ㄽ", "ㄾ", "ㄿ", "ㅀ", "ㅁ", "ㅂ", "ㅄ", "ㅅ", "ㅆ", "ㅇ", "ㅈ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ"]

        guard let scalarValue = character.unicodeScalars.first?.value, hangulSyllables.contains(scalarValue) else {
            return ("", "", "")
        }

        let base = scalarValue - 0xAC00
        let choIndex = Int(base / 588)
        let jungIndex = Int((base % 588) / 28)
        let jongIndex = Int(base % 28)

        return (initialConsonants[choIndex], medialVowels[jungIndex], finalConsonants[jongIndex])
    }
    /**
     * 0:""
     * 1: 모음 입력상태
     * 2: 모음 + 자음 입력상태
     * 3: 모음 + 자음 + 모음입력상태(초 중 종성)
     * 초성과 종성에 들어갈 수 있는 문자가 다르기 때문에 필요에 맞게 수정이 필요함.(chos != jons)
     */
    fileprivate var state = 0
    var textStorage: String = ""
    func afterDelete() {
        setStateZero()
        textStorage = String("")
        clear()
        state = 0
    }
    func clear() {
        cho = "\u{0000}"
        jun = "\u{0000}"
        jon = "\u{0000}"
        jonFlag = "\u{0000}"
        doubleJonFlag = "\u{0000}"
        junFlag = "\u{0000}"
    }

    func makeHan() -> Character {
        if state == 0 {
            return "\u{0000}"
        }
        if state == 1 {
            return cho
        }
        let choIndex = chos.firstIndex(of: Int(cho.unicodeScalars.first!.value)) ?? -1
        let junIndex = juns.firstIndex(of: Int(jun.unicodeScalars.first!.value)) ?? -1
        let jonIndex = jons.firstIndex(of: Int(jon.unicodeScalars.first!.value)) ?? -1

        let makeResult = 0xAC00 + 28 * 21 * choIndex + 28 * junIndex + jonIndex
        return Character(UnicodeScalar(makeResult)!)
    }

    open func commit(_ c: Character) -> Int {
        var isDecomposable = delegate?.requestDecomposableState()
        let prevCharInCase0 = delegate?.requestJustPreviousCharacter()
        var (prevCho0, prevJung0, prevJong0) = ("", "", "")
        (prevCho0, prevJung0, prevJong0) = decomposeKoreanCharacter(prevCharInCase0 ?? " ")
            let cInt = Int(c.unicodeScalars.first!.value)
            if !chos.contains(cInt) && !juns.contains(cInt) && !jons.contains(cInt) {
                setStateZero()
                textStorage = String(c)
                clear()
                state = 0
                delegate?.updateDecomposableState(isDecomposable: false)
                return 0
            }
        if delegate?.requestDecomposableState() == true {
            if prevCho0 != "" && prevJung0 != "" && prevJong0 != "" {
                state = 3
            } else if prevCho0 != "" && prevJung0 != "" {
                cho = Character(prevCho0)
                jun = Character(prevJung0)
                state = 2
            }
        }
            switch state {
                
            case 0:
                if juns.contains(cInt) { //ㅏ
                    setStateZero()
                    textStorage = String(c)
                    clear()
                } else { // ㅂ
                    state = 1
                    cho = c
                    textStorage = String(cho)
                }
                delegate?.updateDecomposableState(isDecomposable: true)
                delegate?.updateDecomposableState(isDecomposable: true)
            case 1: // ㅂ
                if chos.contains(cInt) { // ㅂㅂ
                    setStateZero()
                    textStorage = String(c)
                    clear()
                    cho = c
                    
                } else { // 바
                    state = 2
                    jun = c
                    textStorage = String(makeHan())
                    delegate?.updateDecomposableState(isDecomposable: true)
                    return 1 // 앞의 텍스트 지우기
                }
                delegate?.updateDecomposableState(isDecomposable: true)
            case 2: //바
                if jons.contains(cInt) {
                    jon = c
                    textStorage = String(makeHan())
                    state = 3
                    delegate?.updateDecomposableState(isDecomposable: true)
                    return 1
                } else { //바ㅏ
                    setStateZero()
                    textStorage = String(c)
                    clear()
                    state = 0
                    if chos.contains(cInt) {
                        state = 1
                        cho = c
                    }
                }
                delegate?.updateDecomposableState(isDecomposable: true)
            case 3: //받

                if jons.contains(cInt) {
                    if doubleJonEnable(c) { // 밟
                        textStorage = String(makeHan())
                        doubleJonFlag = "\u{0000}"
                        delegate?.updateDecomposableState(isDecomposable: true)
                        return 1
                    } else { //발ㄹ
                        let isDecpmposable = delegate?.requestDecomposableState()
                        if isDecpmposable == true && state == 1 {
                            state = 3
                            textStorage = String(makeHan())
                            delegate?.updateDecomposableState(isDecomposable: true)
                            break
                        }
                        setStateZero()
                        textStorage = String(c)
                        clear()
                        state = 1
                        cho = c
                        textStorage = String(cho)
                        delegate?.updateDecomposableState(isDecomposable: true)
                    }
                } else if chos.contains(cInt) {
                    setStateZero()
                    textStorage = String(c)
                    clear()
                    state = 1
                    cho = c
                    textStorage = String(cho)
                    delegate?.updateDecomposableState(isDecomposable: true)
                    
                } else {
                    var temp: Character = "\u{0000}"
                    if delegate?.requestDecomposableState() == true && isDoubleJong(Character(prevJong0)){
                        let jong = splitDoubleJong(Character(prevJong0))
                        state = 2
                        cho = Character(prevCho0)
                        jun = Character(prevJung0)
                        jon = jong!.first
                        textStorage = String(makeHan())
                        cho = jong!.second
                        jun = c
                        jon = "\u{0000}"
                        textStorage.append(String(makeHan()))
                        delegate?.updateDecomposableState(isDecomposable: true)
                        return 2
                    }
                    if doubleJonFlag == "\u{0000}" {
                        temp = jon
                        jon = "\u{0000}"
                        setStateZero()
                        if isDecomposable == true {
                            state = 2
                            cho = Character(prevCho0)
                            jun = Character(prevJung0)
                            textStorage = String(makeHan())
                            temp = Character(prevJong0)
                            cho = temp
                            jun = c
                            jon = "\u{0000}"
                            textStorage.append(String(makeHan()))
                            delegate?.updateDecomposableState(isDecomposable: true)
                            return 2
                        }
                        delegate?.updateDecomposableState(isDecomposable: true)
                    } else {
                        temp = doubleJonFlag
                        jon = jonFlag

                        setStateZero()
                        delegate?.updateDecomposableState(isDecomposable: true)
                    }
                    state = 2
                    clear()
                    cho = temp
                    jun = c
                    textStorage = removeFirstHangulSyllable(textStorage)
                    
                    textStorage.append(String(makeHan()))
                    delegate?.updateDecomposableState(isDecomposable: true)
                    return 2
                }

            default:
                break
            }
            return 0
        }

    func removeFirstHangulSyllable(_ string: String) -> String {
        if string.isEmpty {
            return string
        }
        
        var index = string.startIndex
        let firstSyllable = string[index]
        
        if firstSyllable.unicodeScalars.first?.value ?? 0 >= 0xAC00 && firstSyllable.unicodeScalars.first?.value ?? 0 <= 0xD7A3 {
            index = string.index(after: index)
        } else {
            while index < string.endIndex &&
                  ((string[index].unicodeScalars.first?.value ?? 0 < 0xAC00) ||
                   (string[index].unicodeScalars.first?.value ?? 0 > 0xD7A3)) {
                index = string.index(after: index)
            }
        }
        
        // Check if the index is at the end of the string
        if index == string.endIndex {
            return ""
        }
        
        return String(string[index...])
    }


    func commitSpace() {
        setStateZero()
        textStorage.append(" ")
    }

    open func setStateZero() {
        if state == 0 {
            return
        }
        if state == 1 {
            state = 1
            return
        }
        textStorage.append(String(makeHan()))
        state = 0
        clear()
    }
    open func removeFinalConsonant(hangul: Character) -> Character {
        let unicode = hangul.unicodeScalars.first!.value
        let base: UInt32 = 0xAC00
        let choIndex = (unicode - base) / (21 * 28)
        let junIndex = ((unicode - base) % (21 * 28)) / 28
        let result = base + choIndex * 21 * 28 + junIndex * 28
        return Character(UnicodeScalar(result)!)
    }
    func isDoubleJong(_ jong: Character) -> Bool {
        // 이중 종성 리스트
        let doubleJongs: [Character] = ["ㄳ", "ㄵ", "ㄶ", "ㄺ", "ㄻ", "ㄼ", "ㄽ", "ㄾ", "ㄿ", "ㅀ", "ㅄ"]
        return doubleJongs.contains(jong)
    }
    func splitDoubleJong(_ jong: Character) -> (first: Character, second: Character)? {
        switch jong {
        case "ㄳ": return ("ㄱ", "ㅅ")
        case "ㄵ": return ("ㄴ", "ㅈ")
        case "ㄶ": return ("ㄴ", "ㅎ")
        case "ㄺ": return ("ㄹ", "ㄱ")
        case "ㄻ": return ("ㄹ", "ㅁ")
        case "ㄼ": return ("ㄹ", "ㅂ")
        case "ㄽ": return ("ㄹ", "ㅅ")
        case "ㄾ": return ("ㄹ", "ㅌ")
        case "ㄿ": return ("ㄹ", "ㅍ")
        case "ㅀ": return ("ㄹ", "ㅎ")
        case "ㅄ": return ("ㅂ", "ㅅ")
        default: return nil
        }
    }
    func isHangulSyllable(_ character: Character) -> Bool {
        let unicode = character.unicodeScalars.first!.value
        return (unicode >= 0xAC00 && unicode <= 0xD7A3)
    }

    open func delete() {
        let isDecomposable = delegate?.requestDecomposableState()
        let prevText = getPrevText()
        let (prevCho, prevJung, prevJong): (String, String, String?) = decomposeKoreanCharacter(prevText)
        let justPrevText = delegate?.requestJustPreviousCharacter()
        let (justPrevCho, justPrevJung, justPrevJong): (String, String, String?) = decomposeKoreanCharacter(justPrevText ?? "\u{0000}")

            switch state {
            case 0:
                if !textStorage.isEmpty {
                    textStorage.removeLast()
                }
                
            case 1:
               
                var temp : Character = "\u{0000}"
                print(prevText)
                
                if isDecomposable == true && prevText != "\n" && prevText != " " && isHangulSyllable(prevText){
                    if ((prevJong?.isEmpty) != nil) && jons.contains(Int(cho.unicodeScalars.first!.value)) || chos.contains(Int(cho.unicodeScalars.first!.value)){
                        if let prevJong = prevJong, !prevJong.isEmpty {
                            jon = Character(prevJong)
                        } else {
                            // prevJong이 nil이거나 빈 문자열인 경우를 처리합니다.
                            // 예를 들어, jon에 기본값을 설정하거나 오류를 반환할 수 있습니다.
                            jon = Character("\u{0000}")
                        }
                        cho = Character(prevCho)
                        jun = Character(prevJung)
                        state = 3
                        textStorage = String(makeHan())
                        doubleJonFlag = "\u{0000}"
                    } else {
                        if jons.contains(Int(cho.unicodeScalars.first!.value)) != true {
                            cho = Character(prevCho)
                            jun = Character(prevJung)
                            state = 2
                            textStorage = String(makeHan())
                            break
                        }
                            state = 3
                            temp = cho
                            cho = Character(prevCho)
                            jun = Character(prevJung)
                        jon = prevJong?.isEmpty == false ? Character(prevJong!) : "\u{0000}"
                            textStorage = String(makeHan())
                        }
//                    }
                }else{
                    cho = "\u{0000}"
                    state = 0
                    textStorage = ""
                }
            case 2:
                let prevText = getPrevText()
                var temp : Character = "\u{0000}"
                print(prevText)
                let (prevCho, prevJung, prevJong): (String, String, String) = decomposeKoreanCharacter(prevText)

                print(prevCho, prevJung, prevJong)
                

                if junFlag != "\u{0000}" {
                    jun = junFlag
                    junFlag = "\u{0000}"
                    state = 2
                    textStorage = String(makeHan())
                } else if isDecomposable == true && prevText != "\n" && prevText != " " && isHangulSyllable(prevText) {
                    if prevJong.isEmpty {
                        let choUnicode = Int(cho.unicodeScalars.first!.value)
                        if jons.contains(choUnicode){
                            temp = jon
                            jon = cho
                            cho = Character(prevCho)
                            jun = Character(prevJung)
                            state = 3
                            textStorage = String(makeHan())
                            break
                        } else {
                            state = 1
                            jun = "\u{0000}"
                            textStorage = String(cho)
                            break
                        }
                    } else {
                        jon = Character(prevJong)
                        if doubleJonEnable(cho) == true {
                            state = 3
                            cho = Character(prevCho)
                            jun = Character(prevJung)
                            textStorage = String(makeHan())
                            break
                        }
                        jun = "\u{0000}"
                        junFlag = "\u{0000}"
                        jon = "\u{0000}"
                        state = 1
                        textStorage = String(cho)
                    }
                } else {
                        jun = "\u{0000}"
                        junFlag = "\u{0000}"
                        jon = "\u{0000}"
                        state = 1
                        textStorage = String(cho)
                    }
            case 3:
                let (prevCho, prevJung, prevJong): (String, String, String) = decomposeKoreanCharacter(Character(textStorage))
                let validPrevJong = prevJong.isEmpty ? "\u{0000}" : prevJong
                var doubleJongState = isDoubleJong(Character(validPrevJong))
                
                if doubleJongState == false {
                    jon = "\u{0000}"
                    jonFlag = "\u{0000}"
                    state = 2
                } else {
                    let jong = splitDoubleJong(Character(prevJong))
                    state = 3
                    cho = Character(prevCho)
                    jun = Character(prevJung)
                    jon = jong!.first
                    textStorage = String(makeHan())
                    commit(jong!.second)

                    jon = jonFlag
                    doubleJonFlag = "\u{0000}"
                }
                textStorage = String(makeHan())
            default:
                break
            }
        }
    
    func doubleJunEnable(_ c: Character) -> Bool {
        switch jun {
        case "ㅗ":
            if c == "ㅏ" {
                junFlag = jun
                jun = "ㅘ"
                return true
            }
            if c == "ㅐ" {
                junFlag = jun
                jun = "ㅙ"
                return true
            }
            if c == "ㅣ" {
                junFlag = jun
                jun = "ㅚ"
                return true
            }
            return false
        case "ㅜ":
            if c == "ㅓ" {
                junFlag = jun
                jun = "ㅝ"
                return true
            }
            if c == "ㅔ" {
                junFlag = jun
                jun = "ㅞ"
                return true
            }
            if c == "ㅣ" {
                junFlag = jun
                jun = "ㅟ"
                return true
            }
            return false
        case "ㅡ":
            if c == "ㅣ" {
                junFlag = jun
                jun = "ㅢ"
                return true
            }
            return false
        default:
            return false
        }
    }

    func doubleJonEnable(_ c: Character) -> Bool {
        jonFlag = jon
        doubleJonFlag = c
        switch jon {
        case "ㄱ":
            if c == "ㅅ" {
                jon = "ㄳ"
                return true
            }
            return false
        case "ㄴ":
            if c == "ㅈ" {
                jon = "ㄵ"
                return true
            }
            if c == "ㅎ" {
                jon = "ㄶ"
                return true
            }
            return false
        case "ㄹ":
            if c == "ㄱ" {
                jon = "ㄺ"
                return true
            }
            if c == "ㅁ" {
                jon = "ㄻ"
                return true
            }
            if c == "ㅂ" {
                jon = "ㄼ"
                return true
            }
            if c == "ㅅ" {
                jon = "ㄽ"
                return true
            }
            if c == "ㅌ" {
                jon = "ㄾ"
                return true
            }
            if c == "ㅍ" {
                jon = "ㄿ"
                return true
            }
            if c == "ㅎ" {
                jon = "ㅀ"
                return true
            }
            return false
        case "ㅂ":
            if c == "ㅅ" {
                jon = "ㅄ"
                return true
            }
            return false
        default:
            return false
        }
    }

    func junAvailable() -> Bool {
        return !["ㅙ", "ㅞ", "ㅢ", "ㅐ", "ㅔ", "ㅛ", "ㅒ", "ㅖ"].contains(jun)
    }

    func isDoubleJun() -> Bool {
        return ["ㅙ", "ㅞ", "ㅚ", "ㅝ", "ㅟ", "ㅘ", "ㅢ"].contains(jun)
    }
}

