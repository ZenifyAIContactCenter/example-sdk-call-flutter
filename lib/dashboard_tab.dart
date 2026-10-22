// Tab Dashboard — số liệu trong ngày của agent, cùng API với trang "Hoạt động trong ngày" của
// web Zenify (monitors/daily-stats):
//   · ZenifyCall.getCallDailyStats() → GET /v2/report/call-daily  (cuộc gọi vào / ra)
//   · ZenifyCall.getMonitorStats()   → GET /v2/monitor/call       (kênh tương tác / hàng đợi)
//   · ZenifyCall.getAgentStatus()    → GET /v2/me/agent-status    (trạng thái làm việc)
//   · ZenifyCall.getCallHistory()    → POST /v3/report/call-history (cộng "Thời gian thoại")
// Agent chỉ thấy số của mình (SDK tự lọc). Tự tải lại mỗi 20s như web, kéo xuống để tải ngay.
// Chỉ tiêu, ca làm, số lead, chiến dịch: Zenify CHƯA có API → lấy từ [DashboardDemo]
// (`--dart-define`), app thật thay bằng dữ liệu CRM / backend của mình.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:zenify_call/zenify_call.dart';

const _teal = Color(0xFF0B6B5C);
const _tealDark = Color(0xFF0A4F45);
const _mint = Color(0xFFD7EEE6);
const _muted = Color(0xFF5F6B68);
const _line = Color(0xFFE3E8E6);
const _orange = Color(0xFFF2994A);
const _green = Color(0xFF2ECC71);
const _grey = Color(0xFF9AA5A2);
const _blue = Color(0xFF2F6FED);

/// Chu kỳ tự tải lại — như web (`STAT_POLL_INTERVAL_MS`).
const _pollEvery = Duration(seconds: 20);

/// Thời gian thoại trong ngày — cộng `duration` các cuộc ĐÃ NGHE trong lịch sử cuộc gọi.
class TalkTime {
  const TalkTime({this.total = Duration.zero, this.answered = 0});
  final Duration total;
  final int answered;

  /// Trung bình mỗi cuộc đã nghe.
  Duration get average => answered == 0 ? Duration.zero : Duration(seconds: total.inSeconds ~/ answered);

  /// Đọc tối đa [maxPages] × 100 cuộc từ 0:00 hôm nay.
  static Future<TalkTime> today(ZenifyCall sdk, {int maxPages = 10}) async {
    final now = DateTime.now();
    final filter = CallHistoryFilter(from: DateTime(now.year, now.month, now.day), to: now);
    var seconds = 0, answered = 0;
    for (var page = 1; page <= maxPages; page++) {
      final p = await sdk.getCallHistory(filter: filter, page: page, pageSize: 100);
      for (final c in p.items) {
        if (!c.isAnswered) continue;
        answered++;
        seconds += c.duration;
      }
      if (!p.hasMore) break;
    }
    return TalkTime(total: Duration(seconds: seconds), answered: answered);
  }
}

/// Số liệu Zenify CHƯA có API (chỉ tiêu, ca, lead, chiến dịch) — demo đọc từ `--dart-define`,
/// app thật lấy từ CRM / backend riêng.
class DashboardDemo {
  const DashboardDemo({
    this.dailyTarget = 40,
    this.shift = '08:30 - 17:30',
    this.center = 'M-Call Center',
    this.leads = 5,
    this.campaignName = 'Chiến dịch Telesale VIP Q3',
    this.campaignDesc = 'Tư vấn Doanh nghiệp & CSKH',
    this.campaignDone = 65,
    this.campaignTotal = 100,
  });

  /// `ZC_DEMO_TARGET` — chỉ tiêu cuộc gọi / ngày.
  final int dailyTarget;

  /// `ZC_DEMO_SHIFT` / `ZC_DEMO_CENTER`.
  final String shift;
  final String center;

  /// `ZC_DEMO_LEADS` — số lịch hẹn đã chốt hôm nay.
  final int leads;

  /// `ZC_DEMO_CAMPAIGN` / `ZC_DEMO_CAMPAIGN_DESC` / `ZC_DEMO_CAMPAIGN_DONE` / `ZC_DEMO_CAMPAIGN_TOTAL`.
  final String campaignName;
  final String campaignDesc;
  final int campaignDone;
  final int campaignTotal;

