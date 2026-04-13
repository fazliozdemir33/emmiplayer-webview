package com.detasoft.emmiplayer

import android.os.Bundle
import android.webkit.CookieManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Cookie'leri kabul et ve kalıcı saklama etkin
        CookieManager.getInstance().setAcceptCookie(true)
    }

    override fun onPause() {
        super.onPause()
        // Uygulama arka plana alındığında cookie'leri diske yaz
        CookieManager.getInstance().flush()
    }

    override fun onStop() {
        super.onStop()
        CookieManager.getInstance().flush()
    }
}
