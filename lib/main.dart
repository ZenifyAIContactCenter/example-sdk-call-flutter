// App demo zenify_call — luồng app thật cần làm:
//   1. Firebase.initializeApp + đưa token FCM cho SDK (updateFcmToken / onTokenRefresh)
//   2. restoreSession() mỗi lần mở app → SDK gọi lại sign-in, dựng PJSIP, đồng bộ push
//   3. chưa có phiên → signIn(email, API key) → SDK tự lấy agent, dựng PJSIP,
//      phone_type=5 + working_status=AVAILABLE + tự chọn đầu số mặc định
//   4. xin quyền (micro / thông báo / full-screen)
//   5. chọn đầu số gọi ra (CalloutQueuePicker trên AppBar) + toast lỗi cuộc gọi (CallErrorToaster)
//   6. ZenifyCallOverlay tự hiện màn cuộc gọi đến / đi; đăng nhập xong vào DemoHome
//      (demo_home.dart): tab CRM click-to-call + tab Gọi thủ công chọn theme màn cuộc gọi
//   7. signOut(): xoá token + phone_type=0 TRƯỚC, rồi huỷ SIP + xoá phiên đã lưu → màn đăng nhập
// Email + API key truyền lúc chạy (không ghi vào code); mật khẩu SIP lấy từ
// /auth/sdk/sign-in. Đăng nhập thành công → demo nhớ email + key (Keychain/Keystore) nên
// đăng xuất / mở lại app vẫn điền sẵn. Ghi đè lúc chạy:
//   flutter run --dart-define-from-file=dart_defines.local.json   (mẫu: dart_defines.example.json)
//   hoặc: flutter run --dart-define=ZC_EMAIL=… --dart-define=ZC_API_KEY=… \
//     [--dart-define=ZC_AUTO=1]
// ZC_AUTO=1: tự đăng nhập khi chưa có phiên và TỰ NGHE cuộc gọi đến (kiểm thử không chạm).
import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:zenify_call/zenify_call.dart';

import 'demo_home.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(
    MaterialApp(
      // toast "<mã> - <thông điệp>" khi cuộc gọi ra bị từ chối
      // Màn cuộc gọi tự phủ khi có cuộc gọi + toast mã lỗi — đặt MỘT lần dưới MaterialApp
      builder: (context, child) => ValueListenableBuilder(
        valueListenable: callScreenStyle,
        builder: (context, style, _) => ZenifyCallOverlay(
          callView: switch (style) {
            CallScreenStyle.mcall => mcallCallView,
            CallScreenStyle.zenify => null,
            CallScreenStyle.custom => customCallView,
          },
          child: CallErrorToaster(child: child!),
        ),
      ),
      home: const DemoPage(),
    ),
  );
}

class DemoPage extends StatefulWidget {
  const DemoPage({super.key});

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  final _sdk = ZenifyCall.instance;
  static const _auto = bool.fromEnvironment('ZC_AUTO');
  // App DEMO điền sẵn email (ZC_EMAIL) để bấm chạy là đăng nhập được. App tích hợp thật
  // KHÔNG làm thế này: key phải lấy từ backend của host.
  final _email = TextEditingController(text: const String.fromEnvironment('ZC_EMAIL'));

  /// API key của tenant (`/auth/sdk/sign-in`) — KHÔNG ghi vào code
  final _apiKey = TextEditingController(text: const String.fromEnvironment('ZC_API_KEY'));

  /// Demo: nhớ email + API key (Keychain / Keystore) để đăng xuất xong — kể cả mở lại app —
  /// màn đăng nhập điền sẵn, không phải dán lại key.
  static const _keyStore = FlutterSecureStorage();
  static const _kSavedEmail = 'demo_api_email';
  static const _kSavedApiKey = 'demo_api_key';
  bool _showKey = false;
  ZenifyAccount? _account;
  bool _busy = true;
  String? _loginError;

  /// Đã thử khôi phục phiên (xong `_boot`) — trước đó hiện vòng xoay, không nháy màn đăng nhập.
  bool _triedRestore = false;
  final _subs = <StreamSubscription<Object?>>[];

  /// Demo: mở lại app → in SIP log (push, CallKit/notification, INVITE, phone_type…) ra
  /// console để xem vì sao cuộc gọi không tới.
  late final _lifecycle = AppLifecycleListener(
    onResume: () {
      if (_account != null) _sdk.printSipLog(lines: 300);
    },
  );