  static const fromEnvironment = DashboardDemo(
    dailyTarget: int.fromEnvironment('ZC_DEMO_TARGET', defaultValue: 40),
    shift: String.fromEnvironment('ZC_DEMO_SHIFT', defaultValue: '08:30 - 17:30'),
    center: String.fromEnvironment('ZC_DEMO_CENTER', defaultValue: 'M-Call Center'),
    leads: int.fromEnvironment('ZC_DEMO_LEADS', defaultValue: 5),
    campaignName: String.fromEnvironment('ZC_DEMO_CAMPAIGN', defaultValue: 'Chiến dịch Telesale VIP Q3'),
    campaignDesc: String.fromEnvironment('ZC_DEMO_CAMPAIGN_DESC', defaultValue: 'Tư vấn Doanh nghiệp & CSKH'),
    campaignDone: int.fromEnvironment('ZC_DEMO_CAMPAIGN_DONE', defaultValue: 65),
    campaignTotal: int.fromEnvironment('ZC_DEMO_CAMPAIGN_TOTAL', defaultValue: 100),
  );
}

/// Nguồn số liệu của Dashboard — mặc định gọi SDK; preview / test truyền dữ liệu giả.
class DashboardSource {
  const DashboardSource({
    required this.callDaily,
    required this.monitor,
    required this.agentStatus,
    required this.talkTime,
  });

  final Future<CallDailyStats> Function() callDaily;
  final Future<MonitorStats> Function() monitor;
  final Future<AgentStatus> Function() agentStatus;
  final Future<TalkTime> Function() talkTime;

  static DashboardSource sdk(ZenifyCall sdk) => DashboardSource(
        callDaily: sdk.getCallDailyStats,
        monitor: sdk.getMonitorStats,
        agentStatus: sdk.getAgentStatus,
        talkTime: () => TalkTime.today(sdk),
      );
}

class DashboardTab extends StatefulWidget {
  const DashboardTab({
    super.key,
    required this.account,
    required this.online,
    this.onCallNext,
    this.demo = DashboardDemo.fromEnvironment,
    this.source,
    this.scrollController,
  });

  final ZenifyAccount account;

  /// SIP đã REGISTER (header DemoHome).
  final bool online;

  /// Nút "Gọi khách hàng tiếp theo" của thẻ chiến dịch.
  final VoidCallback? onCallNext;
  final DashboardDemo demo;

