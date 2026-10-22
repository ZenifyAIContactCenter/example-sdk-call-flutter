// Xem tab Dashboard KHÔNG cần đăng nhập (số liệu giả theo response thật của API):
//   flutter run -t lib/dashboard_preview.dart
import 'package:flutter/material.dart';
import 'package:zenify_call/zenify_call.dart';

import 'dashboard_tab.dart';

/// `--dart-define=ZC_PREVIEW_SCROLL=900` → mở sẵn ở vị trí cuộn đó (chụp màn phần dưới).
const _scroll = int.fromEnvironment('ZC_PREVIEW_SCROLL');

void main() => runApp(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0B6B5C)),
          scaffoldBackgroundColor: const Color(0xFFF2F5F4),
        ),
        home: Scaffold(
          appBar: AppBar(
            backgroundColor: const Color(0xFFF2F5F4),
            centerTitle: false,
            title: const Text('Dashboard', style: TextStyle(fontSize: 26)),
          ),
          body: DashboardTab(
            scrollController: ScrollController(initialScrollOffset: _scroll.toDouble()),
            online: true,
            account: ZenifyAccount(
              email: 'agent@demo.vn',
              userId: 'u1',
              tenantId: 't1',
              agentId: '1235',
              name: 'Telesale Agent',
              role: 'agent',
              expiresAt: DateTime(2100),
            ),
            source: DashboardSource(
              // response /v2/report/call-daily + /v2/monitor/call đo 2026-10-22
              callDaily: () async => CallDailyStats.fromJson(const {
                'total': 39, 'miss_call': 25, 'answer_call': 14, 'reject_call': 5,
                'average_time_answer': '00:00:04', 'average_time_waiting': '00:00:06',
                'call_in': 34, 'miss_call_in': 25, 'answer_call_in': 9, 'reject_call_in': 5,
                'average_time_answer_in': '00:00:04', 'average_time_waiting_in': '00:00:07',
                'call_out': 5, 'miss_call_out': 0, 'miss_call_out_prd': 0, 'answer_call_out': 5,
                'reject_call_out': 0, 'average_time_answer_out': '00:00:05',
                'average_time_waiting_out': '00:00:06', 'average_time_waiting_out_prd': '00:00:00',
              }),
              monitor: () async => MonitorStats.fromJson(const {
                'realtime': {'call_ringing': 0, 'call_answering': 1, 'call_queue': [0]},
                'analytic': {'totalFacebook': 0, 'totalZalo': 0, 'totalChat': 0, 'totalEmail': 6,
                  'totalEmailWaiting': 6},
              }),
              agentStatus: () async =>
                  const AgentStatus(phoneType: PhoneType.mobileApp, rawPhoneType: 5, workingStatus: kAvailable),
              talkTime: () async => const TalkTime(total: Duration(hours: 1, minutes: 48), answered: 28),
            ),
          ),
        ),
      ),
    );
