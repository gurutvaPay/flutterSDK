// lib/gurutvapay-sdk-flutter.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

typedef EventCallback = void Function(Map<String, dynamic> event);
typedef SimpleCallback = void Function(Map<String, dynamic> payload);

class GurutvaPaySDK extends StatefulWidget {
  final String liveSaltKey1;
  final String envBaseUrl;
  final Map<String, dynamic> orderPayload;
  final EventCallback? onAnyEvent;
  final SimpleCallback? onSuccess;
  final SimpleCallback? onFailure;
  final SimpleCallback? onPending;
  final SimpleCallback? onIntentLaunched;

  // UI options
  final bool showHeader;
  final String brandLogoUrl;
  final bool showSdkPopups;

  const GurutvaPaySDK({
    Key? key,
    required this.liveSaltKey1,
    required this.orderPayload,
    this.envBaseUrl = 'https://api.gurutvapay.com/live',
    this.onAnyEvent,
    this.onSuccess,
    this.onFailure,
    this.onPending,
    this.onIntentLaunched,
    this.showHeader = true,
    this.brandLogoUrl = 'https://jaikalki.com/static/assets/img/Gravity_logo.png',
    this.showSdkPopups = false,
  }) : super(key: key);

  @override
  State<GurutvaPaySDK> createState() => _GurutvaPaySDKState();

