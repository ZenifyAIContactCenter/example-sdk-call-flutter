import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zenify_call/zenify_call.dart';
import 'package:call_flutter_example/main.dart' show customDial;

void main() {
  testWidgets('bản tuỳ biến: header trắng, phím nền tối', (t) async {
    late ZenifyPhoneDial d;
    await t.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      d = customDial(c);
      return Scaffold(body: ZenifyPhoneDial(controller: DialController(), theme: d.theme, keyBuilder: d.keyBuilder));
    })));
    final header = t.widget<Text>(find.text('CHỌN ĐẦU SỐ'));
    debugPrint('header color=${header.style?.color}');
    final btn = t.widget<FilledButton>(find.byType(FilledButton).first);
    debugPrint('key bg=${btn.style?.backgroundColor?.resolve({})}');
  });
}
