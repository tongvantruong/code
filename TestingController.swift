import UIKit
import AVFoundation
import CoreData
import WebKit
import MIBadgeButton_Swift
import PopupDialog
import GoogleMobileAds

class TestingController: UIViewController, UITableViewDataSource, UITableViewDelegate, AVAudioPlayerDelegate {
    
    @IBOutlet weak var bannerAd: GADBannerView!
    @IBOutlet weak var audioSlider: UISlider!
    @IBOutlet weak var headerImage: UIImageView!
    @IBOutlet weak var webDescription: WKWebView!
    @IBOutlet weak var questionTableView: UITableView!
    @IBOutlet weak var backButton: UIButton!
    @IBOutlet weak var nextButton: UIButton!
    @IBOutlet weak var hintButton: MIBadgeButton!
    
    let bannderAdId = "ca-app-pub-8151040395902193/628493981780"
    var fullScreenAd: GADInterstitial!
    let fullScreenAdId = "ca-app-pub-81510403953902193/4942354891"
    var fullAdDismissAction: FullAdDismissAction = .none
    let rewardedAdId = "ca-app-pub-81510403959202193/12634878351"
    var isRewarded: Bool = false
    
    let badgeColor = UIColor(named: "Color5")
    let badgeFreeText = "Free"
    
    var questionSets = [QuestionSet]()
    var isFullTest: Bool = false
    
    var remainingQuestionSets = [QuestionSet]()
    var currentQuestionSet: QuestionSet?
    var sortedQuestions = [QuestionDetail]()

    var audioPlayer: AVAudioPlayer?
    var audioTimer: Timer?
    
    var fullTestTimer: Timer?
    var fullTestTime = 110 * 60 * 1000
    
    var tempAnswers = [Answer]()
    
    var currentIndex = 0
    
    var correctListeningCount: Int = 0
    var correctReadingCount: Int = 0
    
    let hintUsedWillShowReview = 300
    
