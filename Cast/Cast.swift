import Cocoa
import SwiftyJSON
import RxSwift
import RxCocoa
import KeychainAccess


let pasteboardTypes = [NSFilenamesPboardType]
var userDefaults = UserDefaults()


enum PBError: ErrorType {
    case UnreadableData
}


enum PBItem {
    case Text(String) //to Gist
    case Image(NSImage) //to Imgur
    case File(NSURL) //to Dropbox/iCloud
}


enum ShortenService: Int {
    case Isgd = 0
    case Hive
    case Bitly
    case Supr
    case Vgd

    func makeURL(url URL: NSURL) -> (String, String?) {
        switch self {
        case .Isgd:
            return ("https://is.gd/create.php?format=json&url=" + URL.relativeString!, "shorturl")

        case .Vgd:
            return ("https://v.gd/create.php?format=json&url=" + URL.relativeString!, "shorturl")

        case .Hive:
            return ("https://hive.am/api?api=spublic&url=" + URL.relativeString!, "short")

        case .Bitly:
            return ("https://api-ssl.bitly.com/v3/shorten?access_token=" + bitlyOAuth2Token + "&longUrl=" + URL.relativeString!, nil)

        case .Supr:
            return ("http://su.pr/api/shorten?longUrl=" + URL.relativeString!, "shortUrl")
        }
    }

    static func popupMenuList() -> NSMenu {
        return buildMenuPopup(source:
        [
                (Isgd.rawValue, "Isgd", "is.gd"),
                (Hive.rawValue, "Hive.am", "hive.am"),
                (Bitly.rawValue, "Bitly", "bit.ly"),
                (Supr.rawValue, "Supr", ""),
                (Vgd.rawValue, "Vgd", ""),
        ])
    }
}


enum ServiceKey: String {
    case Gist
    case GistIsPublic
    case Shorten
    case Image
    case RecentActions
}


enum GistService: Int {
    case GitHub = 0
    case PasteBin
    case NoPaste
    case TinyPaste

    static func popupMenuList() -> NSMenu {
        return buildMenuPopup(source:
        [
                (GitHub.rawValue, "GitHub", ""),
                (PasteBin.rawValue, "PasteBin", ""),
                (NoPaste.rawValue, "NoPaste", ""),
                (TinyPaste.rawValue, "TinyPaste", ""),
        ])
    }
}


enum ConnectionError: ErrorType {
    case InvalidData(String)
    case NoResponse(String)
    case NotAuthenticated(String)
    case StatusCode(Int)
}


//------------------------------------------------------------------------------------------


struct UserDefaults {
    let userDefaults = NSUserDefaults.standardUserDefaults()

    init() {
        registerDefaults()
    }

    subscript(key: ServiceKey) -> AnyObject {
        get {
            guard let value = userDefaults.objectForKey(key.rawValue) else {
                fatalError("You forgot to provide a default value for all ServiceKey cases")
            }
            return value
        }
        set {
            userDefaults.setObject(newValue, forKey: key.rawValue)
        }
    }

    /// Default values to provide in absense of user provided defaults
    func registerDefaults() {
        let registeredDefaults: [String:AnyObject] = [
                ServiceKey.Gist.rawValue: GistService.GitHub.rawValue,
                ServiceKey.GistIsPublic.rawValue: false,
                ServiceKey.Shorten.rawValue: ShortenService.Isgd.rawValue,
                ServiceKey.Image.rawValue: "Imgur",
                ServiceKey.RecentActions.rawValue: [],
        ]

        userDefaults.registerDefaults(registeredDefaults)
    }
}


struct OAuthOptions {
    /// Required. The client ID you received from GitHub when you registered.
    var clientID: String = ""

    /// Required. The client secret you received from GitHub when you registered.
    var clientSecret: String = ""

    /// Redirect users to request GitHub access
    var authURL: String = "https://github.com/login/oauth/authorize/"

    /// The URL in your app where users will be sent after authorization.
    var redirectURL: String = "cast://oauth"

