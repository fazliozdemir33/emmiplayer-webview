import Flutter
import UIKit
import WebKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // WKWebView için kalıcı cookie depolama garanti altına al
    // (HTTPCookieStorage ile WKHTTPCookieStore senkronize et)
    let cookieStore = WKWebsiteDataStore.default().httpCookieStore
    for cookie in HTTPCookieStorage.shared.cookies ?? [] {
      cookieStore.setCookie(cookie, completionHandler: nil)
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func applicationWillResignActive(_ application: UIApplication) {
    // Uygulama arka plana alındığında cookie'leri HTTPCookieStorage'a geri yaz
    WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
      for cookie in cookies {
        HTTPCookieStorage.shared.setCookie(cookie)
      }
    }
  }
}
