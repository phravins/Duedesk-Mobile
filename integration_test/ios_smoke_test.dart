import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:duedesk/app/bootstrap.dart';

Future<void> waitFor(
  WidgetTester tester,
  Finder finder, {
  bool scroll = false,
}) async {
  for (var i = 0; i < 120; i++) {
    await tester.pump(const Duration(milliseconds: 250));
    if (finder.hitTestable().evaluate().isNotEmpty) return;
    if (scroll && i > 10 && find.byType(Scrollable).evaluate().isNotEmpty) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -160));
    }
  }
  expect(finder.hitTestable(), findsWidgets);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('iPhone native storage, PDF rendering and demo navigation', (
    tester,
  ) async {
    // Run on a dedicated test simulator; leave real account credentials alone.
    const storage = FlutterSecureStorage();
    const key = 'duedesk.integration.keychain';
    try {
      await storage.write(key: key, value: 'native-round-trip');
      expect(await storage.read(key: key), 'native-round-trip');
    } finally {
      await storage.delete(key: key);
    }

    await pdfrxFlutterInitialize();
    final asset = await rootBundle.load('assets/demo/evidence.pdf');
    final document = await PdfDocument.openData(asset.buffer.asUint8List());
    try {
      expect(document.pages, isNotEmpty);
      final image = await document.pages.first.render(width: 120, height: 160);
      expect(image, isNotNull);
      image?.dispose();
    } finally {
      await document.dispose();
    }

    final preferences = await SharedPreferences.getInstance();
    await preferences.remove('demoUser');
    await preferences.setBool('onboarding', true);
    // Nobody is there to answer the notification permission alert, which
    // would leave the app inactive behind its privacy cover.
    await preferences.setBool('notificationPermissionAsked', true);
    await bootstrap();
    final demo = find.text('Continue in demo mode');
    await waitFor(tester, demo, scroll: true);
    await tester.tap(demo);
    await waitFor(tester, find.text('Due overview'));
    expect(preferences.getString('demoUser'), 'management');

    await tester.tap(find.text('Due', skipOffstage: true));
    await waitFor(tester, find.text('Due Items'));
    // Let the tab transition finish so the outgoing page's cards are gone.
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Pin obligation').hitTestable().first);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Unpin obligation'), findsWidgets);

    await tester.tap(find.text('Calendar', skipOffstage: true));
    await waitFor(tester, find.text('Month'));
    await tester.tap(find.text('Docs', skipOffstage: true));
    await waitFor(tester, find.text('Documents'));
    await tester.tap(find.text('More', skipOffstage: true));
    await waitFor(tester, find.text('Your workspace'));
    expect(tester.takeException(), isNull);
  });
}
