import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const MontanaApp());
}

class MontanaApp extends StatelessWidget {
  const MontanaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EmmiPlayer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE50914),
          secondary: Color(0xFFE50914),
        ),
      ),
      home: const WebViewScreen(),
    );
  }
}

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _hasError = false;
  double _progress = 0.0;

  static const String _targetUrl = 'https://montanahd2.com/';

  // İzin verilen domainler — app.montanahd2.com dahil tüm alt domainler
  static const List<String> _allowedDomains = [
    'montanahd2.com',        // ana site + app.montanahd2.com vb. tüm alt domainler
    'youtube.com',
    'youtu.be',
    'googleapis.com',
    'gstatic.com',
    'cloudflare.com',
    'cloudflarestream.com',
    'jwplatform.com',
    'jwpcdn.com',
    'jwplayer.com',
    'vimeo.com',
    'vimeocdn.com',
    'dailymotion.com',
    'streamtape.com',
    'doodstream.com',
    'dood.watch',
    'fembed.com',
    'ok.ru',
    'cdn77.org',
    'akamaihd.net',
    'fastly.net',
    'bunnycdn.com',
    'b-cdn.net',
    'recaptcha.net',
    'google.com',
    'paytr.com',
    'iyzico.com',
  ];

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  void _initWebView() {
    // Android WebView, cookie'leri ve localStorage'ı uygulama verisiyle
    // otomatik olarak kalıcı saklar — ek bir işlem gerekmez.
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setUserAgent(
        'Mozilla/5.0 (Linux; Android 13; Pixel 7) '
        'AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/120.0.0.0 Mobile Safari/537.36',
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            setState(() {
              _isLoading = true;
              _hasError = false;
              _progress = 0.0;
            });
          },
          onProgress: (progress) {
            setState(() => _progress = progress / 100.0);
          },
          onPageFinished: (url) {
            setState(() {
              _isLoading = false;
              _progress = 1.0;
            });
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame ?? false) {
              setState(() {
                _isLoading = false;
                _hasError = true;
              });
            }
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri == null) return NavigationDecision.prevent;

            // javascript: ve about: schemelerine izin ver
            if (uri.scheme == 'javascript' || uri.scheme == 'about') {
              return NavigationDecision.navigate;
            }

            final host = uri.host.toLowerCase();

            // İzin verilen domainleri kontrol et (alt domainler dahil)
            final isAllowed = _allowedDomains.any(
              (d) => host == d || host.endsWith('.$d'),
            );

            if (!isAllowed) {
              debugPrint('[NAV BLOCKED] $host');
              return NavigationDecision.prevent;
            }

            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(_targetUrl));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) {
          if (await _controller.canGoBack()) {
            await _controller.goBack();
          }
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              // WebView
              WebViewWidget(controller: _controller),

              // Yükleme çubuğu
              if (_isLoading)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(
                    value: _progress > 0 ? _progress : null,
                    backgroundColor: Colors.black26,
                    color: const Color(0xFFE50914),
                    minHeight: 3,
                  ),
                ),

              // Hata ekranı
              if (_hasError)
                Container(
                  color: Colors.black,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.wifi_off_rounded,
                          color: Color(0xFFE50914),
                          size: 72,
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Bağlantı kurulamadı',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'İnternet bağlantınızı kontrol edin',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 32),
                        ElevatedButton.icon(
                          onPressed: () {
                            setState(() {
                              _hasError = false;
                              _isLoading = true;
                            });
                            _controller.reload();
                          },
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Tekrar Dene'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE50914),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 32,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
