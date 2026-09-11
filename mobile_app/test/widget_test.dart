import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/presentation/widgets/app_error_view.dart';

// The full app needs Firebase, so this smoke test covers the shared error view.
void main() {
  testWidgets('AppErrorView classifies network errors and retries', (tester) async {
    var retried = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AppErrorView(
          error: Exception('Connection timed out'),
          onRetry: () => retried = true,
        ),
      ),
    ));

    expect(find.text('Connection Error'), findsOneWidget);
    expect(find.text('Connection timed out'), findsOneWidget);

    await tester.tap(find.text('Try Again'));
    expect(retried, isTrue);
  });
}