  /// `null` = [DashboardSource.sdk] của `ZenifyCall.instance`.
  final DashboardSource? source;
  final ScrollController? scrollController;

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  late final DashboardSource _src = widget.source ?? DashboardSource.sdk(ZenifyCall.instance);
  CallDailyStats? _calls;
  MonitorStats? _monitor;
  AgentStatus? _status;
  TalkTime? _talk;
  String? _error;
  bool _loading = true;
  DateTime? _updatedAt;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(_pollEvery, (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  /// Các API chạy song song; một cái lỗi vẫn hiện phần còn lại.
  Future<void> _load() async {
    Future<T?> safe<T>(Future<T> f) => f.then<T?>((v) => v).catchError((Object e) {
          _error = e is ZenifySdkException ? e.message : '$e';
          return null;
        });
    _error = null;
    final r = await Future.wait([
      safe(_src.callDaily()),
      safe(_src.monitor()),
      safe(_src.agentStatus()),
      safe(_src.talkTime()),
    ]);
    if (!mounted) return;
    setState(() {
      _calls = r[0] as CallDailyStats? ?? _calls;
      _monitor = r[1] as MonitorStats? ?? _monitor;
      _status = r[2] as AgentStatus? ?? _status;
      _talk = r[3] as TalkTime? ?? _talk;
      _loading = false;
      _updatedAt = DateTime.now();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = _calls;
    final m = _monitor;
    return RefreshIndicator(
      color: _teal,
      onRefresh: _load,
      child: ListView(
        controller: widget.scrollController,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          _AgentCard(account: widget.account, online: widget.online, status: _status, demo: widget.demo),
          const SizedBox(height: 24),
          Row(
            children: [
              const Expanded(
                child: Text('Hiệu suất cuộc gọi hôm nay', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              ),
              _Pill(text: _updatedAt == null ? 'Đang tải…' : 'Thời gian thực', color: _teal, background: _mint),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            _ErrorBanner(message: _error!, onRetry: _load),
          ],
          const SizedBox(height: 14),
          if (_loading && c == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator(color: _teal)),
            )
          else ...[
            _KpiGrid(stats: c ?? const CallDailyStats(), talk: _talk, demo: widget.demo),
            const SizedBox(height: 16),
            _CampaignCard(demo: widget.demo, onCallNext: widget.onCallNext),
            const SizedBox(height: 16),
            _CallSection(
              title: 'Cuộc gọi vào',
              icon: Icons.call_received,
              counts: c?.inbound ?? const CallCounts(),
              totalLabel: 'Số cuộc gọi vào',
              waitLabel: 'Thời gian chờ trung bình gọi vào',
              answerLabel: 'Thời gian trả lời trung bình gọi vào',
            ),
            const SizedBox(height: 16),
            _CallSection(
              title: 'Cuộc gọi ra',
              icon: Icons.call_made,
              counts: c?.outbound ?? const CallCounts(),
              totalLabel: 'Số cuộc gọi ra',
              waitLabel: 'Thời gian chờ trung bình gọi ra',
              answerLabel: 'Thời gian trả lời trung bình gọi ra',
              extra: [
                _StatRow(
                  icon: Icons.phone_missed,
                  color: _orange,
                  label: 'Số cuộc Predictive gặp khách bị nhỡ',
                  value: '${c?.predictiveMissed ?? 0}',
                ),
                _StatRow(
                  icon: Icons.schedule,
                  color: _orange,
                  label: 'Thời gian chờ cuộc Predictive gặp khách bị nhỡ',
                  value: _hms(c?.predictiveAvgWaiting),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _ChannelSection(stats: m ?? const MonitorStats()),
            const SizedBox(height: 16),
            _QueueSection(stats: m ?? const MonitorStats()),
          ],
        ],
      ),
    );
  }
}

// ===================== định dạng =====================

String _hms(Duration? d) {
  if (d == null) return '--:--:--';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
}

/// "3m 52s" / "1h 08m" — gọn cho thẻ KPI.
String _short(Duration? d) {
  if (d == null) return '--';
  if (d.inHours > 0) return '${d.inHours}h ${(d.inMinutes % 60).toString().padLeft(2, '0')}m';
  if (d.inMinutes > 0) return '${d.inMinutes}m ${(d.inSeconds % 60).toString().padLeft(2, '0')}s';
  return '${d.inSeconds}s';
}

String _percent(double r) => '${(r * 100).toStringAsFixed(r == 0 || r == 1 ? 0 : 1)}%';

// ===================== thẻ agent =====================

class _AgentCard extends StatelessWidget {
  const _AgentCard({required this.account, required this.online, required this.demo, this.status});
  final ZenifyAccount account;
  final bool online;
  final DashboardDemo demo;
  final AgentStatus? status;

  @override
  Widget build(BuildContext context) {
    final ws = status?.workingStatus;
    final available = ws == null || ws == kAvailable;
    final ready = online && available;
    final name = account.name.isEmpty ? account.email : account.name;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_teal, _tealDark],
        ),
        boxShadow: [BoxShadow(color: _tealDark.withValues(alpha: 0.25), blurRadius: 16, offset: const Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), shape: BoxShape.circle),
                    child: const Icon(Icons.headset_mic_outlined, color: Colors.white, size: 30),
                  ),
                  Positioned(
                    right: 2,
                    bottom: 2,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: ready ? _green : _grey,
                        shape: BoxShape.circle,
                        border: Border.all(color: _teal, width: 2.5),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$name · Ext ${account.agentId}',
                      style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      ready
                          ? 'Sẵn sàng nhận & gọi cuộc gọi tổng đài'
                          : !online
                              ? 'Chưa kết nối tổng đài'
                              : 'Đang ở trạng thái $ws',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 14),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _Pill(
                text: ready ? 'ON DUTY' : (online ? (ws ?? 'BẬN').toUpperCase() : 'OFFLINE'),
                color: Colors.white,
                background: Colors.white.withValues(alpha: 0.15),
                dot: ready ? const Color(0xFF5ED3B0) : _grey,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                Icon(Icons.schedule, size: 16, color: Colors.white.withValues(alpha: 0.8)),
                const SizedBox(width: 8),
                Text(
                  'Ca: ${demo.shift}',
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    demo.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 13),
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

// ===================== KPI =====================

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.stats, required this.demo, this.talk});
  final CallDailyStats stats;
  final DashboardDemo demo;
  final TalkTime? talk;

  @override
  Widget build(BuildContext context) {
    final a = stats.all;
    final target = demo.dailyTarget;
    final tiles = [
      _Kpi(
        title: 'Tổng cuộc gọi',
        icon: Icons.phone_in_talk_outlined,
        tint: _teal,
        value: '${a.total}',
        unit: target > 0 ? '/ $target' : null,
        caption: target > 0 ? 'Đạt ${(a.total * 100 / target).round()}% chỉ tiêu' : 'Vào ${stats.inbound.total} · Ra ${stats.outbound.total}',
      ),
      _Kpi(
        title: 'Thời gian thoại',
        icon: Icons.timer_outlined,
        tint: _blue,
        value: talk == null ? '--' : _short(talk!.total),
        caption: talk == null ? 'Đang tính…' : 'TB: ${_short(talk!.average)}/cuộc',
      ),
      _Kpi(
        title: 'Tỷ lệ nghe máy',
        icon: Icons.check_circle,
        tint: _teal,
        value: _percent(a.answerRate),
        caption: '${a.answered}/${a.total} kết nối thành công',
      ),
      _Kpi(
        title: 'Chốt lịch hẹn',
        icon: Icons.verified,
        tint: _orange,
        value: '${demo.leads}',
        unit: 'lead',
        caption: 'Tỷ lệ chốt ${_percent(a.total == 0 ? 0 : demo.leads / a.total)}',
      ),
    ];
    return LayoutBuilder(
      builder: (context, box) {
        final w = (box.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [for (final t in tiles) SizedBox(width: w, child: t)],
        );
      },
    );
  }
}

class _CampaignCard extends StatelessWidget {
  const _CampaignCard({required this.demo, this.onCallNext});
  final DashboardDemo demo;
  final VoidCallback? onCallNext;

  @override
  Widget build(BuildContext context) {
    final total = demo.campaignTotal;
    final done = demo.campaignDone.clamp(0, total);
    final ratio = total == 0 ? 0.0 : done / total;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: const Color(0xFFF1F6F4), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.campaign_outlined, color: _tealDark),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(demo.campaignName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(demo.campaignDesc, style: const TextStyle(fontSize: 13, color: _muted)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const _Pill(text: 'Đang chạy', color: Color(0xFF16803C), background: Color(0xFFDDF6E6)),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              const Expanded(child: Text('Tiến độ danh sách gọi', style: TextStyle(fontSize: 14, color: _muted))),
              Text(
                '$done / $total khách (${(ratio * 100).round()}%)',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _teal),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              color: _teal,
              backgroundColor: const Color(0xFFE6EBF2),
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onCallNext,
            style: FilledButton.styleFrom(
              backgroundColor: _teal,
              minimumSize: const Size.fromHeight(56),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            icon: const Icon(Icons.phone_forwarded),
            label: const Text('Gọi khách hàng tiếp theo'),
          ),
        ],
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({
    required this.title,
    required this.icon,
    required this.tint,
    required this.value,
    required this.caption,
    this.unit,
  });
  final String title;
  final IconData icon;
  final Color tint;
  final String value;
  final String? unit;
  final String caption;

  @override
  Widget build(BuildContext context) => _Card(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: const TextStyle(fontSize: 14, color: _muted))),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: tint.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon, size: 18, color: tint),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text.rich(
              TextSpan(
                text: value,
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                children: [
                  if (unit != null)
                    TextSpan(text: ' $unit', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: _grey)),
                ],
              ),
            ),
            const SizedBox(height: 6),
            // cỡ chữ hệ thống lớn → thu nhỏ cho vừa một dòng thay vì cắt "…"
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(caption, maxLines: 1, style: TextStyle(fontSize: 13, color: tint)),
            ),
          ],
        ),
      );
}