    /// Exchange authURL: code for an access token
    var tokenURL: String = "https://github.com/login/oauth/access_token"

    init(id: String, secret: String) {
        self.clientID = id
        self.clientSecret = secret
    }
}


//------------------------------------------------------------------------------------------


struct GistOptions {
    let githubAPI = NSURL(string: "https://api.github.com/gists")!
    let pastebinAPI = NSURL(string: "https://api.pastebin.com/gists")!
    var gistService: GistService = .GitHub
    var publicGist: Bool {
        return userDefaults[.GistIsPublic] as! Bool
    }
    var fileName: String = "Casted.swift"
    var description: String = "Generated with Cast (cast.lfaoro.com)"

    // This can't be set unless the user is logged in
    var gistIsUpdatable: Bool = false
    var updateGist: Bool {
        get {
            if gistID != nil && gistIsUpdatable == true {
                return true
            } else {
                return false
            }
        }
        set {
            gistIsUpdatable = newValue
        }
    }
    var connectionURL: NSURL {
        get {
            switch gistService {
            case .GitHub:
                return githubAPI
            case .PasteBin:
                return pastebinAPI
            default: fatalError("\(__FUNCTION__)")
            }
        }
    }
    var gistID: String? {
        get {
            let userDefaults = NSUserDefaults.standardUserDefaults()
            if OAuthClient.getToken() != nil {
                return userDefaults.stringForKey("gistID")
            } else {
                userDefaults.removeObjectForKey("gistID")
                return nil
            }
        }
        set {
            if OAuthClient.getToken() != nil {
                let userDefaults = NSUserDefaults.standardUserDefaults()
                userDefaults.setObject(newValue, forKey: "gistID")
            }
        }
    }
}


class GistClient {
    var options: GistOptions

    init(options: GistOptions) {
        self.options = options
    }

    func createGist(content: String) -> ErrorType? {
        self.setGist(content: content)
        .debug("setGist")
        .retry(3)
        .flatMap {
            shorten(withUrl: $0)
        }
        .subscribe {
            event in
            switch event {
            case .Next(let url):
                if let url = url {
                    putInPasteboard(items: [url])
                    app.userNotification.pushNotification(openURL: url)
                } else {
                    app.userNotification.pushNotification(error: "Unable to Shorten URL")
                }

            case .Completed:
                //app.statusBarItem.menu = createMenu(self)
                break

            case .Error(let error):
                app.userNotification.pushNotification(error: String(error))
            }
        }

        return nil
    }

    func setGist(content content: String) -> Observable<NSURL> {
        let HTTPBody = [
                "description": self.options.description,
                "public": !self.options.publicGist,
                "files": [self.options.fileName: ["content": content]],
        ]

        return create {
            stream in
            var request: NSMutableURLRequest

            if self.options.updateGist {
                let updateURL = self.options.connectionURL.URLByAppendingPathComponent(self.options.gistID!)
                request = NSMutableURLRequest(URL: updateURL)
                request.HTTPMethod = "PATCH"
            } else {
                request = NSMutableURLRequest(URL: self.options.connectionURL)
                request.HTTPMethod = "POST"
            }

            request.HTTPBody = try! JSON(HTTPBody).rawData()
            request.addValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

            if let token = OAuthClient.getToken() {
                request.addValue("token \(token)", forHTTPHeaderField: "Authorization")
            }

            let session = NSURLSession.sharedSession()
            let task = session.dataTaskWithRequest(request) {
                (data, response, error) in
                if let data = data, response = response as? NSHTTPURLResponse {
                    if !((200 ..< 300) ~= response.statusCode) {
                        sendError(stream, ConnectionError.StatusCode(response.statusCode))
                        print(response)
                    }

                    let jsonData = JSON(data: data)
                    if let gistURL = jsonData["html_url"].URL, gistID = jsonData["id"].string {
                        self.options.gistID = gistID

                        sendNext(stream, gistURL)
                        sendCompleted(stream)
                    } else {
                        sendError(stream, ConnectionError.InvalidData(
                        "Unable to read data received from \(self.options.connectionURL)"))
                    }
                } else {
                    sendError(stream, ConnectionError.NoResponse(error!.localizedDescription))
                }
            }

            task.resume()

            return NopDisposable.instance
        }
    }
}