  /// Public helper: call transaction-status-android endpoint (form-encoded POST).
  static Future<Map<String, dynamic>?> checkTransactionStatus(
      String liveSaltKey1,
      String merchantOrderId, {
        int timeoutSeconds = 10,
      }) async {
    try {
      final pkg = await PackageInfo.fromPlatform();
      final appId = pkg.packageName;
      final url = 'https://api.gurutvapay.com/live/transaction-status-android';
      final uri = Uri.parse(url).replace(queryParameters: {
        'merchantOrderId': merchantOrderId,
      });

      final headers = {
        'Live-Salt-Key1': liveSaltKey1,
        'appId': appId,
        // no need to set Content-Type for an empty body / query params
      };

      final resp = await http
          .post(uri, headers: headers)
          .timeout(Duration(seconds: timeoutSeconds));

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        try {
          final decoded = jsonDecode(resp.body);
          if (decoded is Map<String, dynamic>) return decoded;
          return {'result': decoded};
        } catch (e) {
          return {'error': 'invalid_json', 'body': resp.body};
        }
      } else {
        return {'error': 'HTTP ${resp.statusCode}', 'body': resp.body};
      }
    } catch (e) {
      return {'error': e.toString()};
    }
  }
}

  class _GurutvaPaySDKState extends State<GurutvaPaySDK>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  InAppWebViewController? _controller;
  String? _paymentUrl;
  String? _appId;

  bool _webViewLoaded = false;

  // prevent popping twice
  bool _sdkRoutePopped = false;

  // dedupe & state for intent launches
  final Map<String, DateTime> _intentLaunchedAt = {};
  final Set<String> _currentlyLaunching = {};
  final Duration _intentDedupeWindow = const Duration(seconds: 8);

  // animation for loader logo
  late final AnimationController _animController;

  final Gradient _brandGradient = const LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFFFA500),
      Color(0xFF8F00FF),
    ],
  );

  final InAppWebViewSettings _settings = InAppWebViewSettings(
    userAgent: "flutterAppUserAgent",
    javaScriptEnabled: true,
    javaScriptCanOpenWindowsAutomatically: true,
    supportMultipleWindows: true,
    allowsInlineMediaPlayback: true,
    iframeAllowFullscreen: true,
    saveFormData: true,
    useOnDownloadStart: true,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _animController =
    AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat();
    _initAppId().then((_) => _initiatePayment());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _animController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final now = DateTime.now();
      _intentLaunchedAt.removeWhere((_, t) => now.difference(t) > _intentDedupeWindow);
      // Clear currently launching after resume so user can launch again.
      _currentlyLaunching.clear();
    }
  }

  Future<void> _initAppId() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _appId = info.packageName;
    } catch (_) {
      _appId = null;
    }
  }

  Future<void> _initiatePayment() async {
    setState(() {
      _webViewLoaded = false;
      _sdkRoutePopped = false;
      _paymentUrl = null;
    });

    final url = '${widget.envBaseUrl}/initiate-payment-android';
    final headers = {
      'Live-Salt-Key1': widget.liveSaltKey1,
      if (_appId != null) 'appId': _appId!,
      'Content-Type': 'application/json',
    };

    try {
      final resp = await http
          .post(Uri.parse(url), headers: headers, body: jsonEncode(widget.orderPayload))
          .timeout(const Duration(seconds: 20));

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final body = jsonDecode(resp.body);
        final purl = body['payment_url'] as String?;
        if (purl == null) {
          _emitEvent({'type': 'error', 'message': 'missing payment_url', 'raw': body});
          return;
        }
        setState(() {
          _paymentUrl = purl;
        });
      } else {
        _emitEvent({'type': 'http_error', 'status': resp.statusCode, 'body': resp.body});
      }
    } catch (e) {
      _emitEvent({'type': 'exception', 'error': e.toString()});
    }
  }

  void _emitEvent(Map<String, dynamic> event) {
    widget.onAnyEvent?.call(event);

    final status = (event['status'] ?? event['message'] ?? '').toString().toLowerCase();

    // don't auto pop or show success popup; host controls navigation.
    if (status.contains('success')) {
      widget.onSuccess?.call(event);
      return;
    } else if (status.contains('failed') || status.contains('failure') || status.contains('error')) {
      if (widget.showSdkPopups) _showSdkPopup('Payment failed', success: false);
      widget.onFailure?.call(event);
    } else if (status.contains('pending')) {
      if (widget.showSdkPopups) _showSdkPopup('Payment pending', pending: true);
      widget.onPending?.call(event);
    }
  }

  // schedule a safe pop (not used for success as requested, but kept)
  void _scheduleSdkPop() {
    if (_sdkRoutePopped) return;
    _sdkRoutePopped = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      } catch (_) {}
    });
  }

  // Prevent launching the same URL repeatedly while a launch is in progress
  Future<void> _maybeLaunchIntent(String url, {String? merchantOrderId}) async {
    final key = '${merchantOrderId ?? ''}::$url';

    // If already launching this exact key, ignore duplicate
    if (_currentlyLaunching.contains(key)) {
      widget.onAnyEvent?.call({'type': 'duplicate_intent_ignored', 'url': url, 'merchantOrderId': merchantOrderId});
      return;
    }

    final now = DateTime.now();
    final last = _intentLaunchedAt[key];
    if (last != null && now.difference(last) <= _intentDedupeWindow) {
      widget.onAnyEvent?.call({'type': 'duplicate_intent_ignored', 'url': url, 'merchantOrderId': merchantOrderId});
      return;
    }

    _currentlyLaunching.add(key);
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (launched) {
          _intentLaunchedAt[key] = DateTime.now();
          widget.onIntentLaunched?.call({'url': url, 'merchantOrderId': merchantOrderId});
        } else {
          widget.onAnyEvent?.call({'type': 'cannot_launch_intent', 'url': url});
        }
      } else {
        widget.onAnyEvent?.call({'type': 'cannot_launch_intent', 'url': url});
      }
    } catch (e) {
      widget.onAnyEvent?.call({'type': 'intent_launch_error', 'error': e.toString(), 'url': url});
    } finally {
      // ensure we clear the currently launching flag after a small delay (so rapid duplicates are blocked)
      Future.delayed(const Duration(seconds: 6), () {
        _currentlyLaunching.remove(key);
      });
    }
  }

  Future<void> _tryLaunchVariantsSequentially(List<String> variants, {String? merchantOrderId}) async {
    if (variants.isEmpty) return;
    final key = '${merchantOrderId ?? ''}::${variants.first}';

    // block if already launching
    if (_currentlyLaunching.contains(key)) {
      widget.onAnyEvent?.call({'type': 'duplicate_intent_ignored', 'variants': variants, 'merchantOrderId': merchantOrderId});
      return;
    }

    final now = DateTime.now();
    final last = _intentLaunchedAt[key];
    if (last != null && now.difference(last) <= _intentDedupeWindow) {
      widget.onAnyEvent?.call({'type': 'duplicate_intent_ignored', 'variants': variants, 'merchantOrderId': merchantOrderId});
      return;
    }

    _currentlyLaunching.add(key);

    for (final v in variants) {
      if (v.trim().isEmpty) continue;
      try {
        final uri = Uri.parse(v);
        if (await canLaunchUrl(uri)) {
          final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
          if (launched) {
            _intentLaunchedAt[key] = DateTime.now();
            widget.onIntentLaunched?.call({'url': v, 'merchantOrderId': merchantOrderId});
            // clear currentlyLaunching after small delay
            Future.delayed(const Duration(seconds: 6), () => _currentlyLaunching.remove(key));
            return;
          }
        }
      } catch (_) {}
    }

    // fallback
    try {
      final fallback = variants.first;
      final uri = Uri.parse(fallback);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      _intentLaunchedAt[key] = DateTime.now();
      widget.onIntentLaunched?.call({'url': fallback, 'merchantOrderId': merchantOrderId});
    } catch (e) {
      widget.onAnyEvent?.call({'type': 'cannot_launch_intent', 'error': e.toString(), 'variants': variants});
    } finally {
      Future.delayed(const Duration(seconds: 6), () => _currentlyLaunching.remove(key));
    }
  }

  void _handleUpiIntentFromPage(String intentUrl, [String? app, String? merchantOrderId]) {
    final url = intentUrl.trim();
    if (url.isEmpty) return;

    if (url.startsWith('intent:') ||
        url.startsWith('upi:') ||
        url.startsWith('upi://') ||
        url.startsWith('phonepe://') ||
        url.startsWith('paytmmp://') ||
        url.startsWith('tez://')) {
      final variants = <String>[];
      if (url.startsWith('intent:')) {
        variants.add(url);
      } else {
        variants.add(url);
        variants.add(url.replaceFirst('upi://pay', 'phonepe://pay'));
        variants.add(url.replaceFirst('upi://pay', 'paytmmp://pay'));
        variants.add(url.replaceFirst('upi://pay', 'tez://upi/pay'));
      }

      if (app != null) {
        final hint = app.toLowerCase();
        if (hint.contains('phonepe')) variants.insert(0, url.replaceFirst('upi://pay', 'phonepe://pay'));
        else if (hint.contains('paytm')) variants.insert(0, url.replaceFirst('upi://pay', 'paytmmp://pay'));
        else if (hint.contains('gpay') || hint.contains('google')) variants.insert(0, url.replaceFirst('upi://pay', 'tez://upi/pay'));
      }

      _tryLaunchVariantsSequentially(variants, merchantOrderId: merchantOrderId);
    } else {
      _maybeLaunchIntent(url, merchantOrderId: merchantOrderId);
    }
  }

  String _consoleOverrideJS() {
    return '''
(function(){
  if (window.__gurutva_console_installed) return;
  window.__gurutva_console_installed = true;
  function send(kind, args){
    try {
      var parts = Array.prototype.slice.call(args).map(function(a){
        try { return (typeof a === 'object' ? JSON.stringify(a) : String(a)); } catch(e){ return String(a); }
      }).join(' ');
      if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
        window.flutter_inappwebview.callHandler('flutter_console', JSON.stringify({kind: kind, payload: parts}));
      } else {
        window.__flutter_messages = window.__flutter_messages || [];
        window.__flutter_messages.push(JSON.stringify({kind: kind, payload: parts}));
      }
    } catch(e){}
  }
  var oldLog = console.log;
  console.log = function(){
    send('log', arguments);
    oldLog && oldLog.apply(console, arguments);
  };
  var oldErr = console.error;
  console.error = function(){
    send('error', arguments);
    oldErr && oldErr.apply(console, arguments);
  };
  window.addEventListener('message', function(e){
    try {
      var d = e.data;
      var payload = (typeof d === 'object') ? JSON.stringify(d) : String(d);
      if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
        window.flutter_inappwebview.callHandler('flutter_console', JSON.stringify({kind:'postMessage', payload: payload}));
      } else {
        window.__flutter_messages = window.__flutter_messages || [];
        window.__flutter_messages.push(JSON.stringify({kind:'postMessage', payload: payload}));
      }
    } catch(e){}
  }, false);
})();
''';
  }

  void _registerJsHandlers(InAppWebViewController controller) {
    controller.addJavaScriptHandler(handlerName: 'flutter_console', callback: (args) {
      if (args.isEmpty) return;
      try {
        final raw = args[0].toString();
        final m = jsonDecode(raw);
        final kind = (m['kind'] ?? '').toString();
        final payload = (m['payload'] ?? '').toString();

        // Try parse payload as JSON object
        try {
          final parsedPayload = jsonDecode(payload);
          if (parsedPayload is Map<String, dynamic>) {
            final innerKind = parsedPayload['kind']?.toString();
            if (innerKind == 'upi_intent') {
              final innerPayload = parsedPayload['payload'];
              if (innerPayload is Map<String, dynamic>) {
                final url = innerPayload['url']?.toString();
                final app = innerPayload['app']?.toString();
                final mo = innerPayload['merchantOrderId']?.toString();
                if (url != null) _handleUpiIntentFromPage(url, app, mo);
                return;
              }
            }
            _handleConsoleObject(parsedPayload);
            return;
          }
        } catch (_) {}

        // If payload is JSON string representing an object
        try {
          final payloadObj = jsonDecode(payload);
          if (payloadObj is Map<String, dynamic>) {
            _handleConsoleObject(payloadObj);
            return;
          }
        } catch (_) {}

        // fallback: treat as string
        _handleConsoleString(payload);
      } catch (_) {
        // ignore malformed
      }
    });
  }

  void _handleConsoleObject(Map<String, dynamic> obj) {
    _emitEvent(obj);
    if (obj.containsKey('merchantOrderId') || obj.containsKey('orderId')) {
      widget.onAnyEvent?.call({'type': 'transaction_info', 'payload': obj});
    }
  }

  void _handleConsoleString(String text) {
    final t = text.trim();
    if (t.isEmpty) return;

    if (t.startsWith('Open External Link: ')) {
      final link = t.substring('Open External Link: '.length).trim();
      widget.onAnyEvent?.call({'type': 'external_link', 'url': link});
      try {
        _maybeLaunchIntent(link);
      } catch (_) {}
      return;
    }

    final lower = t.toLowerCase();
    if (lower.contains('upi:') || lower.contains('intent:') || lower.contains('upi://')) {
      final regex = RegExp(r'(intent:[^\s"<>]+|upi:[^\s"<>]+|upi://[^\s"<>]+)', caseSensitive: false);
      final m = regex.firstMatch(t);
      if (m != null) {
        final url = m.group(0)!;
        _handleUpiIntentFromPage(url);
        widget.onAnyEvent?.call({'type': 'console', 'message': t});
        return;
      }
    }

    final statusMatch = RegExp(r'"status"\s*:\s*"([^"]+)"').firstMatch(t);
    if (statusMatch != null) {
      final status = statusMatch.group(1) ?? '';
      _emitEvent({'type': 'console_status', 'status': status, 'raw': t});
      return;
    }

    widget.onAnyEvent?.call({'type': 'console', 'message': t});
  }

  void _showSdkPopup(String text, {bool success = false, bool pending = false}) {
    if (!mounted) return;
    if (success) return; // success handled by host

    showDialog(
      context: context,
      barrierDismissible: !pending,
      builder: (ctx) {
        if (pending) {
          return AlertDialog(
            title: Text(text),
            content: const Text('Payment is pending. Please check later.'),
            actions: [
              TextButton(onPressed: () {
                if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
              }, child: const Text('OK')),
            ],
          );
        } else {
          return AlertDialog(
            title: Text(text),
            content: const Text('Tap OK to continue.'),
            actions: [
              TextButton(onPressed: () {
                if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
              }, child: const Text('OK')),
            ],
          );
        }
      },
    );
  }

  Future<NavigationActionPolicy> _shouldOverrideUrlLoading(NavigationAction action) async {
    final url = action.request.url?.toString() ?? '';
    final low = url.toLowerCase();
    if (low.startsWith('intent:') ||
        low.startsWith('upi:') ||
        low.startsWith('upi://') ||
        low.startsWith('phonepe://') ||
        low.startsWith('paytmmp://') ||
        low.startsWith('tez://')) {
      _handleUpiIntentFromPage(url);
      return NavigationActionPolicy.CANCEL;
    }
    return NavigationActionPolicy.ALLOW;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          if (widget.showHeader)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(gradient: _brandGradient, boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 6, offset: const Offset(0, 3))
              ]),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.05)),
                    child: ClipOval(
                      child: Image.network(widget.brandLogoUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) {
                        return const Center(child: Icon(Icons.account_balance_wallet, color: Colors.white));
                      }),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text('GurutvaPay', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                ],
              ),
            ),
          Expanded(
            child: Stack(
              children: [
                // make the webview broad: remove horizontal padding so it fills available width
                Card(
                  margin: const EdgeInsets.fromLTRB(0, 12, 0, 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 4,
                  clipBehavior: Clip.hardEdge,
                  child: _paymentUrl == null
                      ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Text('Unable to create payment session'),
                      const SizedBox(height: 8),
                      ElevatedButton(onPressed: () => _initiatePayment(), child: const Text('Retry')),
                    ]),
                  )
                      : SizedBox.expand(
                    child: InAppWebView(
                      initialUrlRequest: URLRequest(url: WebUri(_paymentUrl!)),
                      initialSettings: _settings,
                      onWebViewCreated: (controller) async {
                        _controller = controller;
                        _registerJsHandlers(controller);
                        try {
                          await controller.evaluateJavascript(source: _consoleOverrideJS());
                        } catch (_) {}
                      },
                      onConsoleMessage: (controller, consoleMessage) {
                        final msg = consoleMessage.message;
                        try {
                          final parsed = jsonDecode(msg);
                          if (parsed is Map<String, dynamic>) {
                            _handleConsoleObject(parsed);
                            return;
                          }
                        } catch (_) {}
                        _handleConsoleString(msg);
                      },
                      onLoadStop: (controller, url) async {
                        if (mounted) setState(() => _webViewLoaded = true);
                        try {
                          await controller.evaluateJavascript(source: _consoleOverrideJS());
                        } catch (_) {}
                      },
                      shouldOverrideUrlLoading: (controller, action) async {
                        return await _shouldOverrideUrlLoading(action);
                      },
                      onCreateWindow: (controller, createWindowAction) async {
                        return true;
                      },
                      onLoadError: (controller, url, code, message) {
                        _emitEvent({'type': 'load_error', 'url': url?.toString(), 'code': code, 'message': message});
                      },
                      onLoadHttpError: (controller, url, statusCode, description) {
                        _emitEvent({'type': 'http_error', 'url': url?.toString(), 'status': statusCode, 'description': description});
                      },
                    ),
                  ),
                ),
                if (!_webViewLoaded)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(gradient: _brandGradient),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            RotationTransition(
                              turns: _animController,
                              child: Container(
                                width: 110,
                                height: 110,
                                decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [
                                  BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 12, offset: const Offset(0, 6))
                                ]),
                                child: ClipOval(
                                  child: Image.network(widget.brandLogoUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) {
                                    return const Center(child: Icon(Icons.account_balance_wallet, size: 48, color: Colors.white));
                                  }),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            const Text('Opening payment...', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            const SizedBox(width: 40, height: 40, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white))),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
