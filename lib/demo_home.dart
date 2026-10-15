// Màn chính sau đăng nhập — mô phỏng app CRM của khách tích hợp SDK:
//   · CRM: danh sách khách cần liên hệ, bấm 📞 = click-to-call (makeCall + tên khách)
//   · Gọi: nhập số / extension + chọn theme → mở màn quay số SDK điền sẵn số đó
// Header: trạng thái SIP (Online / Offline) + extension (= agent_id) + nút đăng xuất.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:zenify_call/zenify_call.dart';

import 'main.dart' show customDial;

/// Số test cho demo (`--dart-define=ZC_DEMO_PHONE=…`) — mọi khách trong danh sách đều gọi về số này.
const kDemoPhone = String.fromEnvironment('ZC_DEMO_PHONE', defaultValue: '0900000000');

// Bảng màu M-Call (Teal & Mint)
const _teal = Color(0xFF0B6B5C);
const _tealDark = Color(0xFF0A4F45);
const _mint = Color(0xFFD7EEE6);
const _bg = Color(0xFFF2F5F4);
const _muted = Color(0xFF5F6B68);

/// Theme màn cuộc gọi SDK — chọn ở tab "Gọi", overlay trong `main.dart` đọc.
enum CallScreenStyle {
  mcall('Mặc định M-Call (Teal & Mint)'),
  zenify('Zenify (Xanh dương)'),
  custom('Tuỳ biến (Gradient tím)');

  const CallScreenStyle(this.label);
  final String label;
}

final callScreenStyle = ValueNotifier(CallScreenStyle.mcall);

/// Màn cuộc gọi theme M-Call.
const mcallCallView = ZenifyCallView(
  theme: ZenifyCallTheme(
    callBackground: _tealDark,
    controlColor: Color(0x33FFFFFF),
    controlActiveColor: Color(0xFF5ED3B0),
    answerColor: Color(0xFF2ECC8F),
    statusColor: Color(0xFFB5DCD0),
    statusStyle: TextStyle(fontSize: 16, color: Color(0xFFB5DCD0)),
  ),
);

class _Customer {
  const _Customer(this.name, this.phone, this.tag, this.note, this.history);
  final String name;
  final String phone;
  final String tag;
  final String note;
  final String history;

  String get initials {
    final w = name.trim().split(RegExp(r'\s+'));
    return (w.length == 1 ? w.first.substring(0, 1) : '${w.first[0]}${w.last[0]}').toUpperCase();
  }
}

/// Danh sách khách màn CRM. Ghi đè bằng `--dart-define=ZC_DEMO_CUSTOMERS=<JSON>` (mảng
/// `{name, phone, tag, note, history}`); thiếu / sai JSON → dữ liệu mẫu bên dưới (số giả).
final List<_Customer> _customers = _loadCustomers();

List<_Customer> _loadCustomers() {
  const raw = String.fromEnvironment('ZC_DEMO_CUSTOMERS');
  if (raw.isNotEmpty) {
    try {
      final list = [
        for (final e in jsonDecode(raw) as List)
          if (e is Map && '${e['name'] ?? ''}'.isNotEmpty && '${e['phone'] ?? ''}'.isNotEmpty)
            _Customer(
              '${e['name']}',
              '${e['phone']}',
              '${e['tag'] ?? ''}',
              '${e['note'] ?? ''}',
              '${e['history'] ?? ''}',
            ),
      ];
      if (list.isNotEmpty) return list;
    } catch (e) {
      debugPrint('[demo] ZC_DEMO_CUSTOMERS sai JSON: $e');
    }
  }
  return const [
    _Customer(
      'Nguyễn Văn A',
      kDemoPhone,
      'Ưu tiên',
      'Quan tâm gói bảo vệ gia đình, hẹn tư vấn sau 14:00.',
      'Hôm qua · Chưa kết nối',
    ),
    _Customer(
      'Trần Thị B',
      '0900000001',
      'Theo dõi',
      'Đã nhận báo giá, cần giải thích thêm quyền lợi nội trú.',
      '12/08 · 03:42 phút',
    ),
    _Customer('Lê Văn C', '0900000002', 'Mới', 'Khách hàng mới từ chiến dịch landing page tháng 8.', 'Chưa liên hệ'),
  ];
}