  @override
  void initState() {
    super.initState();
    // App demo luôn ghi bản tin SIP (mức 4) — app thật để mặc định 3
    _sdk.sipLogLevel = const int.fromEnvironment('ZC_SIP_LOG', defaultValue: 4);
    _lifecycle; // khởi tạo listener
    // Demo: in log SIP TRỰC TIẾP (REGISTER / INVITE tới…) ra console khi app đang mở.
    // Tắt: --dart-define=ZC_SIP_LIVE=false
    if (const bool.fromEnvironment('ZC_SIP_LIVE', defaultValue: true)) {
      unawaited(_sdk.setLiveSipLog(true).catchError((Object e) => debugPrint('[demo] live log: $e')));
    }
    _subs
      ..add(_sdk.registration.listen((r) => debugPrint('[zenify_call] $r')))
      ..add(
        _sdk.calls.listen((c) {
          debugPrint('[zenify_call] ${c.error == null ? c : '$c → ${c.error}'}');
          // cuộc gọi kết thúc bất thường (603, 480…) → in log SIP để xem INVITE + bản tin lỗi
          if (c.type == CallEventType.ended && !c.local && c.code >= 300) {
            Future<void>.delayed(const Duration(milliseconds: 300), () => _sdk.printSipLog(lines: 300));
          }
          if (_auto && c.type == CallEventType.incoming) _run(() => _sdk.answer(c.callId));
        }),
      )
      ..add(
        _sdk.accountChanges.listen(
          (a) => setState(() => _account = a),
          onError: (Object e) => debugPrint('[demo] Phiên lỗi: $e — cần đăng nhập lại'),
        ),
      );
    _boot();
  }

  /// iOS: `getToken` lỗi `apns-token-not-set` khi APNs chưa trả token (lúc mở app) và
  /// `onTokenRefresh` không bắn lại → server mãi có `fcm_token: null`. Thử lại tới khi có.
  Future<void> _fetchFcmToken(FirebaseMessaging fcm) async {
    for (var i = 0; i < 10; i++) {
      try {
        final t = await fcm.getToken();
        if (t != null) return await _sdk.updateFcmToken(t);
      } catch (e) {
        debugPrint('[demo] Chưa lấy được token FCM (lần ${i + 1}): $e');
      }
      await Future<void>.delayed(const Duration(seconds: 3));
    }
  }

  /// Token FCM → SDK (SDK tự gửi lên server khi đã đăng nhập), rồi khôi phục phiên.
  Future<void> _boot() async {
    final fcm = FirebaseMessaging.instance;
    _subs.add(fcm.onTokenRefresh.listen(_sdk.updateFcmToken));
    unawaited(_fetchFcmToken(fcm));
    await _run(_loadSavedApiKey);
    await _run(() async {
      final acc = await _sdk.restoreSession();
      debugPrint('[demo] ${acc == null ? 'Chưa có phiên — hãy đăng nhập' : 'Khôi phục phiên: $acc'}');
      if (acc == null && _auto && _email.text.isNotEmpty && _apiKey.text.isNotEmpty) await _submitLogin();
    });
    setState(() {
      _busy = false;
      _triedRestore = true;
    });
  }

  /// Điền sẵn email + API key đã lưu (chỉ khi không truyền ZC_API_KEY lúc chạy).
  Future<void> _loadSavedApiKey() async {
    if (_apiKey.text.isNotEmpty) return;
    final key = await _keyStore.read(key: _kSavedApiKey);
    if (key == null || key.isEmpty) return;
    final email = await _keyStore.read(key: _kSavedEmail);
    if (!mounted) return;
    setState(() {
      _apiKey.text = key;
      if (email != null && email.isNotEmpty) _email.text = email;
    });
  }