// ===================== khối như web =====================

class _CallSection extends StatelessWidget {
  const _CallSection({
    required this.title,
    required this.icon,
    required this.counts,
    required this.totalLabel,
    required this.waitLabel,
    required this.answerLabel,
    this.extra = const [],
  });
  final String title;
  final IconData icon;
  final CallCounts counts;
  final String totalLabel;
  final String waitLabel;
  final String answerLabel;
  final List<Widget> extra;

  @override
  Widget build(BuildContext context) => _Section(
        title: title,
        children: [
          _TileGrid(tiles: [
            _CountTile(icon: icon, color: _teal, label: totalLabel, value: counts.total),
            _CountTile(icon: Icons.phone_missed, color: _orange, label: 'Số cuộc gọi nhỡ', value: counts.missed),
            _CountTile(icon: Icons.phone_callback, color: _green, label: 'Số cuộc gọi trả lời', value: counts.answered),
            _CountTile(icon: Icons.phone_disabled, color: _grey, label: 'Số cuộc gọi từ chối', value: counts.rejected),
          ]),
          ...extra,
          _StatRow(icon: Icons.schedule, color: _teal, label: waitLabel, value: _hms(counts.avgWaiting)),
          _StatRow(icon: Icons.schedule, color: _teal, label: answerLabel, value: _hms(counts.avgAnswer)),
        ],
      );
}

