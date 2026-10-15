// Chụp giao diện cuộc gọi để so với app RN (chạy trên simulator, không cần SIP):
//   flutter run -t lib/screenshot_main.dart   → PNG trong thư mục tmp của app
//   chụp lần lượt bản MẶC ĐỊNH (zc_*.png) rồi bản TUỲ BIẾN (zc_custom_*.png)
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:zenify_call/zenify_call.dart';

import 'main.dart' show customCallView, customDial;
import 'preview.dart';

void main() => runApp(const _ShotApp());

class _ShotApp extends StatefulWidget {
  const _ShotApp();
  @override
  State<_ShotApp> createState() => _ShotAppState();
}

class _ShotAppState extends State<_ShotApp> {
  bool custom = false;
  final _boundary = GlobalKey();
  final backend = PreviewBackend();
  late final call = ActiveCallController(backend: backend, lookupCustomer: false)..attach();
  late final dial = DialController(backend: backend)..attach();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _shot(String name) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final b = _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await b.toImage(pixelRatio: 3);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    final f = File('${Directory.systemTemp.path}/zc_${custom ? 'custom_' : ''}$name.png');
    await f.writeAsBytes(png!.buffer.asUint8List());
    debugPrint('[shot] ${f.path}');
  }

  Future<void> _run() async {
    await _sequence();
    setState(() => custom = true);
    dial.clear();
    await _sequence();
    await File('${Directory.systemTemp.path}/zc_done').writeAsString('ok');
    debugPrint('[shot] done');
  }

  Future<void> _sequence() async {
    await _shot('1_dial_empty');
    for (final d in '0901234567'.split('')) {
      dial.insert(d);
    }
    await _shot('2_dial_number');
    backend.emit(CallEventType.incoming, dir: CallDirection.incoming);
    await _shot('3_incoming');
    backend.emit(CallEventType.ended);
    backend.emit(CallEventType.outgoing);
    await _shot('4_outgoing');
    backend.emit(CallEventType.connected, at: DateTime.now().subtract(const Duration(seconds: 83)));
    await _shot('5_connected');
    call.toggleKeypad();
    await call.sendDtmf('1');
    await call.sendDtmf('2');
    await _shot('6_keypad');
    call.toggleKeypad();
    backend.network(NetworkStatus.offline);
    await _shot('7_offline');
    backend.network(NetworkStatus.online);
    backend.emit(CallEventType.ended);
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: _boundary,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: ZenifyCallOverlay(
          controller: call,
          callView: custom ? customCallView : null,
          child: Builder(
            builder: (context) => ZenifyPhoneDialPage(
              key: ValueKey(custom),
              dial: custom ? _customDial(context) : ZenifyPhoneDial(controller: dial, onBack: () {}),
            ),
          ),
        ),
      ),
    );
  }
}

extension on _ShotAppState {
  /// Bản tuỳ biến của demo nhưng dùng controller giả để chụp.
  ZenifyPhoneDial _customDial(BuildContext context) {
    final d = customDial(context);
    return ZenifyPhoneDial(
      controller: dial,
      onBack: () {},
      theme: d.theme,
      strings: d.strings,
      keyBuilder: d.keyBuilder,
    );
  }
}
