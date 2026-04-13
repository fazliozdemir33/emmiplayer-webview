import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

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
    'mntdns1.vip',           // IPTV sunucusu
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
            final path = uri.path.toLowerCase();

            // İndirilebilir video dosyası yakalanırsa, telefonun varsayılan tarayıcısına pasla
            // Bu sayede sistemin kendi indirme yöneticisi devreye girer.
            if (path.endsWith('.mp4') || path.endsWith('.mkv') || path.endsWith('.ts') || path.endsWith('.m3u8') || path.endsWith('.apk')) {
              _launchExternal(uri);
              // WebView üzerinde gezinmeyi kapat (sadece indirme tetiklensin)
              return NavigationDecision.prevent;
            }

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
      ..addJavaScriptChannel(
        'EmmiApp',
        onMessageReceived: (JavaScriptMessage message) {
          // Eğer sitenizdeki bir butondan "EmmiApp.postMessage('video_url')" çalıştırılırsa:
          final url = message.message;
          final uri = Uri.tryParse(url);
          if (uri != null) {
            _launchExternal(uri);
          }
        },
      )
      ..loadRequest(Uri.parse(_targetUrl));
  }

  // Harici uygulamada (varsayılan tarayıcı) açma metodu
  Future<void> _launchExternal(Uri uri) async {
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      debugPrint('Açılamayan bağlantı: $uri');
    }
  }

  // Oynatılan videoyu HTML içerisinden çalıp bulmaya çalışan metod
  Future<void> _tryDownloadVideo() async {
    const String jsCode = '''
      (function() {
        var video = document.querySelector('video');
        if (video && video.src && !video.src.startsWith('blob:')) {
          return video.src;
        }
        var source = document.querySelector('video source');
        if (source && source.src && !source.src.startsWith('blob:')) {
          return source.src;
        }
        // İframe içindeki oynatıcıları da kontrol etmeyi dene
        var iframes = document.querySelectorAll('iframe');
        for (var i=0; i<iframes.length; i++) {
           try {
             var v = iframes[i].contentWindow.document.querySelector('video');
             if (v && v.src && !v.src.startsWith('blob:')) return v.src;
             var s = iframes[i].contentWindow.document.querySelector('video source');
             if (s && s.src && !s.src.startsWith('blob:')) return s.src;
           } catch(e) {}
        }
        return 'not_found';
      })();
    ''';
    
    try {
      final Object result = await _controller.runJavaScriptReturningResult(jsCode);
      String url = result.toString();
      
      // Çift tırnakları veya tek tırnakları temizle
      if (url.startsWith('"') && url.endsWith('"')) {
        url = url.substring(1, url.length - 1);
      } else if (url.startsWith("'") && url.endsWith("'")) {
        url = url.substring(1, url.length - 1);
      }

      if (url == 'not_found' || url.isEmpty || url == 'null') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Sayfada direkt video bağlantısı bulunamadı. Lütfen videoyu başlatıp tekrar deneyin.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } else {
        final uri = Uri.tryParse(url);
        if (uri != null) {
          _launchExternal(uri);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sayfadan video linki okunamadı (korumalı oynatıcı).')),
        );
      }
    }
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
        floatingActionButton: (!_hasError && !_isLoading) ? FloatingActionButton(
          onPressed: _tryDownloadVideo,
          backgroundColor: const Color(0xFFE50914),
          foregroundColor: Colors.white,
          tooltip: 'Bu Videoyu İndir',
          child: const Icon(Icons.download_rounded),
        ) : null,
      ),
    );
  }
}