class OAuthClient: NSObject {
    var options: OAuthOptions
    var eventHandler: NSAppleEventManager?

    required init(options opt: OAuthOptions) {
        self.options = opt
        super.init()
        self.eventHandler = registerEventHandlerForURL(handler: self)
    }

    /// Remove the access token from the Key chain
    /// and send the user to the revoke token web page
    class func revoke() -> NSError? {
        let keychain = Keychain(service: "com.lfaoro.cast.github-token")
        let revokeURL = NSURL(string: "https://github.com/settings/connections/applications/" + "ef09cfdbba0dfd807592")!

        NSWorkspace.sharedWorkspace().openURL(revokeURL)

        return keychain.remove("token")
    }

    /// Retrieve the access token from the Keychain
    class func getToken() -> String? {
        let keychain = Keychain(service: "com.lfaoro.cast.github-token")

        return keychain.get("token")
    }

    //MARK:- Internal
    func oauthRequest() -> Void {
        let oauthQuery = [
                NSURLQueryItem(name: "client_id", value: options.clientID),
                NSURLQueryItem(name: "redirect_uri", value: "cast://oauth"),
                NSURLQueryItem(name: "scope", value: "gist")
                //      NSURLQueryItem(name: "state", value: "\(NSUUID().UUIDString)"),
        ]

        let oauthComponents = NSURLComponents()
        oauthComponents.scheme = "https"
        oauthComponents.host = "github.com"
        oauthComponents.path = "/login/oauth/authorize/"
        oauthComponents.queryItems = oauthQuery

        NSWorkspace.sharedWorkspace().openURL(oauthComponents.URL!)
    }

    func exchangeCodeForAccessToken(code: String) -> Observable<String> {

        let oauthQuery = [
                NSURLQueryItem(name: "client_id", value: options.clientID),
                NSURLQueryItem(name: "client_secret", value: options.clientSecret),
                NSURLQueryItem(name: "code", value: code),
                NSURLQueryItem(name: "redirect_uri", value: "cast://oauth"),
                //      NSURLQueryItem(name: "state", value: "\(NSUUID().UUIDString)"),
        ]

        let oauthComponents = NSURLComponents()
        oauthComponents.scheme = "https"
        oauthComponents.host = "github.com"
        oauthComponents.path = "/login/oauth/access_token"
        oauthComponents.queryItems = oauthQuery

        let request = NSMutableURLRequest(URL: oauthComponents.URL!)
        request.HTTPMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        return create {
            stream in
            let session = NSURLSession.sharedSession()
            session.dataTaskWithRequest(request) {
                (data, response, error) -> Void in
                if let data = data {
                    if let token = JSON(data: data)["access_token"].string {
                        sendNext(stream, token)
                        sendCompleted(stream)
                    } else {
                        sendError(stream, ConnectionError.InvalidData("No Token :((("))
                    }
                } else {
                    sendError(stream, ConnectionError.NoResponse(error!.localizedDescription))
                }
            }.resume()

            return NopDisposable.instance
        }
    }

    /// Registers URL callback event
    func registerEventHandlerForURL(handler object: AnyObject) -> NSAppleEventManager {
        let eventManager: NSAppleEventManager = NSAppleEventManager.sharedAppleEventManager()
        eventManager.setEventHandler(object,
                andSelector: "handleURLEvent:",
                forEventClass: AEEventClass(kInternetEventClass),
                andEventID: AEEventClass(kAEGetURL))
        return eventManager
    }

