#!/usr/bin/env python3
"""Sinh lib/firebase_options.dart từ file cấu hình Firebase của app (KHÔNG commit cả 3 file).

  android/app/google-services.json        ← Firebase console (Android, package của app)
  ios/Runner/GoogleService-Info.plist     ← Firebase console (iOS, bundle id của app)
  → lib/firebase_options.dart             (Firebase.initializeApp(options: …))

Thay cho `flutterfire configure` để không phải đăng nhập Firebase CLI.
"""
import json, os, plistlib, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
aj = os.path.join(ROOT, 'android/app/google-services.json')
ip = os.path.join(ROOT, 'ios/Runner/GoogleService-Info.plist')
out = os.path.join(ROOT, 'lib/firebase_options.dart')

def dart(v):
    return "'" + str(v).replace("\\", "\\\\").replace("'", "\\'") + "'"

android = ios = 'null'
if os.path.exists(aj):
    j = json.load(open(aj))
    c = j['client'][0]
    android = (f"FirebaseOptions(apiKey: {dart(c['api_key'][0]['current_key'])}, "
               f"appId: {dart(c['client_info']['mobilesdk_app_id'])}, "
               f"messagingSenderId: {dart(j['project_info']['project_number'])}, "
               f"projectId: {dart(j['project_info']['project_id'])}, "
               f"storageBucket: {dart(j['project_info'].get('storage_bucket', ''))})")
if os.path.exists(ip):
    p = plistlib.load(open(ip, 'rb'))
    ios = (f"FirebaseOptions(apiKey: {dart(p['API_KEY'])}, appId: {dart(p['GOOGLE_APP_ID'])}, "
           f"messagingSenderId: {dart(p['GCM_SENDER_ID'])}, projectId: {dart(p['PROJECT_ID'])}, "
           f"storageBucket: {dart(p.get('STORAGE_BUCKET', ''))}, iosBundleId: {dart(p['BUNDLE_ID'])})")
if android == 'null' and ios == 'null':
    sys.exit('!! không thấy google-services.json / GoogleService-Info.plist')

open(out, 'w').write(f"""// SINH TỰ ĐỘNG bởi tool/gen_firebase_options.py — KHÔNG commit, KHÔNG sửa tay.
// ignore_for_file: unnecessary_nullable_for_final_variable_declarations
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {{
  static FirebaseOptions? get currentPlatform => switch (defaultTargetPlatform) {{
    TargetPlatform.android => _android,
    TargetPlatform.iOS => _ios,
    _ => null,
  }};

  static const FirebaseOptions? _android = {android if android != 'null' else 'null'};
  static const FirebaseOptions? _ios = {ios if ios != 'null' else 'null'};
}}
""")
print('→', out, '| android:', android != 'null', '| ios:', ios != 'null')
