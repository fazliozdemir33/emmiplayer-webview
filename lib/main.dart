import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:chewie/chewie.dart';
import 'package:video_player/video_player.dart';

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
  bool _isDownloading = false;
  double _downloadProgress = 0.0;

  static const String _targetUrl = 'https://app.montanahd2.com/home';
  static const List<String> _allowedDomains = [
    'montanahd2.com',
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

  @override
  void initState() {
    super.initState();
    _initWebView();
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

            if (uri.scheme == 'javascript' || uri.scheme == 'about') {
              return NavigationDecision.navigate;
            }

            final host = uri.host.toLowerCase();
            final path = uri.path.toLowerCase();

            if (path.endsWith('.mp4') || path.endsWith('.mkv') || path.endsWith('.ts')) {
              _startDownload(request.url);
              return NavigationDecision.prevent;
            }

            final isAllowed = _allowedDomains.any((d) => host == d || host.endsWith('.$d'));
            if (!isAllowed) return NavigationDecision.prevent;

            return NavigationDecision.navigate;
          },
        ),
      )
      ..addJavaScriptChannel(
        'EmmiApp',
        onMessageReceived: (JavaScriptMessage message) {
          _startDownload(message.message);
        },
      )
      ..loadRequest(Uri.parse(_targetUrl));
  }

  // İndirmeyi başlatan ve yöneten ana fonksiyon
  Future<void> _startDownload(String url) async {
    if (_isDownloading) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Zaten bir indirme devam ediyor.')),
      );
      return;
    }

    // İzin kontrolü
    if (Platform.isAndroid) {
      var status = await Permission.storage.request();
      if (!status.isGranted) {
        status = await Permission.manageExternalStorage.request();
      }
    }

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
    });

    try {
      final dio = Dio();
      final dir = await getApplicationDocumentsDirectory();
      final fileName = "EmmiPlayer_${DateTime.now().millisecondsSinceEpoch}.mp4";
      final filePath = "${dir.path}/$fileName";

      await dio.download(
        url,
        filePath,
        onReceiveProgress: (count, total) {
          if (total != -1) {
            setState(() {
              _downloadProgress = count / total;
            });
          }
        },
      );

      // Metadatayı kaydet
      final prefs = await SharedPreferences.getInstance();
      List<String> downloads = prefs.getStringList('downloads') ?? [];
      final name = await _getCurrentPageTitle();
      downloads.add(jsonEncode({
        'name': name,
        'path': filePath,
        'date': DateTime.now().toString(),
        'url': url,
      }));
      await prefs.setStringList('downloads', downloads);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$name indirildi!'),
            backgroundColor: Colors.green,
            action: SnackBarAction(
              label: 'Listeyi Gör',
              textColor: Colors.white,
              onPressed: () => _openDownloads(),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('İndirme hatası: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadProgress = 0.0;
        });
      }
    }
  }

  Future<String> _getCurrentPageTitle() async {
    try {
      final Object? title = await _controller.runJavaScriptReturningResult("document.title");
      String t = title.toString();
      if (t.startsWith('"') && t.endsWith('"')) t = t.substring(1, t.length - 1);
      return t.isEmpty ? "Dizi/Film" : t;
    } catch (_) {
      return "Video Bölümü";
    }
  }

  Future<void> _tryDetectAndDownload() async {
    const String jsCode = '''
      (function() {
        var v = document.querySelector('video');
        if (v && v.src && !v.src.startsWith('blob:')) return v.src;
        var s = document.querySelector('video source');
        if (s && s.src && !s.src.startsWith('blob:')) return s.src;
        return 'not_found';
      })();
    ''';
    
    try {
      final Object result = await _controller.runJavaScriptReturningResult(jsCode);
      String url = result.toString();
      if (url.startsWith('"') && url.endsWith('"')) url = url.substring(1, url.length - 1);

      if (url == 'not_found' || url.isEmpty || url == 'null') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Video linki bulunamadı. Lütfen videoyu başlatıp tekrar deneyin.')),
          );
        }
      } else {
        _startDownload(url);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Hata oluştu.')));
    }
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
        appBar: AppBar(
          backgroundColor: Colors.black,
          title: const Text('EmmiPlayer', style: TextStyle(color: Color(0xFFE50914), fontWeight: FontWeight.bold)),
          actions: [
            IconButton(
              icon: const Icon(Icons.folder_copy_rounded, color: Colors.white),
              onPressed: _openDownloads,
              tooltip: 'İndirilenler',
            ),
          ],
        ),
        body: SafeArea(
          child: Stack(
            children: [
              WebViewWidget(controller: _controller),
              if (_isLoading)
                const LinearProgressIndicator(backgroundColor: Colors.black26, color: Color(0xFFE50914), minHeight: 3),
              if (_isDownloading)
                Positioned(
                  bottom: 20,
                  left: 20,
                  right: 80,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(10)),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('İndiriliyor...', style: TextStyle(fontSize: 12)),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(value: _downloadProgress, color: const Color(0xFFE50914)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _tryDetectAndDownload,
          backgroundColor: const Color(0xFFE50914),
          child: const Icon(Icons.download_rounded, color: Colors.white),
        ),
      ),
    );
  }
}

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  List<Map<String, dynamic>> _files = [];

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> downloads = prefs.getStringList('downloads') ?? [];
    setState(() {
      _files = downloads.map((e) => jsonDecode(e) as Map<String, dynamic>).toList().reversed.toList();
    });
  }

  Future<void> _deleteFile(int index) async {
    final fileData = _files[index];
    final file = File(fileData['path']);
    if (await file.exists()) await file.delete();

    final prefs = await SharedPreferences.getInstance();
    List<String> downloads = prefs.getStringList('downloads') ?? [];
    downloads.removeWhere((e) => jsonDecode(e)['path'] == fileData['path']);
    await prefs.setStringList('downloads', downloads);
    _loadFiles();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('İndirilen Videolar'), backgroundColor: Colors.black),
      body: _files.isEmpty
          ? const Center(child: Text('Henüz indirilmiş video yok.'))
          : ListView.builder(
              itemCount: _files.length,
              itemBuilder: (context, index) {
                final file = _files[index];
                return ListTile(
                  leading: const Icon(Icons.video_library_rounded, color: Color(0xFFE50914)),
                  title: Text(file['name'] ?? 'İsimsiz Video', maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(file['date'].substring(0, 16), style: const TextStyle(fontSize: 11)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.grey),
                    onPressed: () => _deleteFile(index),
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => VideoPlayerScreen(path: file['path'], title: file['name']),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}

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

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    _videoPlayerController = VideoPlayerController.file(File(widget.path));
    await _videoPlayerController.initialize();
    _chewieController = ChewieController(
      videoPlayerController: _videoPlayerController,
      autoPlay: true,
      looping: false,
      fullScreenByDefault: true,
    );
    setState(() {});
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
      appBar: AppBar(title: Text(widget.title), backgroundColor: Colors.black),
      body: Center(
        child: _chewieController != null && _chewieController!.videoPlayerController.value.isInitialized
            ? Chewie(controller: _chewieController!)
            : const CircularProgressIndicator(color: Color(0xFFE50914)),
      ),
    );
  }
}
