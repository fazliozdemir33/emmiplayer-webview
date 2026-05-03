import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:chewie/chewie.dart';
import 'package:video_player/video_player.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase with the provided configuration
  try {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: "AIzaSyBuqj4jKvzVDsQl71OK2UzmrPGdN-6rXEA",
        appId: "1:94061509633:web:3f8d7cdaad0518e5b7d400",
        messagingSenderId: "94061509633",
        projectId: "detasoft-comtr",
        storageBucket: "detasoft-comtr.firebasestorage.app",
        measurementId: "G-DNT1F8JGFS",
      ),
    );
  } catch (e) {
    debugPrint("Firebase initialization error: $e");
  }

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
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String _downloadingName = '';
  CancelToken? _cancelToken;
  bool _appBarVisible = false;

  String _targetUrl = 'https://app.montanahd4.com/home';
  final List<String> _allowedDomains = [
    'montanahd4.com',
    'montanahd3.com',
    'mntdns1.vip',
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

  static const List<String> _videoExtensions = [
    '.mp4', '.mkv', '.ts', '.avi', '.webm', '.mov', '.m4v', '.flv',
  ];

  bool _isVideoUrl(String url) {
    final lower = url.toLowerCase();
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    final pathLower = uri.path.toLowerCase();
    return _videoExtensions.any((ext) => pathLower.contains(ext));
  }

  @override
  void initState() {
    super.initState();
    _fetchConfigAndInit();
  }

  Future<void> _fetchConfigAndInit() async {
    try {
      // Fetch URL from Firebase Firestore
      // Collection: settings, Document: app_config, Field: url
      final doc = await FirebaseFirestore.instance
          .collection('settings')
          .doc('app_config')
          .get();

      if (doc.exists && doc.data() != null) {
        final dynamic remoteUrl = doc.data()!['url'];
        if (remoteUrl != null && remoteUrl.toString().isNotEmpty) {
          final String url = remoteUrl.toString();
          setState(() {
            _targetUrl = url;
            
            // Add the host of the remote URL to allowed domains
            final uri = Uri.tryParse(url);
            if (uri != null && uri.host.isNotEmpty) {
              final host = uri.host.toLowerCase();
              if (!_allowedDomains.contains(host)) {
                _allowedDomains.add(host);
              }
            }
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching remote config: $e");
    } finally {
      _initWebView();
    }
  }

  void _initWebView() {
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
            _injectDownloadInterceptor();
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

            if (uri.scheme == 'javascript' || uri.scheme == 'about' || uri.scheme == 'blob') {
              return NavigationDecision.navigate;
            }

            // Video URL'lerini yakala ve indir
            if (_isVideoUrl(request.url)) {
              _startDownload(request.url);
              return NavigationDecision.prevent;
            }

            final host = uri.host.toLowerCase();
            final isAllowed = _allowedDomains.any((d) => host == d || host.endsWith('.$d'));
            if (!isAllowed) return NavigationDecision.prevent;

            return NavigationDecision.navigate;
          },
        ),
      )
      ..addJavaScriptChannel(
        'EmmiApp',
        onMessageReceived: (JavaScriptMessage message) {
          final data = message.message;
          // "DOWNLOAD:url" veya sadece "url" olarak gelebilir
          if (data.startsWith('DOWNLOAD:')) {
            _startDownload(data.substring(9));
          } else if (data.isNotEmpty && (data.startsWith('http://') || data.startsWith('https://'))) {
            _startDownload(data);
          }
        },
      )
      ..loadRequest(Uri.parse(_targetUrl));
  }

  /// Sayfaya JavaScript enjekte ederek indirme linklerini yakalar
  void _injectDownloadInterceptor() {
    const jsCode = '''
      (function() {
        // Daha önce enjekte edildiyse tekrar yapma
        if (window.__emmiInjected) return;
        window.__emmiInjected = true;

        // <a download> linklerine tıklamayı yakala
        document.addEventListener('click', function(e) {
          var el = e.target;
          // En yakın anchor'a çık
          while (el && el.tagName !== 'A') el = el.parentElement;
          if (!el) return;

          var href = el.href || '';
          var hasDownload = el.hasAttribute('download');
          var isVideoLink = /\\.(mp4|mkv|ts|avi|webm|mov|m4v|flv)(\\?.*)?\$/i.test(href);

          if (href && (hasDownload || isVideoLink)) {
            e.preventDefault();
            e.stopPropagation();
            EmmiApp.postMessage('DOWNLOAD:' + href);
          }
        }, true);

        // window.open'ı override et (bazı siteler popup üzerinden indiriyor)
        var _origOpen = window.open;
        window.open = function(url, name, features) {
          if (url && /\\.(mp4|mkv|ts|avi|webm|mov|m4v|flv)(\\?.*)?\$/i.test(url)) {
            EmmiApp.postMessage('DOWNLOAD:' + url);
            return null;
          }
          return _origOpen.apply(this, arguments);
        };

        // fetch() override ile blob download'ları yakala (opsiyonel, bazı siteler için)
        var _origFetch = window.fetch;
        window.fetch = function(input, init) {
          var url = typeof input === 'string' ? input : (input && input.url) || '';
          if (url && /\\.(mp4|mkv|ts|avi|webm|mov|m4v|flv)(\\?.*)?\$/i.test(url)) {
            EmmiApp.postMessage('DOWNLOAD:' + url);
            return Promise.resolve(new Response('', {status: 200}));
          }
          return _origFetch.apply(this, arguments);
        };
      })();
    ''';
    _controller.runJavaScript(jsCode);
  }

  /// Sayfadaki video tag'ini bulup URL'ini getirir
  Future<void> _tryDetectAndDownload() async {
    const String jsCode = '''
      (function() {
        // Önce doğrudan video tag'ini dene
        var v = document.querySelector('video');
        if (v && v.src && !v.src.startsWith('blob:')) return v.src;
        var s = document.querySelector('video source');
        if (s && s.src && !s.src.startsWith('blob:')) return s.src;

        // iframe içindeki videoyu dene
        var iframes = document.querySelectorAll('iframe');
        for (var i = 0; i < iframes.length; i++) {
          try {
            var iv = iframes[i].contentDocument.querySelector('video');
            if (iv && iv.src && !iv.src.startsWith('blob:')) return iv.src;
          } catch(e) {}
        }

        // Player veri attribute'larını dene
        var playerEl = document.querySelector('[data-video-src],[data-src],[data-url]');
        if (playerEl) {
          return playerEl.getAttribute('data-video-src') ||
                 playerEl.getAttribute('data-src') ||
                 playerEl.getAttribute('data-url') || 'not_found';
        }

        return 'not_found';
      })();
    ''';

    try {
      final Object result = await _controller.runJavaScriptReturningResult(jsCode);
      String url = result.toString();
      if (url.startsWith('"') && url.endsWith('"')) url = url.substring(1, url.length - 1);

      if (url == 'not_found' || url.isEmpty || url == 'null') {
        if (mounted) {
          _showSnack('Video linki bulunamadı. Lütfen videoyu başlatıp tekrar deneyin.', isError: true);
        }
      } else {
        _startDownload(url);
      }
    } catch (e) {
      if (mounted) _showSnack('Hata oluştu: $e', isError: true);
    }
  }

  /// Sayfadan zengin metadata çeker
  Future<Map<String, String>> _getCurrentPageMeta() async {
    const js = '''
      (function() {
        try {
          var og = document.querySelector('meta[property="og:title"]');
          var title = og ? og.content : document.title;
          var h1 = document.querySelector('h1');
          var h1Text = h1 ? h1.innerText.trim() : '';
          var breadItems = Array.from(
            document.querySelectorAll('.breadcrumb a, .breadcrumbs a, nav ol li a, .bread a')
          ).map(function(e){ return e.innerText.trim(); }).filter(Boolean);
          return JSON.stringify({ title: title, h1: h1Text, bread: breadItems });
        } catch(e) {
          return JSON.stringify({ title: document.title, h1: '', bread: [] });
        }
      })()
    ''';
    try {
      final Object result = await _controller.runJavaScriptReturningResult(js);
      String raw = result.toString();
      if (raw.startsWith('"') && raw.endsWith('"')) {
        raw = raw.substring(1, raw.length - 1).replaceAll('\\"', '"');
      }
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final pageTitle = (map['title'] as String? ?? '').trim();
      final h1 = (map['h1'] as String? ?? '').trim();
      final bread = (map['bread'] as List<dynamic>? ?? []).map((e) => e.toString()).toList();
      final bestTitle = pageTitle.isNotEmpty ? pageTitle : (h1.isNotEmpty ? h1 : 'Video');
      return {'title': bestTitle, 'h1': h1, 'breadcrumbs': bread.join(' › ')};
    } catch (_) {
      return {'title': 'Video', 'h1': '', 'breadcrumbs': ''};
    }
  }

  /// Başlıktan seri adı ve bölüm bilgisini ayrıştırır
  static Map<String, String> _parseSeriesInfo(String title) {
    final regexes = [
      RegExp(r'^(.+?)\s*[-–—:]\s*(\d+\.?\s*[Ss]ezon.+)\$', caseSensitive: false),
      RegExp(r'^(.+?)\s*[-–—:]\s*([Ss]eason\s*\d+.+)\$', caseSensitive: false),
      RegExp(r'^(.+?)\s*[-–—:]\s*([Ss]\d{1,2}[Ee]\d{1,3}.*)\$'),
      RegExp(r'^(.+?)\s*[-–—:]\s*([Bb]ölüm\s*\d+.*)\$', caseSensitive: false),
      RegExp(r'^(.+?)\s*[-–—:]\s*([Ee]pisode\s*\d+.*)\$', caseSensitive: false),
      RegExp(r'^(.+?)\s+(\d+\.\s*[Ss]ezon.+)\$', caseSensitive: false),
      RegExp(r'^(.+?)\s+([Ss]\d{1,2}[Ee]\d{1,3}.*)\$'),
    ];
    for (final re in regexes) {
      final m = re.firstMatch(title);
      if (m != null) {
        final sn = m.group(1)!.trim();
        final ep = m.group(2)!.trim();
        if (sn.length > 1 && sn.length < 80) {
          return {'seriesName': sn, 'episodeInfo': ep};
        }
      }
    }
    return {'seriesName': '', 'episodeInfo': ''};
  }

  Future<void> _startDownload(String url) async {
    if (_isDownloading) {
      _showSnack('Zaten bir indirme devam ediyor.', isError: true);
      return;
    }

    // İzin kontrolü
    if (Platform.isAndroid) {
      var status = await Permission.storage.request();
      if (!status.isGranted) {
        status = await Permission.manageExternalStorage.request();
      }
      if (!status.isGranted) {
        _showSnack('Depolama izni reddedildi.', isError: true);
        return;
      }
    }

    final meta = await _getCurrentPageMeta();
    final name = meta['title']!.isEmpty ? 'Video' : meta['title']!;
    final series = _parseSeriesInfo(name);
    final seriesName = series['seriesName']!;
    final episodeInfo = series['episodeInfo']!;

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _downloadingName = seriesName.isNotEmpty ? '$seriesName · $episodeInfo' : name;
    });

    _cancelToken = CancelToken();

    try {
      final dio = Dio();
      // Gerçek tarayıcı headerları ekle (bazı CDN'ler kontrol eder)
      dio.options.headers = {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
        'Referer': _targetUrl,
        'Accept': '*/*',
        'Accept-Encoding': 'identity',
      };

      final dir = await getApplicationDocumentsDirectory();
      final safeTitle = name.replaceAll(RegExp(r'[^\w\s-]'), '').trim().replaceAll(' ', '_');
      final fileName = "EmmiPlayer_${safeTitle}_${DateTime.now().millisecondsSinceEpoch}.mp4";
      final filePath = "${dir.path}/$fileName";

      await dio.download(
        url,
        filePath,
        cancelToken: _cancelToken,
        onReceiveProgress: (count, total) {
          if (total != -1 && mounted) {
            setState(() {
              _downloadProgress = count / total;
            });
          }
        },
      );

      // Metadatayı kaydet
      final prefs = await SharedPreferences.getInstance();
      List<String> downloads = prefs.getStringList('downloads') ?? [];
      downloads.add(jsonEncode({
        'name': name,
        'seriesName': seriesName,
        'episodeInfo': episodeInfo,
        'breadcrumbs': meta['breadcrumbs'] ?? '',
        'path': filePath,
        'date': DateTime.now().toString(),
        'url': url,
        'size': File(filePath).existsSync() ? File(filePath).lengthSync() : 0,
      }));
      await prefs.setStringList('downloads', downloads);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ "$name" indirildi!'),
            backgroundColor: const Color(0xFF1a7a1a),
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Listeyi Gör',
              textColor: Colors.white,
              onPressed: _openDownloads,
            ),
          ),
        );
      }
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        if (mounted) _showSnack('İndirme iptal edildi.', isError: false);
      } else {
        if (mounted) _showSnack('İndirme hatası: ${e.message}', isError: true);
      }
    } catch (e) {
      if (mounted) _showSnack('İndirme hatası: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadProgress = 0.0;
          _downloadingName = '';
        });
      }
    }
  }

  void _cancelDownload() {
    _cancelToken?.cancel('Kullanıcı iptal etti');
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red[800] : const Color(0xFF333333),
    ));
  }

  void _openDownloads() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const DownloadsScreen()),
    );
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
              // WebView - tam ekran
              if (!_hasError)
                WebViewWidget(controller: _controller)
              else
                _buildErrorView(),

              // Animasyonlu AppBar (yukarıdan kayar)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedSlide(
                      offset: _appBarVisible ? Offset.zero : const Offset(0, -1),
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeInOut,
                      child: AnimatedOpacity(
                        opacity: _appBarVisible ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 280),
                        child: Container(
                          color: Colors.black.withOpacity(0.92),
                          child: SafeArea(
                            bottom: false,
                            child: Row(
                              children: [
                                const SizedBox(width: 8),
                                const Text(
                                  'EmmiPlayer',
                                  style: TextStyle(
                                    color: Color(0xFFE50914),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                                const Spacer(),
                                if (!_isLoading && !_hasError)
                                  IconButton(
                                    icon: const Icon(Icons.download_rounded, color: Colors.white),
                                    onPressed: _tryDetectAndDownload,
                                    tooltip: 'Videoyu İndir',
                                  ),
                                IconButton(
                                  icon: const Icon(Icons.folder_copy_rounded, color: Colors.white),
                                  onPressed: _openDownloads,
                                  tooltip: 'İndirilenler',
                                ),
                                IconButton(
                                  icon: const Icon(Icons.keyboard_arrow_up_rounded, color: Colors.white54),
                                  onPressed: () => setState(() => _appBarVisible = false),
                                  tooltip: 'Gizle',
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Her zaman görünen küçük handle pill
                    GestureDetector(
                      onTap: () => setState(() => _appBarVisible = !_appBarVisible),
                      child: Container(
                        width: double.infinity,
                        color: Colors.transparent,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Center(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 280),
                            width: _appBarVisible ? 36 : 48,
                            height: 4,
                            decoration: BoxDecoration(
                              color: _appBarVisible
                                  ? Colors.white38
                                  : const Color(0xFFE50914),
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Yükleme çubuğu
              if (_isLoading)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(
                    value: _progress,
                    backgroundColor: Colors.black26,
                    color: const Color(0xFFE50914),
                    minHeight: 3,
                  ),
                ),

              // İndirme overlay'i
              if (_isDownloading)
                Positioned(
                  bottom: 24,
                  left: 16,
                  right: 16,
                  child: _buildDownloadOverlay(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDownloadOverlay() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a1a),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE50914).withOpacity(0.5)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.download_rounded, color: Color(0xFFE50914), size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'İndiriliyor: $_downloadingName',
                  style: const TextStyle(fontSize: 13, color: Colors.white70),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              GestureDetector(
                onTap: _cancelDownload,
                child: const Icon(Icons.close, color: Colors.grey, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _downloadProgress,
              backgroundColor: Colors.white12,
              color: const Color(0xFFE50914),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${(_downloadProgress * 100).toStringAsFixed(1)}%',
            style: const TextStyle(fontSize: 11, color: Colors.white38),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.wifi_off_rounded, color: Colors.grey, size: 64),
          const SizedBox(height: 16),
          const Text('Bağlantı hatası', style: TextStyle(color: Colors.white, fontSize: 16)),
          const SizedBox(height: 8),
          const Text('İnternet bağlantınızı kontrol edin.', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => _controller.reload(),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Yenile'),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE50914)),
          ),
        ],
      ),
    );
  }
}

// ─── İndirilenler Ekranı (Gruplu) ──────────────────────────────────────────

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});
  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  List<Map<String, dynamic>> _allFiles = [];
  bool _loading = true;

  // key: seri adı (veya '__movies__' tek filmler için)
  Map<String, List<Map<String, dynamic>>> _grouped = {};

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> raw = prefs.getStringList('downloads') ?? [];
    final List<Map<String, dynamic>> parsed = [];

    for (final e in raw) {
      try {
        final map = jsonDecode(e) as Map<String, dynamic>;
        if (File(map['path']).existsSync()) parsed.add(map);
      } catch (_) {}
    }

    // Güncel kayıtları geri yaz
    await prefs.setStringList('downloads', parsed.map((m) => jsonEncode(m)).toList());

    // Grupla: seriesName varsa oraya, yoksa '__movies__'
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final f in parsed.reversed.toList()) {
      final sn = (f['seriesName'] as String? ?? '').trim();
      final key = sn.isNotEmpty ? sn : '__movies__';
      grouped.putIfAbsent(key, () => []).add(f);
    }

    setState(() {
      _allFiles = parsed.reversed.toList();
      _grouped = grouped;
      _loading = false;
    });
  }

  String _formatSize(dynamic size) {
    if (size == null) return '';
    final bytes = (size is int) ? size : int.tryParse(size.toString()) ?? 0;
    if (bytes == 0) return '';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _deleteByPath(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
    final prefs = await SharedPreferences.getInstance();
    List<String> dl = prefs.getStringList('downloads') ?? [];
    dl.removeWhere((e) {
      try { return jsonDecode(e)['path'] == path; } catch (_) { return false; }
    });
    await prefs.setStringList('downloads', dl);
    _loadFiles();
  }

  @override
  Widget build(BuildContext context) {
    final seriesKeys = _grouped.keys.where((k) => k != '__movies__').toList()..sort();
    final movies = _grouped['__movies__'] ?? [];

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('İndirilenler', style: TextStyle(color: Colors.white)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFE50914)))
          : _allFiles.isEmpty
              ? _buildEmptyState()
              : ListView(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  children: [
                    // Seri grupları
                    for (final sKey in seriesKeys) _buildSeriesCard(sKey, _grouped[sKey]!),
                    // Tek filmler bölümü
                    if (movies.isNotEmpty) ..._buildMovieItems(movies),
                  ],
                ),
    );
  }

  Widget _buildSeriesCard(String seriesName, List<Map<String, dynamic>> episodes) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Material(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => EpisodesScreen(
                seriesName: seriesName,
                episodes: episodes,
                formatSize: _formatSize,
                onDelete: _deleteByPath,
              ),
            ),
          ).then((_) => _loadFiles()),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE50914).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.live_tv_rounded, color: Color(0xFFE50914), size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        seriesName,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${episodes.length} bölüm indirildi',
                        style: const TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Colors.white30),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildMovieItems(List<Map<String, dynamic>> movies) {
    return [
      const Padding(
        padding: EdgeInsets.only(left: 16, top: 8, bottom: 4),
        child: Text('Filmler', style: TextStyle(color: Colors.white54, fontSize: 12, letterSpacing: 1)),
      ),
      for (final f in movies)
        _buildVideoTile(
          name: f['name'] ?? 'İsimsiz',
          subtitle: (f['date'] as String? ?? '').length >= 16 ? (f['date'] as String).substring(0, 16) : '',
          size: _formatSize(f['size']),
          onTap: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => VideoPlayerScreen(path: f['path'], title: f['name'] ?? 'Film'),
          )),
          onDelete: () => _deleteByPath(f['path']),
        ),
    ];
  }

  Widget _buildVideoTile({
    required String name,
    required String subtitle,
    required String size,
    required VoidCallback onTap,
    required VoidCallback onDelete,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.movie_rounded, color: Colors.white38, size: 22),
      ),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 14)),
      subtitle: Text([subtitle, size].where((s) => s.isNotEmpty).join(' · '),
          style: const TextStyle(color: Colors.white30, fontSize: 11)),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline, color: Colors.white24),
        onPressed: onDelete,
      ),
      onTap: onTap,
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.download_for_offline_outlined, size: 72, color: Colors.white.withOpacity(0.1)),
          const SizedBox(height: 16),
          const Text('Henüz indirilmiş video yok.', style: TextStyle(color: Colors.white38, fontSize: 15)),
          const SizedBox(height: 6),
          const Text('⬇ butonuyla video indirebilirsin.', style: TextStyle(color: Colors.white24, fontSize: 12)),
        ],
      ),
    );
  }
}