    var hintPopup: PopupDialog?
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
       return currentQuestionSet?.questions.count ?? 0
    }
    
    fileprivate func shuffleCurrentReadingPartOptions() {
        if let questions = currentQuestionSet?.questions {
            sortedQuestions = Array(questions).sorted(by: { $0.questionOrder < $1.questionOrder })
        }
    }
    
    override func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
        if #available(iOS 13.0, *) {
            viewControllerToPresent.modalPresentationStyle = .fullScreen
        }
        super.present(viewControllerToPresent, animated: flag, completion: completion)
    }
    
    func initData() {
        if !questionSets.isEmpty {
            if isFullTest {
                remainingQuestionSets = questionSets
            } else {
                remainingQuestionSets = SmartSort.sort(questionSets)
            }
            newQuestionSet()
        }
    }
    
    func resetHintPopup() {
        hintPopup?.dismiss()
        hintPopup = nil
    }
    
    func newQuestionSet() {
        resetHintPopup()
        if remainingQuestionSets.count > currentIndex {
            currentQuestionSet = remainingQuestionSets[currentIndex]
        } else {
            currentQuestionSet = remainingQuestionSets[0]
        }
        shuffleCurrentReadingPartOptions()
        
        initAudioPart()
        initImagePart()
        initWebViewPart()
        
        setupAutoNextAction()
        setupHideHeaderAction(true)
        setupAudioAction()
        setupBottomActions()
        
        initTempAnswers()
        questionTableView.reloadData()
        questionTableView.scrollToTop()
        updateQuestionShown()
    }
    
    func nextQuestionSet() {
        if isRealTestLastQuestions() {
            completeFullTest()
            return
        }
        
        if currentIndex < remainingQuestionSets.count - 1 {
            currentIndex += 1
        } else {
            currentIndex = 0
        }
        AdsUtil.decreaseFullAdTrackerNextBack()
        if willShowFullScreenAdNextback() {
            fullAdDismissAction = .next
            showFullScreenAd()
        }
        newQuestionSet()
    }
    
    func backQuestionSet() {
        if currentIndex > 0 {
            currentIndex -= 1
        } else {
            currentIndex = remainingQuestionSets.count - 1
        }
        AdsUtil.decreaseFullAdTrackerNextBack()
        if willShowFullScreenAdNextback() {
            fullAdDismissAction = .back
            showFullScreenAd()
        }
        newQuestionSet()
    }
    
    func willShowFullScreenAdNextback() -> Bool {
        return AdsUtil.willShowFullScreenAdNextBack() && fullScreenAd != nil && fullScreenAd.isReady && !isFullTest && !AppUtil.isRemovedAds()
    }
    
    @IBAction func onBackClick(_ sender: Any) {
        backQuestionSet()
    }
    
    func showRewardedAd() -> Bool {
        if GADRewardBasedVideoAd.sharedInstance().isReady == true {
            GADRewardBasedVideoAd.sharedInstance().present(fromRootViewController: self)
            return true
        }
        return false
    }
    
    @IBAction func onNextClick(_ sender: Any) {
        nextQuestionSet()
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "OptionCell", for: indexPath) as! OptionCell
        cell.controller = self
        let currentIndex = indexPath.row
        
        if sortedQuestions.count > currentIndex {
            if tempAnswers.count <= currentIndex {
                tempAnswers.append(Answer(answerCount: 0, correct: false, selectedIndex: -1, keyIndex: -1))
            }
            cell.cellTempAnswer = tempAnswers[currentIndex]
            let currentQuestion = sortedQuestions[currentIndex]
            cell.questionDetail = currentQuestion
            if cell.cellDelegate == nil {
                cell.cellDelegate = self
            }
        }
        return cell
    }
    
    func updateQuestionShown() {
        if let questions = currentQuestionSet?.questions {
            let currentDateTime = Int64(Date().millisecondsSince1970)
            Array(questions).forEach {question in
                question.shown = question.shown + 1
                question.seenAt = currentDateTime
                
                PersistenceService.saveContext()
            }
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        stopAudio()
        stopFullTestTimer()
    }
    
    func stopFullTestTimer() {
        fullTestTimer?.invalidate()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        initData()
        initAllAds()
        initBackButton()
        initTitle()
    }
    
    func initAllAds() {
        if AppUtil.isRemovedAds() {
            bannerAd.isHidden = true
        } else {
            bannerAd.isHidden = false
            initFullScreenAd()
            initRewardedAd()
            loadBannerAd()
        }
    }
    
    func initRewardedAd() {
        GADRewardBasedVideoAd.sharedInstance().delegate = self
        reloadRewardedAd()
    }
    
    func reloadRewardedAd() {
        isRewarded = false
        GADRewardBasedVideoAd.sharedInstance().load(GADRequest(), withAdUnitID: rewardedAdId)
    }
    
    func initTitle() {
        if isFullTest {
            title = DateTimeUtil.formatTime(fullTestTime)
            fullTestTimer?.invalidate()
            fullTestTimer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(updateFullTestTitle), userInfo: nil, repeats: true)
        }
    }
    
    @objc func updateFullTestTitle() {
        if fullTestTime >= 1000 {
            fullTestTime -= 1000
            title = DateTimeUtil.formatTime(fullTestTime)
        }
    }
    
    func goHome() {
        self.navigationController?.popViewController(animated: true)
    }
    
    func initBackButton() {
        self.navigationItem.hidesBackButton = true
        let newBackButton = UIBarButtonItem(image: UIImage(named: "ic-back"), style: .plain, target: self, action: #selector(homeClick))
        self.navigationItem.leftBarButtonItem = newBackButton
    }
    
    @objc func homeClick() {
        AdsUtil.decreaseFullAdTrackerHome()
        if AdsUtil.willShowFullScreenAdHome() && fullScreenAd != nil && fullScreenAd.isReady {
            fullAdDismissAction = .home
            showFullScreenAd()
        }
        goHome()
    }
    
    func initFullScreenAd() {
        fullScreenAd = GADInterstitial(adUnitID: fullScreenAdId)
        fullScreenAd.load(GADRequest())
        fullScreenAd.delegate = self
    }
    
    func showFullScreenAd() {
        if fullScreenAd.isReady && !AppUtil.isRemovedAds() {
            stopAudio()
            fullScreenAd.present(fromRootViewController: self)
        } else {
            print("Full Screen Ad wasn't ready")
        }
    }
    
    func loadBannerAd() {
        bannerAd.adUnitID = bannderAdId
        bannerAd.rootViewController = self
        bannerAd.load(GADRequest())
    }
    
    func isRealTestLastQuestions() -> Bool {
        if currentQuestionSet == nil {
            return false
        }
        let questions = Array(currentQuestionSet!.questions)
        if QuestionUtil.extractQuestionNumber(questions[0].question) >= 196 {
            return true
        }
        return false
    }
    
    func setupBottomActions() {
        backButton.visibility = .gone
        hintButton.visibility = .gone
        nextButton.visibility = .gone
        
        let lang = TextUtil.loadLanguage()
        if isRealTestLastQuestions() {
            nextButton.titleLabel?.text = "complete".loc(lang)
        } else {
            nextButton.titleLabel?.text = "Next"
        }
    }
    
    func initTempAnswers() {
        tempAnswers.removeAll()
        sortedQuestions.forEach {question in
            let answer = Answer(answerCount: 0, correct: false, selectedIndex: -1, keyIndex: -1)
            tempAnswers.append(answer)
        }
    }
    
    @IBAction func onHintClick(_ sender: Any) {
        if AppUtil.isRemovedAds() {
            showHint()
            hintButton.badgeString = ""
            return
        }
        var badgeText: String = ""
        let prefs = UserDefaults.standard
        if prefs.object(forKey: Constant.KEY_HINT) == nil {
            prefs.set(AdsUtil.randomHintAds(), forKey: Constant.KEY_HINT)
            badgeText = String(AdsUtil.randomHintAds())
        } else {
            let currentValue = prefs.integer(forKey: Constant.KEY_HINT)
            if currentValue > 1 {
                showHint()
                let newValue = currentValue - 1
                badgeText = String(newValue)
                prefs.set(newValue, forKey: Constant.KEY_HINT)
            } else if currentValue == 1 {
                showHint()
                badgeText = badgeFreeText
                prefs.set(0, forKey: Constant.KEY_HINT)
            } else {
                if !showRewardedAd() {
                    showToast("cannotShowAds".loc(TextUtil.loadLanguage()))
                    badgeText = badgeFreeText
                    initRewardedAd()
                }
            }
        }
        hintButton.badgeString = badgeText
    }
    
    func showHint() {
        guard currentQuestionSet == nil else {
            let currentLanguage = TextUtil.loadLanguage()
            let hint = currentQuestionSet?.hint
            let hintVn = currentQuestionSet?.hintVn
            
            if var realHint = getHintToShow(currentLanguage, hint, hintVn), !realHint.isEmpty {
                
                if let from = currentQuestionSet?.from, !from.isEmpty {
                    realHint += "<br/><br/><i>\(String(describing: from))</i>"
                }
                
                let popupView = WebViewController(nibName: "WebViewController", bundle: nil)
                popupView.titleContent = "hint".loc(currentLanguage)
                popupView.htmlContent = "<div style='color:white'>\(TextUtil.formatHtmlWithCustomColors(text: realHint))</div>"
                
                hintPopup = PopupDialog(viewController: popupView,
                                        buttonAlignment: .horizontal,
                                        transitionStyle: .bounceUp,
                                        tapGestureDismissal: false,
                                        panGestureDismissal: false)
                
                
                let okButton = DefaultButton(title: "listenAgain".loc(currentLanguage), dismissOnTap: false) {
                    self.audioPlayer?.stop()
                    self.audioPlayer?.currentTime = 0
                    self.audioPlayer?.prepareToPlay()
                    self.playAudio()
                    self.setupAudioAction()
                }
                
                let cancelButton = CancelButton(title: "CANCEL") {
                    self.stopAudio()
                    self.setupAudioAction()
                    self.checkToShowReview()
                }
                if currentQuestionSet!.part <= 4 {
                    hintPopup?.addButtons([cancelButton, okButton])
                } else {
                    hintPopup?.addButtons([cancelButton])
                }
                
                self.present(hintPopup!, animated: true, completion: nil)
                
                plusHintUsed()
            }
            return
        }
    }
    
    func checkToShowReview() {
        let hintUsed = getHintUsed()
        if hintUsed == 3 || hintUsed == 40 || hintUsed == 100 || hintUsed == 190 ||  hintUsed == 290 {
            showReview()
        }
    }
    
    func getHintUsed() -> Int {
        let prefs = UserDefaults.standard
        if prefs.object(forKey: Constant.KEY_HINT_USED) == nil {
            return 0
        } else {
            return prefs.integer(forKey: Constant.KEY_HINT_USED)
        }
    }
    
    func plusHintUsed() {
        let prefs = UserDefaults.standard
        if prefs.object(forKey: Constant.KEY_HINT_USED) == nil {
            prefs.set(1, forKey: Constant.KEY_HINT_USED)
        } else {
            let oldValue = prefs.integer(forKey: Constant.KEY_HINT_USED)
            if oldValue <= hintUsedWillShowReview {
                prefs.set(oldValue + 1, forKey: Constant.KEY_HINT_USED)
            }
        }
    }
    
    func showReview() {
        SKStoreReviewController.requestReview()
    }
    
    func getHintToShow(_ lang: String, _ hint: String?, _ hintVn: String?) -> String? {
        if lang == Constant.LANG_EN && hint != nil && !hint!.isEmpty {
            return hint
        }
        if hintVn != nil && !hintVn!.isEmpty {
            return hintVn
        }
        return hint
    }
    
    func setupAutoNextAction() {
        var autoNextImage = UIImage(named: "ic-auto-next")
        
        let prefs = UserDefaults.standard
        if prefs.object(forKey: Constant.KEY_AUTO_NEXT) == nil {
            autoNextImage = autoNextImage?.alpha(0.5)
        } else {
            let currentValue = prefs.bool(forKey: Constant.KEY_AUTO_NEXT)
            if currentValue {
                autoNextImage = autoNextImage?.alpha(1)
            } else {
                autoNextImage = autoNextImage?.alpha(0.5)
            }
        }
        let action = UIBarButtonItem(image: autoNextImage, style: .plain, target: self, action: #selector(autoNextClick))
        if navigationItem.rightBarButtonItems == nil || navigationItem.rightBarButtonItems!.isEmpty {
            navigationItem.rightBarButtonItems = [action]
        } else {
            navigationItem.rightBarButtonItems?.remove(at: 0)
            navigationItem.rightBarButtonItems?.insert(action, at: 0)
        }
    }
    
    func setupHideHeaderAction(_ isShowing: Bool) {
        let showImage = UIImage(named: "ic-show")
        let show = UIBarButtonItem(image: showImage, style: .plain, target: self, action: #selector(showHeaderClick))
        
        let hideImage = UIImage(named: "ic-hide")
        let hide = UIBarButtonItem(image: hideImage, style: .plain, target: self, action: #selector(hideHeaderClick))
        
        if navigationItem.rightBarButtonItems!.count > 1 {
            navigationItem.rightBarButtonItems?.remove(at: 1)
        }
        if let image = currentQuestionSet?.image, let desc = currentQuestionSet?.descriptionText, !image.isEmpty || !desc.isEmpty {
            if isShowing {
                navigationItem.rightBarButtonItems?.insert(hide, at: 1)
            } else {
                navigationItem.rightBarButtonItems?.insert(show, at: 1)
            }
        }
    }
    
    @objc func showHeaderClick() {
        setupHideHeaderAction(true)
        if let image = currentQuestionSet?.image, !image.isEmpty {
            if headerImage.visibility == .gone {
                headerImage.visibility = .visible
            }
        }
        if let desc = currentQuestionSet?.descriptionText, !desc.isEmpty {
            if webDescription.visibility == .gone {
                webDescription.visibility = .visible
            }
        }
    }
    
    @objc func hideHeaderClick() {
        setupHideHeaderAction(false)
        if let image = currentQuestionSet?.image, !image.isEmpty {
            if headerImage.visibility != .gone {
                headerImage.visibility = .gone
            }
        }
        if let desc = currentQuestionSet?.descriptionText, !desc.isEmpty {
            if webDescription.visibility != .gone {
                webDescription.visibility = .gone
            }
        }
    }
    
    func setupAudioAction() {
        let resumeImage = UIImage(named: "ic-resume")
        let resume = UIBarButtonItem(image: resumeImage, style: .plain, target: self, action: #selector(resumeClick))
        
        let pauseImage = UIImage(named: "ic-pause")
        let pause = UIBarButtonItem(image: pauseImage, style: .plain, target: self, action: #selector(pauseClick))
        
        if let image = currentQuestionSet?.image, let desc = currentQuestionSet?.descriptionText, !image.isEmpty || !desc.isEmpty {
            if navigationItem.rightBarButtonItems!.count > 2 {
                navigationItem.rightBarButtonItems?.remove(at:2)
            }
        } else {
            if navigationItem.rightBarButtonItems!.count > 1 {
                navigationItem.rightBarButtonItems?.remove(at:1)
            }
        }
        
        if !isFullTest {
            if let isPlaying = audioPlayer?.isPlaying {
                if isPlaying {
                    navigationItem.rightBarButtonItems?.append(pause)
                } else {
                    navigationItem.rightBarButtonItems?.append(resume)
                }
            }
        }
    }
    
    @objc func resumeClick() {
        audioPlayer?.prepareToPlay()
        playAudio()
        setupAudioAction()
    }
    
    @objc func pauseClick() {
        audioPlayer?.pause()
        setupAudioAction()
    }
    
    @objc func autoNextClick() {
        let currentLanguage = TextUtil.loadLanguage()
        var message = "autoNextEnabled".loc(currentLanguage)
        let prefs = UserDefaults.standard
        if prefs.object(forKey: Constant.KEY_AUTO_NEXT) == nil {
            prefs.set(true, forKey: Constant.KEY_AUTO_NEXT)
        } else {
            let currentValue = prefs.bool(forKey: Constant.KEY_AUTO_NEXT)
            prefs.set(!currentValue, forKey: Constant.KEY_AUTO_NEXT)
            if currentValue {
                message = "autoNextDisabled".loc(currentLanguage)
            }
        }
        setupAutoNextAction()
        showToast(message)
    }
    
    func initWebViewPart() {
        if let descriptionText = currentQuestionSet?.descriptionText, !descriptionText.isEmpty {
            var headerString = "<header><meta name='viewport' content='width=device-width, initial-scale=1.0, maximum-scale=1.0, minimum-scale=1.0'></header>"
            headerString.append(descriptionText)
            webDescription.loadHTMLString(headerString, baseURL: Bundle.main.bundleURL)
            webDescription.visibility = .visible
        } else {
            webDescription.visibility = .gone
        }
    }

    func initImagePart() {
        if let imageName = currentQuestionSet?.image, !imageName.isEmpty {
            headerImage.image = UIImage(named: imageName)
            headerImage.visibility = .visible
        } else {
            headerImage.visibility = .gone
        }
    }
    
    func hideAudioIfNeeded() {
        if let mp3Name = currentQuestionSet?.mp3, mp3Name.isEmpty {
            audioSlider.visibility = .gone
        } else {
            audioSlider.visibility = .visible
        }
    }

    func initAudioPart() {
        hideAudioIfNeeded()
        if let mp3Name = currentQuestionSet?.mp3, !mp3Name.isEmpty {
            initAudio(name: mp3Name)
            playAudio()
        } else {
            audioPlayer?.pause()
            audioPlayer = nil
            audioTimer?.invalidate()
            audioTimer = nil
        }
    }

    func initAudioTimer() {
        audioTimer?.invalidate()
        audioTimer = Timer.scheduledTimer(timeInterval: 0.1, target: self, selector: #selector(updateAudioSlider), userInfo: nil, repeats: true)
    }

    @objc func updateAudioSlider() {
        if let player = audioPlayer {
            audioSlider.value = Float(player.currentTime)
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        audioTimer?.invalidate()
        if audioPlayer != nil {
            audioSlider.value = Float(audioPlayer!.duration)
        }
        setupAudioAction()
        
        let prefs = UserDefaults.standard
        if prefs.object(forKey: Constant.KEY_AUTO_NEXT) != nil && prefs.bool(forKey: Constant.KEY_AUTO_NEXT) {
            nextQuestionSet()
        }
    }

    func allowAudioInBackground() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers, .allowAirPlay])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print(error)
        }
    }

    func initAudio(name: String) {
        if let path = Bundle.main.path(forResource: name, ofType: "mp3") {
            do {
                audioPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
                allowAudioInBackground()
                if let player = audioPlayer {
                    player.prepareToPlay()
                    player.delegate = self
                    audioSlider.maximumValue = Float(player.duration)
                }
            } catch {
                print(error)
            }
        }
    }

    func playAudio() {
        audioPlayer?.play()
        initAudioTimer()
    }

    func stopAudio() {
        audioPlayer?.stop()
        audioTimer?.invalidate()
    }

    @IBAction func onSliderChanged(_ sender: Any) {
        audioPlayer?.stop()
        audioPlayer?.currentTime = TimeInterval(audioSlider.value)
        audioPlayer?.prepareToPlay()
        playAudio()
        setupAudioAction()
    }
    
}

extension TestingController: OptionCellListener {
    
    fileprivate func showHintButton() {
        if hintButton.visibility != .visible {
            hintButton.visibility = .visible
            
            if AppUtil.isRemovedAds() {
                return
            }
            
            var badgeText: String = ""
            let prefs = UserDefaults.standard
            if prefs.object(forKey: Constant.KEY_HINT) == nil {
                prefs.set(AdsUtil.randomHintAds(), forKey: Constant.KEY_HINT)
                badgeText = String(AdsUtil.randomHintAds())
            } else {
                let currentValue = prefs.integer(forKey: Constant.KEY_HINT)
                if currentValue > 0 {
                    badgeText = String(currentValue)
                } else {
                    badgeText = badgeFreeText
                }
            }
            hintButton.badgeString = badgeText
            
            if let color = badgeColor {
                hintButton.badgeBackgroundColor = color
            }
        }
    }
    
    fileprivate func completeFullTest() {
        let listeningScore = ScoreUtil.getListeningScore(correctQuestionCount: correctListeningCount)
        let readingScore = ScoreUtil.getReadingScore(correctQuestionCount: correctReadingCount)
        
        let popupView = WebViewController(nibName: "WebViewController", bundle: nil)
        let currentLanguage = TextUtil.loadLanguage()
        popupView.titleContent = "congrats".loc(currentLanguage)
        popupView.htmlContent = "<div style='background-color:#d50000;color:white;text-align:center;padding:8px;'>TOTAL SCORE</div><div style='background-color:#1E3C57;padding:24px;color:white'><div style='text-align:center'><span style='padding:6px 16px;font-size:30px;border:1.5px solid;border-radius:50%'>\(listeningScore + readingScore)</span></div></div><div style='background-color:#00bfa5;color:white;text-align:center; padding:6px;margin-top:16px'>LISTENING</div><div style='background-color:#1E3C57;padding:24px;color:white'><div style='text-align:center'><span style='padding:6px 16px;font-size:26px;border:1.5px solid;border-radius:50%'>\(listeningScore)</span><div style='margin-top:16px'>\(correctListeningCount)/100</div></div></div><div style='background-color:#aa00ff;color:white;text-align:center; padding:6px;margin-top:16px'>READING</div><div style='background-color:#1E3C57;padding:24px;color:white'><div style='text-align:center'><span style='padding:6px 16px;font-size:26px;border:1.5px solid;border-radius:50%'>\(readingScore)</span><div style='margin-top:16px'>\(correctReadingCount)/100</div></div></div>"
        
        let popup = PopupDialog(viewController: popupView,
                                buttonAlignment: .horizontal,
                                transitionStyle: .bounceDown,
                                tapGestureDismissal: false,
                                panGestureDismissal: false)
        
        
        let okButton = DefaultButton(title: "backToHome".loc(currentLanguage)) {
            self.goHome()
        }
        
        popup.addButtons([okButton])
        self.present(popup, animated: true, completion: nil)
        stopFullTestTimer()
        self.stopAudio()
    }
    
    fileprivate func showNextBackIfNeeded() {
        if isFullTest {
            backButton.visibility = .gone
        } else {
            backButton.visibility = .visible
        }
        nextButton.visibility = .visible
    }
    
    func onOptionClick(questionOrder: Int, isCorrect: Bool, selectedIndex: Int, keyIndex: Int) {
        let cellIndex = questionOrder - 1
        tempAnswers[cellIndex].answerCount = tempAnswers[cellIndex].answerCount + 1
        tempAnswers[cellIndex].correct = isCorrect
        tempAnswers[cellIndex].selectedIndex = selectedIndex
        tempAnswers[cellIndex].keyIndex = keyIndex
        if isCorrect {
            saveCorrectedForFullTest()
            saveCorrected(questionOrder)
        }
        if canHint() {
            showHintButton()
        }
        showNextBackIfNeeded()
    }
    
    func canHint() -> Bool {
        let currentLanguage = TextUtil.loadLanguage()
        let hint = currentQuestionSet?.hint
        let hintVn = currentQuestionSet?.hintVn
        if let realHint = getHintToShow(currentLanguage, hint, hintVn), !realHint.isEmpty {
            return !isFullTest
        }
        return  false
    }
    
    func saveCorrectedForFullTest() {
        if isFullTest {
            if currentQuestionSet!.part <= 4 {
                
                correctListeningCount += 1
            } else {
                correctReadingCount += 1
            }
        }
    }
    
    fileprivate func saveCorrected(_ questionOrder: Int) {
        if let questions = currentQuestionSet?.questions {
            let matchedQuestions = Array(questions).filter {$0.questionOrder == questionOrder}
            if matchedQuestions.count == 1 {
                matchedQuestions[0].corrected = matchedQuestions[0].corrected + 1
                PersistenceService.saveContext()
            }
        }
    }
    
    func updateTableViewContentInset(tableView: UITableView) {
        let viewHeight: CGFloat = view.frame.size.height
        let tableViewContentHeight: CGFloat = tableView.contentSize.height
        let marginHeight: CGFloat = (viewHeight - tableViewContentHeight) / 2.0
        
        tableView.contentInset = UIEdgeInsets(top: marginHeight, left: 0, bottom:  -marginHeight, right: 0)
    }
}

extension Date {
    var millisecondsSince1970:Int {
        return Int((self.timeIntervalSince1970 * 1000.0).rounded())
    }
    
    init(milliseconds:Int) {
        self = Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
    }
}

extension UIViewController {
    enum FullAdDismissAction {
        case back
        case next
        case home
        case none
    }
}

extension UIView {
    
    enum Visibility {
        case visible
        case invisible
        case gone
    }
    
    var visibility: Visibility {
        get {
            let constraint = (self.constraints.filter{$0.firstAttribute == .height && $0.constant == 0}.first)
            if let constraint = constraint, constraint.isActive {
                return .gone
            } else {
                return self.isHidden ? .invisible : .visible
            }
        }
        set {
            if self.visibility != newValue {
                self.setVisibility(newValue)
            }
        }
    }
    
    private func setVisibility(_ visibility: Visibility) {
        let constraint = (self.constraints.filter{$0.firstAttribute == .height && $0.constant == 0}.first)
        
        switch visibility {
        case .visible:
            constraint?.isActive = false
            self.isHidden = false
            break
        case .invisible:
            constraint?.isActive = false
            self.isHidden = true
            break
        case .gone:
            if let constraint = constraint {
                constraint.isActive = true
            } else {
                let constraint = NSLayoutConstraint(item: self, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .height, multiplier: 1, constant: 0)
                self.addConstraint(constraint)
                constraint.isActive = true
            }
            self.isHidden = true
        }
    }
}

extension UITableView{
    
    func hasRowAtIndexPath(indexPath: IndexPath) -> Bool {
        return indexPath.section < numberOfSections && indexPath.row < numberOfRows(inSection: indexPath.section)
    }
    
    func scrollToTop(_ animated: Bool = false) {
        let indexPath = IndexPath(row: 0, section: 0)
        if hasRowAtIndexPath(indexPath: indexPath) {
            scrollToRow(at: indexPath, at: .top, animated: animated)
        }
    }
}

extension UIViewController {
    static let DELAY_SHORT = 1.5
    static let DELAY_LONG = 3.0
    
    func showToast(_ text: String, delay: TimeInterval = DELAY_LONG) {
        let label = ToastLabel()
        label.backgroundColor = UIColor(white: 0, alpha: 0.5)
        label.textColor = .white
        label.textAlignment = .center
        label.font = UIFont.systemFont(ofSize: 15)
        label.alpha = 0
        label.text = text
        label.clipsToBounds = true
        label.layer.cornerRadius = 20
        label.numberOfLines = 0
        label.textInsets = UIEdgeInsets(top: 10, left: 15, bottom: 10, right: 15)
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        
        let saveArea = view.safeAreaLayoutGuide
        label.centerXAnchor.constraint(equalTo: saveArea.centerXAnchor, constant: 0).isActive = true
        label.leadingAnchor.constraint(greaterThanOrEqualTo: saveArea.leadingAnchor, constant: 15).isActive = true
        label.trailingAnchor.constraint(lessThanOrEqualTo: saveArea.trailingAnchor, constant: -15).isActive = true
        label.bottomAnchor.constraint(equalTo: saveArea.bottomAnchor, constant: -30).isActive = true
        
        UIView.animate(withDuration: 0.5, delay: 0, options: .curveEaseIn, animations: {
            label.alpha = 1
        }, completion: { _ in
            UIView.animate(withDuration: 0.5, delay: delay, options: .curveEaseOut, animations: {
                label.alpha = 0
            }, completion: {_ in
                label.removeFromSuperview()
            })
        })
    }
}

extension TestingController: GADInterstitialDelegate {
    
    func interstitialDidDismissScreen(_ ad: GADInterstitial) {
        switch fullAdDismissAction {
            case .next, .back:
                audioPlayer?.prepareToPlay()
                playAudio()
            default:
                print("No action")
        }
        setupAudioAction()
        initFullScreenAd()
    }
}

extension TestingController: GADRewardBasedVideoAdDelegate {
    func rewardBasedVideoAd(_ rewardBasedVideoAd: GADRewardBasedVideoAd,
                            didRewardUserWith reward: GADAdReward) {
        isRewarded = true
    }
    
    func rewardBasedVideoAdDidReceive(_ rewardBasedVideoAd:GADRewardBasedVideoAd) {
        print("Reward based video ad is received.")
    }
    
    func rewardBasedVideoAdDidOpen(_ rewardBasedVideoAd: GADRewardBasedVideoAd) {
        print("Opened reward based video ad.")
        stopAudio()
    }
    
    func rewardBasedVideoAdDidStartPlaying(_ rewardBasedVideoAd: GADRewardBasedVideoAd) {
        print("Reward based video ad started playing.")
    }
    
    func rewardBasedVideoAdDidCompletePlaying(_ rewardBasedVideoAd: GADRewardBasedVideoAd) {
        print("Reward based video ad has completed.")
        isRewarded = true
    }
    
    func rewardBasedVideoAdDidClose(_ rewardBasedVideoAd: GADRewardBasedVideoAd) {
        print("Reward based video ad is closed.")
        if isRewarded {
            let newHintCount = AdsUtil.randomHintAds()
            UserDefaults.standard.set(newHintCount, forKey: Constant.KEY_HINT)
            hintButton.badgeString = String(newHintCount)
            showHint()
        } else {
            hintButton.badgeString = badgeFreeText
        }
        reloadRewardedAd()
        setupAudioAction()
    }
    
    func rewardBasedVideoAdWillLeaveApplication(_ rewardBasedVideoAd: GADRewardBasedVideoAd) {
        print("Reward based video ad will leave application.")
    }
    
    func rewardBasedVideoAd(_ rewardBasedVideoAd: GADRewardBasedVideoAd,
                            didFailToLoadWithError error: Error) {
        print("Reward based video ad failed to load.")
    }
}