class DemoHome extends StatefulWidget {
  const DemoHome({super.key, required this.account, required this.onSignOut, this.busy = false});

  final ZenifyAccount account;
  final VoidCallback onSignOut;
  final bool busy;

  @override
  State<DemoHome> createState() => _DemoHomeState();
}

class _DemoHomeState extends State<DemoHome> {
  final _sdk = ZenifyCall.instance;
  int _tab = 0;
  bool _online = false;
  StreamSubscription<RegistrationState>? _reg;

  @override
  void initState() {
    super.initState();
    _reg = _sdk.registration.listen(
      (r) => setState(() => _online = r.status == RegistrationStatus.registered),
      onError: (Object e) => debugPrint('[demo] registration: $e'),
    );
    // trạng thái hiện tại (sự kiện registration có thể đã bắn trước khi vào màn)
    _sdk.snapshot().then((s) {
      if (mounted) setState(() => _online = s['registration'] == 'registered');
    }, onError: (Object _) {});
  }

  @override
  void dispose() {
    _reg?.cancel();
    super.dispose();
  }

  /// Gọi ra → SDK tự phủ màn cuộc gọi (ZenifyCallOverlay). Lỗi trước khi tạo cuộc → snackbar.
  Future<void> _call(String number, {String? name}) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _sdk.makeCall(number, displayName: name ?? (await _sdk.findCustomerByPhone(number))?.name);
    } on ZenifySdkException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [_CrmTab(onCall: _call), const _ManualDialTab()];
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: ColorScheme.fromSeed(seedColor: _teal, primary: _teal, surface: _bg),
        scaffoldBackgroundColor: _bg,
      ),
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: _bg,
          surfaceTintColor: Colors.transparent,
          titleSpacing: 20,
          title: Text(_tab == 0 ? 'CRM' : 'Gọi thủ công', style: const TextStyle(fontSize: 26)),
          actions: [
            _StatusChip(online: _online, extension: widget.account.agentId),
            IconButton(
              tooltip: 'Đăng xuất',
              onPressed: widget.busy ? null : widget.onSignOut,
              icon: widget.busy
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.logout),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: IndexedStack(index: _tab, children: tabs),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          indicatorColor: _mint,
          backgroundColor: const Color(0xFFE6ECEA),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.groups), label: 'CRM'),
            NavigationDestination(icon: Icon(Icons.dialpad), label: 'Gọi'),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.online, required this.extension});
  final bool online;
  final String extension;

  @override
  Widget build(BuildContext context) {
    final color = online ? _teal : const Color(0xFF9AA5A2);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: online ? _mint : const Color(0xFFE6E9E8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 8, color: color),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                online ? 'Online' : 'Offline',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color),
              ),
              Text('Ext. $extension', style: TextStyle(fontSize: 11, color: color)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Nhãn nhỏ màu teal + tiêu đề đậm + mô tả — đầu mỗi tab.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.eyebrow, required this.title, required this.subtitle});
  final String eyebrow;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        eyebrow,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _teal),
      ),
      const SizedBox(height: 2),
      Text(title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
      const SizedBox(height: 4),
      Text(subtitle, style: const TextStyle(fontSize: 13, color: _muted)),
      const SizedBox(height: 16),
    ],
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding = const EdgeInsets.all(20)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
    child: child,
  );
}

// ===================== Tab CRM =====================

class _CrmTab extends StatelessWidget {
  const _CrmTab({required this.onCall});
  final Future<void> Function(String number, {String? name}) onCall;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
    children: [
      _SectionHeader(
        eyebrow: 'Hôm nay · ${_customers.length} khách hàng',
        title: 'Danh sách cần liên hệ',
        subtitle: 'Click-to-call mô phỏng workflow từ CRM của khách.',
      ),
      _Card(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            for (final (i, c) in _customers.indexed) ...[
              if (i > 0) const Divider(height: 1, indent: 104),
              _CustomerRow(
                customer: c,
                onCall: () => onCall(c.phone, name: c.name),
              ),
            ],
          ],
        ),
      ),
    ],
  );
}

