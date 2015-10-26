import Cocoa


var appModel = AppModel()
let app = (NSApp.delegate as? AppDelegate)!


class RecentAction: NSObject, NSCoding {
    var desc: String
    var url: NSURL

    init(description: String, URL: NSURL) {
        self.desc = description
        self.url = URL
    }

    required init?(coder aDecoder: NSCoder) {
        self.desc = aDecoder.decodeObjectForKey("description") as! String
        self.url = aDecoder.decodeObjectForKey("url") as! NSURL
    }

    func encodeWithCoder(aCoder: NSCoder) {
        aCoder.encodeObject(desc, forKey: "description")
        aCoder.encodeObject(url, forKey: "url")
    }
}


protocol AppModelProtocol {
    func clearRecentUploads() -> Void
}


struct AppModel: AppModelProtocol {
    var recentActions: [RecentAction] = []
    var preferences: PreferencesModel?
    var userDefaults = UserDefaults()

    mutating func saveRecentAction(url: NSURL) {
        let description = String("\(url.host ?? "")\(url.path ?? "")".characters.prefix(30))
        recentActions.append(RecentAction(description: description, URL: url))
    }

    func clearRecentUploads() {
        fatalError("implement this")
    }

    func load() {
    }


    func save() {
    }
}


@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    var timer: NSTimer?
    var oauth: OAuthClient
    var statusBarItem: NSStatusItem!
    var menuSendersAction: MenuActionHandler!
    var userNotification: UserNotifications!
    var optionsWindowController: OptionsWindowController!
    var preferenceWindow: PreferencesController?
    var stubWindow: StubController?

    override init() {
        let options = OAuthOptions(id: "ef09cfdbba0dfd807592", secret: "ce7541f7a3d34c2ff5b20207a3036ce2ad811cc7")
        self.oauth = OAuthClient(options: options)
        super.init()
    }

    func applicationDidFinishLaunching(aNotification: NSNotification) -> Void {
        appModel.userDefaults.registerDefaults()
        for i in 0 ... 10 {
            appModel.saveRecentAction(NSURL(string: "http://www.test.com/thisis\(i).pop")!)
        }

        userNotification = UserNotifications()
        menuSendersAction = MenuActionHandler()
        menuSendersAction.appModel = appModel
        statusBarItem = configureStatusBarItem(target: menuSendersAction)

        optionsWindowController = OptionsWindowController()
        openPreferenceWindow()
        openStubWindow()
    }

    func updateMenu() -> () {
        statusBarItem.menu?.update()
    }

    func openPreferenceWindow() {
        if preferenceWindow == nil {
            preferenceWindow = PreferencesController()
        }
        if let p = preferenceWindow {
            p.showWindow(nil)
        }
    }

    func openStubWindow() {
        if stubWindow == nil {
            stubWindow = StubController()
        }
        if let p = stubWindow {
            p.showWindow(nil)
        }
    }

    func errorNotification(error: String) {

    }
}