    /// Selector of `registerEventHandlerForURL`
    func handleURLEvent(event: NSAppleEventDescriptor) -> Void {

        if let callback = event.descriptorForKeyword(AEEventClass(keyDirectObject))?.stringValue {
            // thank you mikeash!

            if let code = NSURLComponents(string: callback)?.queryItems?[0].value {
                exchangeCodeForAccessToken(code)
                .debug()
                .retry(3)
                .subscribe {
                    event in
                    switch event {
                    case .Next(let token):
                        let keychain = Keychain(service: "com.lfaoro.cast.github-token")
                        keychain["token"] = token
                    case .Completed:
                        Swift.print("completed")
                        app.statusBarItem.menu = createMenu(app.menuSendersAction)
                        app.userNotification.pushNotification(error: "GitHub Authentication",
                                description: "Successfully authenticated!")
                    case .Error(let error):
                        Swift.print("\(error)")
                    }
                }
            } else {
                fatalError("Impossible to extract code")
            }
        } else {
            fatalError("No callback")
        }
    }
}


func shorten(withUrl url: NSURL) -> Observable<String?> {
    //TODO: Fix it => keepRecent(URL: URL)

    let session = NSURLSession.sharedSession()
    let service = ShortenService(rawValue: userDefaults[.Shorten] as! Int)! //TODO: Fix me

    let (_url, responseKey) = service.makeURL(url: url)

    return session.rx_JSON(NSURL(string: _url)!) //TODO: Fix me (!)
    .debug("Shortening with: \(service)")
    .retry(3)
    .map {
        switch service {
        case .Bitly:
            guard let data = $0["data"] as? NSDictionary, url = data["url"] as? String else {
                return nil
            }
            return url

        default:
            return $0[responseKey!] as? String
        }
    }
}

//------------------------------------------------------------------------------------------


class MenuActionHandler: NSObject {
    var appModel: AppModelProtocol?
    //dependency injection
    var gistOptions: GistOptions
    let gist: GistClient

    override init() {
        self.gistOptions = GistOptions()
        self.gist = GistClient(options: gistOptions)
    }

    func shareClipboardContentsAction(sender: NSMenuItem) {
        let _ = getPasteboardItems()
        .debug("getPasteboardItems")
        .subscribe(next: {
            value in

            switch value {
            case .Text(let pbContents):
                self.gist.createGist(pbContents)
                self.gistOptions.updateGist = false

            case .Image(_ ):
                app.userNotification
                .pushNotification(error: "Not yet Supported :(",
                        description: "Image support is on the way, hold tight!")

            case .File(let file):
                app.userNotification
                .pushNotification(error: "Not yet Supported :(",
                        description: "File sharing support is on the way, hold tight!")
                print(file.path!)
            }
        })
    }

    func updateGistAction(sender: NSMenuItem) {
        self.gistOptions.updateGist = true
        shareClipboardContentsAction(sender)
    }

    //    func shortenURLAction(sender: NSMenuItem) {
    //
    //        let _ = getPasteboardItems()
    //        .debug("getPasteboardItems")
    //        .subscribe(next: {
    //            value in
    //            switch value {
    //            case .Text(let item):
    //                guard let url = NSURL(string: item) else {
    //                    fallthrough
    //                }
    //                shorten(withUrl: url)
    //                .subscribe {
    //                    event in
    //                    switch event {
    //                    case .Next(let shortenedURL):
    //                        guard let URL = shortenedURL else {
    //                            fallthrough
    //                        }
    //                        putInPasteboard(items: [URL])
    //                        app.userNotification.pushNotification(openURL: URL,
    //                                title: "Shortened with \(userDefaults[.RecentActions])")
    //
    //                    case .Error:
    //                        app.userNotification.pushNotification(
    //                        error: "Unable to shorten URL",
    //                                description: "\(url.standardizedURL!)"
    //                        )
    //
    //                    case .Completed:
    //                        print("completed")
    //                    }
    //                }
    //
    //            default:
    //                app.userNotification.pushNotification(error: "Not a valid URL")
    //            }
    //        })
    //    }

    func loginToGithubAction(sender: NSMenuItem) {
        app.oauth.oauthRequest()
    }

