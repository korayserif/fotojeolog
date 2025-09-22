// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fotojeolog/main.dart';

void main() {
  testWidgets('Uygulama açılış smoke test', (WidgetTester tester) async {
    // Uygulamayı başlat
    await tester.pumpWidget(const MyApp());

    // Ana ekranda beklenen başlık ve butonların göründüğünü doğrula
    expect(find.textContaining('Jeoloji'), findsWidgets);
    expect(find.text('SAHA FOTOĞRAFI ÇEK'), findsOneWidget);
    expect(find.text('SAHA ARŞİVİNDEN SEÇ'), findsOneWidget);

    // Ayarlar ikonunun varlığını kontrol et
    expect(find.byIcon(Icons.settings), findsOneWidget);
  });
}