class _ChannelSection extends StatelessWidget {
  const _ChannelSection({required this.stats});
  final MonitorStats stats;

  @override
  Widget build(BuildContext context) => _Section(
        title: 'Kênh tương tác',
        children: [
          _TileGrid(tiles: [
            _CountTile(icon: Icons.facebook, color: _teal, label: 'Facebook', value: stats.facebook.total),
            _CountTile(icon: Icons.chat_bubble_outline, color: _teal, label: 'Zalo', value: stats.zalo.total),
            _CountTile(icon: Icons.forum_outlined, color: _teal, label: 'LiveChat', value: stats.liveChat.total),
            _CountTile(icon: Icons.mail_outline, color: _teal, label: 'Email', value: stats.email.total),
          ]),
        ],
      );
}

class _QueueSection extends StatelessWidget {
  const _QueueSection({required this.stats});
  final MonitorStats stats;

  @override
  Widget build(BuildContext context) {
    final rt = stats.realtime;
    return _Section(
      title: 'Hàng đợi',
      children: [
        _TileGrid(tiles: [
          _CountTile(icon: Icons.forum_outlined, color: _teal, label: 'Hội thoại', value: stats.conversationsWaiting),
          _CountTile(icon: Icons.phone_outlined, color: _teal, label: 'Cuộc gọi', value: rt.inQueue),
        ]),
        _TileGrid(tiles: [
          _CountTile(icon: Icons.ring_volume_outlined, color: _blue, label: 'Đang đổ chuông', value: rt.ringing),
          _CountTile(icon: Icons.record_voice_over_outlined, color: _blue, label: 'Đang nói', value: rt.answering),
        ]),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            for (final (i, c) in children.indexed) ...[if (i > 0) const SizedBox(height: 10), c],
          ],
        ),
      );
}

class _TileGrid extends StatelessWidget {
  const _TileGrid({required this.tiles});
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) {
          final w = (box.maxWidth - 10) / 2;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [for (final t in tiles) SizedBox(width: w, child: t)],
          );
        },
      );
}

class _CountTile extends StatelessWidget {
  const _CountTile({required this.icon, required this.color, required this.label, required this.value});
  final IconData icon;
  final Color color;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: const Color(0xFFF1F6F4), borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            _RoundIcon(icon: icon, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label, maxLines: 2, style: const TextStyle(fontSize: 13, color: Color(0xFF3D4745))),
            ),
            Text('$value', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _blue)),
          ],
        ),
      );
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.icon, required this.color, required this.label, required this.value});
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: const Color(0xFFF1F6F4), borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            _RoundIcon(icon: icon, color: color),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF3D4745)))),
            const SizedBox(width: 8),
            Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _blue)),
          ],
        ),
      );
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Icon(icon, size: 17, color: Colors.white),
      );
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding = const EdgeInsets.all(18)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _line),
        ),
        child: child,
      );
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color, required this.background, this.dot});
  final String text;
  final Color color;
  final Color background;
  final Color? dot;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(20)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dot != null) ...[Icon(Icons.circle, size: 8, color: dot), const SizedBox(width: 6)],
            Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color, letterSpacing: 0.5)),
          ],
        ),
      );
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        decoration: BoxDecoration(color: const Color(0xFFFDECEA), borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            const Icon(Icons.error_outline, size: 18, color: Color(0xFFC62828)),
            const SizedBox(width: 8),
            Expanded(child: Text(message, style: const TextStyle(fontSize: 13, color: Color(0xFFC62828)))),
            TextButton(onPressed: onRetry, child: const Text('Thử lại')),
          ],
        ),
      );
}