    func logoutFromGithubAction(sender: NSMenuItem) {

        if let error = OAuthClient.revoke() {
            app.userNotification.pushNotification(error: error.localizedDescription)
        } else {
            app.statusBarItem.menu = createMenu(app.menuSendersAction)
            app.userNotification.pushNotification(error: "GitHub Authentication",
                    description: "API key revoked internally")
        }
    }

    func recentUploadsAction(sender: NSMenuItem) {
        if let url = sender.representedObject as? NSURL {
            NSWorkspace.sharedWorkspace().openURL(url)
        } else {
            fatalError("No link in recent uploads")
        }
    }

    func clearItemsAction(sender: NSMenuItem) {
        appModel?.clearRecentUploads()
    }

    func startAtLoginAction(sender: NSMenuItem) {
        if sender.state == 0 {
            sender.state = 1
        } else {
            sender.state = 0
        }
    }

    func optionsAction(sender: NSMenuItem) {
        NSApp.activateIgnoringOtherApps(true)
        app.optionsWindowController.showWindow(nil)

        app.openPreferenceWindow()
    }
}


func putInPasteboard(items items: [String]) -> Bool {
    let pb = NSPasteboard.generalPasteboard()

    pb.clearContents()

    return pb.writeObjects(items)
}

func getPasteboardItems() -> Observable<PBItem> {
    let pasteBoard = NSPasteboard.generalPasteboard()
    let classes: [AnyClass] = [NSURL.self, NSString.self, NSAttributedString.self, NSImage.self]
    let options: [String:AnyObject] = [:]
    let copiedItems = pasteBoard.readObjectsForClasses(classes, options: options)

    return create {
        stream in if let items = copiedItems {
            for item in items {
                switchOnItem(stream, item: item)
            }
            sendCompleted(stream)
            // Question: SHOULD THERE BE A RETURN HERE?
        }

        sendError(stream, PBError.UnreadableData)

        return NopDisposable.instance
    }
}

func switchOnItem(stream: ObserverOf<PBItem>, item: AnyObject) {
    switch item {
    case let image as NSImage:
        sendNext(stream, .Image(image))

    case let text as NSString:
        sendNext(stream, .Text(String(text)))

    case let attrText as NSAttributedString:
        sendNext(stream, .Text(attrText.string))

    case let file as NSURL:
        sendNext(stream, .File(file))

    default: //blow up
        preconditionFailure()
    }
}


//------------------------------------------------------------------------------------------


enum MenuSelectorAction: Selector {
    case UpdateGist = "updateGistAction:"
    case ShareClipboardContents = "shareClipboardContentsAction:"
    case RecentUploads = "recentUploadsAction:"
    case ClearItems = "clearItemsAction:"
    case ShortenURL = "shortenURLAction:"
    case LogOutFromGitHub = "logoutFromGitHubAction:"
    case LogInToGitHub = "loginToGitHubAction:"
    case Preferences = "optionsAction:"
    case Terminate = "terminateAction:"
}


func configureStatusBarItem(target target: MenuActionHandler) -> NSStatusItem {
    let item = NSStatusBar.systemStatusBar().statusItemWithLength(NSVariableStatusItemLength)
    item.button?.title = "Cast"
    let image = NSImage(named: "StatusBarIcon")
    image?.template = true
    item.button?.image = image
    item.button?.alternateImage = NSImage(named: "LFStatusBarAlternateIcon")
    item.button?.registerForDraggedTypes(pasteboardTypes)
    item.menu = createMenu(target)

    return item
}


func createRecentUploads(target: MenuActionHandler) -> NSMenuItem {
    let recentUploadsItem = NSMenuItem()
    recentUploadsItem.setItemWithTitle("Recent Actions", action: .RecentUploads, target: target)

    let subMenu = NSMenu(title: "Cast - Recent Actions Menu")

    let recentActions = appModel.recentActions //userDefaults[.RecentActions] as! [RecentAction]

    for each in recentActions {
        let m = NSMenuItem()
        let title = "This is a test \(each)"
        m.setItemWithTitle(title, action: .RecentUploads, target: target, representedObject: NSURL(string: each.url.relativeString!))
        subMenu.addItem(m)
    }

    subMenu.addSeparator()
    subMenu.addItemWithTitle("Clear Recents", action: .ClearItems, target: target)

    recentUploadsItem.submenu = subMenu
    return recentUploadsItem
}