  /// Màn đăng nhập: email + API key (`/auth/sdk/sign-in`).
  Future<void> _submitLogin() async {
    if (_email.text.trim().isEmpty || _apiKey.text.trim().isEmpty) {
      return setState(() => _loginError = 'Vui lòng nhập đủ email, API key');
    }
    setState(() {
      _busy = true;
      _loginError = null;
    });
    try {
      await _sdk.signIn(email: _email.text.trim(), apiKey: _apiKey.text.trim());
      // đăng nhập được → nhớ lại cho lần sau (đăng xuất vẫn giữ)
      await _run(() async {
        await _keyStore.write(key: _kSavedEmail, value: _email.text.trim());
        await _keyStore.write(key: _kSavedApiKey, value: _apiKey.text.trim());
      });
      unawaited(_sdk.requestPermissions());
      unawaited(FirebaseMessaging.instance.requestPermission()); // iOS: APNs → token FCM
    } on ZenifySdkException catch (e) {
      setState(() => _loginError = e.message);
    } catch (e) {
      setState(() => _loginError = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Nút "Đăng xuất" trên header màn quay số → về màn đăng nhập (accountChanges = null).
  Future<void> _signOut() async {
    setState(() => _busy = true);
    await _run(_sdk.signOut);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _run(Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      debugPrint('[demo] LỖI: $e');
    }
  }

  @override
  void dispose() {
    _apiKey.dispose();
    for (final s in _subs) {
      s.cancel();
    }
    _lifecycle.dispose();
    super.dispose();
  }

  /// Màn khởi đầu khi CHƯA đăng nhập: email + API key + nút Đăng nhập, không điều hướng nào khác.
  Widget _loginScreen() => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.phone_in_talk_rounded, size: 56, color: Color(0xFF4081EC)),
              const SizedBox(height: 12),
              const Text(
                'Đăng nhập',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _email,
                enabled: !_busy,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _apiKey,
                enabled: !_busy,
                obscureText: !_showKey,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submitLogin(),
                decoration: InputDecoration(
                  labelText: 'API key',
                  border: const OutlineInputBorder(),
                  errorText: _loginError,
                  suffixIcon: IconButton(
                    icon: Icon(_showKey ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _showKey = !_showKey),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _submitLogin,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                child: _busy
                    ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Đăng nhập'),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    // Mở app: đang khôi phục phiên → vòng xoay (không nháy màn đăng nhập)
    if (!_triedRestore) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    // CHƯA đăng nhập → chỉ màn đăng nhập (email + API key)
    if (_account == null) return _loginScreen();
    // Đã đăng nhập (vừa đăng nhập / khôi phục phiên) → màn CRM / Gọi thủ công
    return DemoHome(account: _account!, busy: _busy, onSignOut: _signOut);
  }
}

// ===================== Giao diện cuộc gọi: mặc định & tuỳ biến =====================

/// Tên khách hàng hiện trên CallKit khi gọi ra.
Future<String?> _customerName(String number) async => (await ZenifyCall.instance.findCustomerByPhone(number))?.name;

/// Ví dụ tuỳ biến: theme tối + phím vuông bo góc.
ZenifyPhoneDial customDial(BuildContext context, {Widget? leading, bool popOnCall = true, String? initialNumber}) =>
    ZenifyPhoneDial(
      initialNumber: initialNumber,
      leading: leading,
      displayNameFor: _customerName,
      onCallStarted: popOnCall ? (_) => Navigator.of(context).maybePop() : null,
      theme: const ZenifyCallTheme(
        dialBackground: Color(0xFF111827),
        dialKeyColor: Color(0xFF1F2937),
        dialDigitStyle: TextStyle(fontSize: 28, fontWeight: FontWeight.w600, color: Colors.white),
        dialLettersStyle: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
        dialNumberStyle: TextStyle(fontSize: 34, letterSpacing: 2, color: Colors.white),
        dialPlaceholderColor: Color(0xFF374151),
        dialCallColor: Color(0xFF10B981),
        dialHeaderDivider: Color(0xFF1F2937),
        dialHeaderStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
        dialIconColor: Colors.white70,
      ),
      strings: const ZenifyCallStrings(dialPlaceholder: 'Enter number'),
      keyBuilder: (context, digit, letters, onPressed) => SizedBox(
        width: 84,
        height: 64,
        child: FilledButton.tonal(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF1F2937),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          onPressed: onPressed,
          child: Text(digit, style: const TextStyle(fontSize: 26)),
        ),
      ),
    );

/// Màn cuộc gọi tuỳ biến: nền gradient, chữ tiếng Anh, thêm nút "Ghi chú", thẻ "Khách VIP".
final customCallView = ZenifyCallView(
  theme: const ZenifyCallTheme(
    callBackground: Colors.transparent,
    controlColor: Color(0x33FFFFFF),
    controlActiveColor: Color(0xFFF59E0B),
  ),
  strings: const ZenifyCallStrings(
    outgoing: 'Calling…',
    incoming: 'Incoming call',
    ringing: 'Ringing',
    earlyMedia: 'Ringback',
    mute: 'Mute',
    speaker: 'Speaker',
    keypad: 'Keypad',
    hideKeypad: 'Hide keypad',
  ),
  controls: [
    CallControl.mute,
    CallControl.speaker,
    CallControl.bluetooth,
    CallControl.keypad,
    CallControl.custom(
      label: 'Ghi chú',
      icon: Icons.edit_note,
      onPressed: (c) => debugPrint('[demo] ghi chú cho cuộc ${c.value?.callId}'),
    ),
  ],
  infoBuilder: (context, s, c, def) => Column(
    children: [
      if (s.name.isNotEmpty) const Chip(avatar: Icon(Icons.star, size: 16), label: Text('Khách VIP')),
      def,
    ],
  ),
  backgroundBuilder: (context, s, c, def) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF1E3A8A), Color(0xFF7C3AED)],
      ),
    ),
    child: def,
  ),
);