// ─── Bölümler Ekranı ─────────────────────────────────────────────────────────

class EpisodesScreen extends StatelessWidget {
  final String seriesName;
  final List<Map<String, dynamic>> episodes;
  final String Function(dynamic) formatSize;
  final Future<void> Function(String path) onDelete;

  const EpisodesScreen({
    super.key,
    required this.seriesName,
    required this.episodes,
    required this.formatSize,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(seriesName,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            Text('${episodes.length} bölüm',
                style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ],
        ),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: episodes.length,
        separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1, indent: 72),
        itemBuilder: (context, i) {
          final ep = episodes[i];
          final epInfo = (ep['episodeInfo'] as String? ?? '').trim().isNotEmpty
              ? ep['episodeInfo'] as String
              : ep['name'] as String? ?? 'Bölüm ${i + 1}';
          final sizeText = formatSize(ep['size']);
          final dateStr = (ep['date'] as String? ?? '').length >= 16
              ? (ep['date'] as String).substring(0, 16)
              : '';

          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            leading: Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFFE50914).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  '${i + 1}',
                  style: const TextStyle(color: Color(0xFFE50914), fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
            title: Text(
              epInfo,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 14),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              [dateStr, sizeText].where((s) => s.isNotEmpty).join(' · '),
              style: const TextStyle(color: Colors.white30, fontSize: 11),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.white24, size: 20),
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: const Color(0xFF1a1a1a),
                    title: const Text('Bölümü Sil', style: TextStyle(color: Colors.white)),
                    content: Text('"$epInfo" silinsin mi?',
                        style: const TextStyle(color: Colors.white70)),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('İptal', style: TextStyle(color: Colors.white54))),
                      TextButton(onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Sil', style: TextStyle(color: Color(0xFFE50914)))),
                    ],
                  ),
                );
                if (confirm == true) {
                  await onDelete(ep['path'] as String);
                  if (context.mounted) Navigator.pop(context);
                }
              },
            ),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => VideoPlayerScreen(
                  path: ep['path'] as String,
                  title: epInfo,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Video Oynatıcı Ekranı ──────────────────────────────────────────────────

class VideoPlayerScreen extends StatefulWidget {
  final String path;
  final String title;
  const VideoPlayerScreen({super.key, required this.path, required this.title});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late VideoPlayerController _videoPlayerController;
  ChewieController? _chewieController;
  bool _initError = false;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      _videoPlayerController = VideoPlayerController.file(File(widget.path));
      await _videoPlayerController.initialize();
      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController,
        autoPlay: true,
        looping: false,
        fullScreenByDefault: false,
        allowFullScreen: true,
        showControls: true,
        materialProgressColors: ChewieProgressColors(
          playedColor: const Color(0xFFE50914),
          handleColor: const Color(0xFFE50914),
          bufferedColor: Colors.white24,
          backgroundColor: Colors.white12,
        ),
      );
      setState(() {});
    } catch (e) {
      setState(() => _initError = true);
    }
  }

  @override
  void dispose() {
    _videoPlayerController.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title,
            style: const TextStyle(color: Colors.white, fontSize: 15),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: _initError
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 48),
                  const SizedBox(height: 12),
                  const Text('Video oynatılamadı.',
                      style: TextStyle(color: Colors.white70)),
                ],
              )
            : (_chewieController != null &&
                    _chewieController!
                        .videoPlayerController.value.isInitialized)
                ? Chewie(controller: _chewieController!)
                : const CircularProgressIndicator(color: Color(0xFFE50914)),
      ),
    );
  }
}
