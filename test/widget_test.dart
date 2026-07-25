import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskmaster_pro/core/localization/app_localizations.dart';

void main() {
  testWidgets('Arabic localization uses RTL presentation', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Builder(
          builder: (context) => Scaffold(
            body: Text(
              AppLocalizations.of(context).text('dashboard'),
              textDirection: Directionality.of(context),
            ),
          ),
        ),
      ),
    );

    expect(find.text('لوحة التحكم'), findsOneWidget);
    final text = tester.widget<Text>(find.text('لوحة التحكم'));
    expect(text.textDirection, TextDirection.rtl);
  });
}
