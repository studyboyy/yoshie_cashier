import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_cashier/main.dart';

void main() {
  testWidgets('renders Yosy Group login screen', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const YosyCashierApp());
    await tester.pumpAndSettle();

    expect(find.text('Yosy Group'), findsOneWidget);
    expect(find.text('Masuk'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));
  });
}