func createMenu(target: MenuActionHandler) -> NSMenu {
    let menu = NSMenu(title: "Cast Menu")
    menu.addItemWithTitle("Share copied text", action: .ShareClipboardContents, key: "S", target: target)

    let gistOptions = GistOptions()
    if gistOptions.gistID != nil {
        menu.addItemWithTitle("Update latest gist", action: .UpdateGist, key: "U", target: target)
    }

    menu.addItemWithTitle("Shorten URL", action: .ShortenURL, key: "T", target: target)
    menu.addSeparator()

    let recentActions = appModel.recentActions //  userDefaults[.RecentActions] as! [RecentAction]
    if recentActions.count > 0 {
        menu.addItem(createRecentUploads(target))
    }

    let gitHubLoginItem = NSMenuItem()
    let title: String
    let action: MenuSelectorAction

    if OAuthClient.getToken() != nil {
        (title, action) = ("Logout from GitHub", .LogOutFromGitHub)
    } else {
        (title, action) = ("Login to GitHub", .LogInToGitHub)
    }
    gitHubLoginItem.setItemWithTitle(title, action: action, key: "L", target: target)

    menu.addSeparator()
    menu.addItemWithTitle("Options", action: .Preferences, key: "O", target: target)
    menu.addSeparator()
    menu.addItemWithTitle("Quit", action: .Terminate, key: "Q", target: target)

    return menu
}


//------------------------------------------------------------------------------------------


class UserNotifications: NSObject {
    var notificationCenter: NSUserNotificationCenter!
    var didActivateNotificationURL: NSURL?

    override init() {
        super.init()
        notificationCenter = NSUserNotificationCenter.defaultUserNotificationCenter()
        notificationCenter.delegate = self
    }

    func createNotification(title: String, subtitle: String) -> NSUserNotification {
        let n = NSUserNotification()
        n.title = title
        n.subtitle = subtitle
        n.informativeText = "Copied to your clipboard"
        n.actionButtonTitle = "Open URL"
        n.soundName = NSUserNotificationDefaultSoundName
        return n
    }

    func pushNotification(openURL url: String, title: String = "Casted to gist.GitHub.com") {
        didActivateNotificationURL = NSURL(string: url)!
        let notification = self.createNotification(title, subtitle: url)
        notificationCenter.deliverNotification(notification)
        startUserNotificationTimer() //IRC: calling from here doesn't work
    }

    func pushNotification(error error: String,
                          description: String = "An error occured, please try again.") {
        let n = NSUserNotification()
        n.title = error
        n.informativeText = description
        n.soundName = NSUserNotificationDefaultSoundName
        n.hasActionButton = false
        notificationCenter.deliverNotification(n)
        startUserNotificationTimer()
    }

    func startUserNotificationTimer() {
        print(__FUNCTION__)
        app.timer = NSTimer.scheduledTimerWithTimeInterval(5.0, target: self, selector: "removeUserNotifcationsAction:", userInfo: nil, repeats: false)
    }

    func removeUserNotifcationsAction(timer: NSTimer) {
        print(__FUNCTION__)
        notificationCenter.removeAllDeliveredNotifications()
        timer.invalidate()
    }
}


extension UserNotifications: NSUserNotificationCenterDelegate {
    func userNotificationCenter(center: NSUserNotificationCenter,
                                didActivateNotification notification: NSUserNotification) {
        print("notification pressed")
        if let url = didActivateNotificationURL {
            NSWorkspace.sharedWorkspace().openURL(url)
        } else {
            center.removeAllDeliveredNotifications()
        }
    }

    func userNotificationCenter(center: NSUserNotificationCenter,
                                shouldPresentNotification notification: NSUserNotification) -> Bool {
        return true
    }
}