class _CustomerRow extends StatelessWidget {
  const _CustomerRow({required this.customer, required this.onCall});
  final _Customer customer;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: _mint, borderRadius: BorderRadius.circular(16)),
          child: Text(
            customer.initials,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _tealDark),
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(customer.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  ),
                  Text(
                    customer.tag,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _teal),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(customer.phone, style: const TextStyle(fontSize: 16, letterSpacing: 1, color: _muted)),
              const SizedBox(height: 8),
              Text(customer.note, style: const TextStyle(fontSize: 15)),
              const SizedBox(height: 8),
              Text(customer.history, style: const TextStyle(fontSize: 13, color: _muted)),
            ],
          ),
        ),
        const SizedBox(width: 12),
        IconButton.filled(
          tooltip: 'Gọi ${customer.name}',
          onPressed: onCall,
          style: IconButton.styleFrom(
            backgroundColor: _mint,
            foregroundColor: _tealDark,
            fixedSize: const Size.square(44),
          ),
          icon: const Icon(Icons.phone_outlined),
        ),
      ],
    ),
  );
}

// ===================== Tab Gọi thủ công =====================

class _ManualDialTab extends StatefulWidget {
  const _ManualDialTab();

  @override
  State<_ManualDialTab> createState() => _ManualDialTabState();
}

class _ManualDialTabState extends State<_ManualDialTab> {
  final _number = TextEditingController(text: kDemoPhone);

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  /// Mở màn quay số SDK (theme theo lựa chọn) điền sẵn số; bấm gọi trên đó → màn cuộc gọi.
  void _submit() {
    FocusScope.of(context).unfocus();
    final number = normalizeDialNumber(_number.text);
    Future<String?> nameFor(String n) async => (await ZenifyCall.instance.findCustomerByPhone(n))?.name;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) {
          void pop(String _) => Navigator.of(context).maybePop();
          return ZenifyPhoneDialPage(
            dial: switch (callScreenStyle.value) {
              CallScreenStyle.custom => customDial(context, initialNumber: number),
              CallScreenStyle.zenify => ZenifyPhoneDial(
                initialNumber: number,
                displayNameFor: nameFor,
                onCallStarted: pop,
              ),
              CallScreenStyle.mcall => ZenifyPhoneDial(
                initialNumber: number,
                displayNameFor: nameFor,
                onCallStarted: pop,
                theme: const ZenifyCallTheme(dialCallColor: _teal, dialCallNotReadyColor: Color(0xFF7FA79F)),
              ),
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: Color(0xFFD5DBD9)),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        const _SectionHeader(
          eyebrow: 'Quick dial',
          title: 'Gọi thủ công',
          subtitle: 'Nhập extension hoặc số điện thoại ngoài danh sách.',
        ),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _number,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                style: const TextStyle(fontSize: 18),
                decoration: InputDecoration(
                  hintText: 'Số điện thoại hoặc extension',
                  prefixIcon: const Icon(Icons.dialpad),
                  filled: true,
                  fillColor: const Color(0xFFF7F9F8),
                  border: border,
                  enabledBorder: border,
                ),
              ),
              const SizedBox(height: 16),
              ValueListenableBuilder(
                valueListenable: callScreenStyle,
                builder: (context, style, _) => DropdownButtonFormField<CallScreenStyle>(
                  initialValue: style,
                  isExpanded: true,
                  onChanged: (s) => callScreenStyle.value = s ?? style,
                  decoration: InputDecoration(
                    labelText: 'Call screen theme',
                    prefixIcon: const Icon(Icons.palette_outlined),
                    filled: true,
                    fillColor: const Color(0xFFF7F9F8),
                    border: border,
                    enabledBorder: border,
                  ),
                  items: [
                    for (final s in CallScreenStyle.values)
                      DropdownMenuItem(
                        value: s,
                        child: Text(s.label, style: const TextStyle(fontSize: 17)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: _teal,
                  minimumSize: const Size.fromHeight(60),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                icon: const Icon(Icons.phone),
                label: const Text('Mở SDK Call Screen'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
