// Xem trước giao diện cuộc gọi KHÔNG cần cuộc gọi thật — backend giả phát sự kiện như zcore.
// Dùng khi chỉnh theme / slot: chạy app → nút "Xem trước" → chọn trạng thái.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:zenify_call/zenify_call.dart';

class PreviewBackend implements CallBackend {
  final _calls = StreamController<CallEvent>.broadcast();
  final _reg = StreamController<RegistrationState>.broadcast();
  final _route = StreamController<AudioRouteInfo>.broadcast();
  final _net = StreamController<NetworkStatus>.broadcast();

  void emit(CallEventType type, {CallDirection dir = CallDirection.outgoing, int code = 0, DateTime? at}) =>
      _calls.add(CallEvent(seq: 0, type: type, callId: 'preview', direction: dir, number: '0901234567', code: code, connectedAt: at));

  void network(NetworkStatus s) => _net.add(s);

  @override
  Stream<CallEvent> get calls => _calls.stream;
  @override
  Stream<RegistrationState> get registration => _reg.stream;
  @override
  Stream<AudioRouteInfo> get audioRoutes => _route.stream;
  @override
  Stream<NetworkStatus> get networkChanges => _net.stream;
  @override
  Future<Map<String, dynamic>> snapshot() async => {'registration': 'registered', 'calls': []};
  @override
  Future<void> answer(String id) async => emit(CallEventType.connected, dir: CallDirection.incoming, at: DateTime.now());
  @override
  Future<void> decline(String id) async => emit(CallEventType.ended);
  @override
  Future<void> hangup(String id) async => emit(CallEventType.ended);
  @override
  Future<void> setMute(String id, bool m) async {}
  @override
  Future<void> sendDtmf(String id, String d) async {}
  @override
  Future<AudioRouteInfo> getAudioRoute() async => const AudioRouteInfo(AudioRoute.earpiece);
  @override
  Future<bool> setAudioRoute(AudioRoute r) async => r != AudioRoute.bluetooth;
  @override
  Future<NetworkStatus> networkStatus() async => NetworkStatus.online;
  @override
  Future<CustomerInfo?> findCustomerByPhone(String p) async => null;
  @override
  Future<String> makeCall(String n, {String? customCallId, String? displayName}) async {
    emit(CallEventType.outgoing);
    return 'preview';
  }

  @override
  Future<void> retryRegistration() async {}
  PhoneType _phoneType = PhoneType.mobileApp;
  @override
  Future<PhoneType?> getPhoneType() async => _phoneType;
  @override
  Future<void> setPhoneType(PhoneType t) async => _phoneType = t;
  @override
  Stream<PhoneType?> get phoneTypeChanges => const Stream.empty();
}

/// Màn xem trước: chọn trạng thái → màn cuộc gọi (mặc định hoặc tuỳ biến) phủ lên.
class CallUiPreviewPage extends StatefulWidget {
  const CallUiPreviewPage({super.key, this.callView});
  final ZenifyCallView? callView;

  @override
  State<CallUiPreviewPage> createState() => _CallUiPreviewPageState();
}

class _CallUiPreviewPageState extends State<CallUiPreviewPage> {
  final backend = PreviewBackend();
  late final controller = ActiveCallController(backend: backend, lookupCustomer: false)..attach();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ZenifyCallOverlay(
      controller: controller,
      callView: widget.callView,
      child: Scaffold(
        appBar: AppBar(title: const Text('Xem trước giao diện cuộc gọi')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            FilledButton(
              onPressed: () => backend.emit(CallEventType.incoming, dir: CallDirection.incoming),
              child: const Text('Cuộc gọi đến'),
            ),
            FilledButton(onPressed: () => backend.emit(CallEventType.outgoing), child: const Text('Đang gọi ra')),
            FilledButton(
              onPressed: () {
                backend.emit(CallEventType.outgoing);
                Future<void>.delayed(const Duration(milliseconds: 50), () => backend.emit(CallEventType.ringing, code: 180));
              },
              child: const Text('Đang đổ chuông (180)'),
            ),
            FilledButton(
              onPressed: () => backend.emit(CallEventType.connected, at: DateTime.now().subtract(const Duration(seconds: 83))),
              child: const Text('Đã nối máy (01:23)'),
            ),
            FilledButton(
              onPressed: () {
                backend.emit(CallEventType.connected, at: DateTime.now());
                Future<void>.delayed(const Duration(milliseconds: 50), () => backend.network(NetworkStatus.offline));
              },
              child: const Text('Mất mạng trong cuộc gọi'),
            ),
          ],
        ),
      ),
    );
  }
}
