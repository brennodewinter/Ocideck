import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/app.dart';

void main() {
  testWidgets('Welcome screen shows startup logo', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: OciDeckApp()));
    expect(
      find.bySemanticsLabel('De Winter Information Solutions'),
      findsOneWidget,
    );
  });

  testWidgets('Welcome screen exposes settings', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: OciDeckApp()));
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
  });
}
