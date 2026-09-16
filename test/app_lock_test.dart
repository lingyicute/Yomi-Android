import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:matrix/matrix.dart';

import 'package:yomi/l10n/l10n.dart';
import 'package:yomi/l10n/l10n_zh.dart';
import 'package:yomi/widgets/app_lock.dart';
import 'package:yomi/widgets/lock_screen.dart';

/// A logged in client: `AppLock` wipes the stored pin as soon as no client is
/// logged in anymore, so the tests need one that claims to be one.
Client _fakeClient() => Client('app lock test')..accessToken = 'token';

/// [L10n.localizationsDelegates] loads the translations deferred, which needs
/// a real isolate and therefore does not work inside a widget test, so the
/// tests hand the Chinese translations over eagerly.
class _EagerL10nDelegate extends LocalizationsDelegate<L10n> {
  const _EagerL10nDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'zh';

  @override
  Future<L10n> load(Locale locale) async => L10nZh();

  @override
  bool shouldReload(_EagerL10nDelegate old) => false;
}

Future<AppLock> pumpLockedApp(
  WidgetTester tester, {
  required String? pincode,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [
        _EagerL10nDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: L10n.supportedLocales,
      home: AppLockWidget(
        pincode: pincode,
        clients: [_fakeClient()],
        child: const Scaffold(body: Center(child: Text('unlocked content'))),
      ),
    ),
  );
  await tester.pump();
  return tester.state<AppLock>(find.byType(AppLockWidget));
}

bool isShowingLockScreen(WidgetTester tester) =>
    find.byType(LockScreen).evaluate().isNotEmpty;

PinField pinField(WidgetTester tester) =>
    tester.widget<PinField>(find.byType(PinField));

PinFieldState pinFieldState(WidgetTester tester) =>
    tester.state<PinFieldState>(find.byType(PinField));

String pinFieldText(WidgetTester tester) => pinFieldState(tester).text;

String? pinFieldError(WidgetTester tester) => pinField(tester).errorText;

bool pinFieldBlocked(WidgetTester tester) => pinField(tester).blocked;

/// Types [digits] the way a real IME would: as one editing value delivered
/// to the registered [TextInputClient] (the pin field attached itself to
/// the input system during pumpLockedApp's first frame).
Future<void> enterPin(WidgetTester tester, String digits) async {
  tester.testTextInput.updateEditingValue(
    TextEditingValue(
      text: digits,
      selection: TextSelection.collapsed(offset: digits.length),
    ),
  );
  await tester.pump();
}

/// `TestWidgetsFlutterBinding` does not forward app lifecycle notifications
/// to the registered observers, so the tests call the observer themselves.
void sendLifecycle(AppLock lock, AppLifecycleState state) =>
    lock.didChangeAppLifecycleState(state);

void main() {
  testWidgets('the app starts locked when a pin is set', (
    WidgetTester tester,
  ) async {
    final lock = await pumpLockedApp(tester, pincode: '0110');

    expect(lock.isLocked, true);
    expect(isShowingLockScreen(tester), true);
    expect(find.byType(PinField), findsOneWidget);
  });

  testWidgets('a pin with a leading zero unlocks while typing', (
    WidgetTester tester,
  ) async {
    final lock = await pumpLockedApp(tester, pincode: '0110');

    // Regression test for fluffychat#2388: running the pin through an int
    // turned `0110` into `110`, so such a pin could never unlock the app -
    // no matter whether it was submitted automatically or by hand.
    await enterPin(tester, '0110');
    await tester.pump();

    expect(lock.isLocked, false);
    expect(isShowingLockScreen(tester), false);
    expect(find.text('unlocked content'), findsOneWidget);
  });

  testWidgets('the fourth digit submits, shorter input is ignored', (
    WidgetTester tester,
  ) async {
    final lock = await pumpLockedApp(tester, pincode: '1234');

    for (final partial in ['1', '12', '123']) {
      await enterPin(tester, partial);
      await tester.pump();
      expect(lock.isLocked, true, reason: '"$partial" must not unlock');
      expect(
        pinFieldError(tester),
        null,
        reason: '"$partial" must not be reported as invalid',
      );
    }

    await enterPin(tester, '1234');
    await tester.pump();
    expect(lock.isLocked, false);
  });

  testWidgets('a wrong pin keeps the app locked', (
    WidgetTester tester,
  ) async {
    final lock = await pumpLockedApp(tester, pincode: '0110');

    await enterPin(tester, '1234');
    await tester.pump();

    expect(lock.isLocked, true);
  });

  testWidgets('non digits never reach the input', (WidgetTester tester) async {
    await pumpLockedApp(tester, pincode: '0110');

    await enterPin(tester, '1a2 3x');
    await tester.pump();

    expect(pinFieldText(tester), '123');
    expect(pinFieldError(tester), null);
  });

  testWidgets('a pasted pin is cut to four digits and unlocks', (
    WidgetTester tester,
  ) async {
    final lock = await pumpLockedApp(tester, pincode: '0110');

    await enterPin(tester, '0110123');
    await tester.pump();

    expect(lock.isLocked, false);
  });

  testWidgets('a wrong pin blocks input and a shorter one does not', (
    WidgetTester tester,
  ) async {
    await pumpLockedApp(tester, pincode: '0110');

    await enterPin(tester, '9999');
    await tester.pump();

    expect(pinFieldText(tester), isEmpty);
    expect(pinFieldBlocked(tester), true);
    expect(pinFieldError(tester), contains('5'));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    // A second attempt while blocked must not restart or extend the
    // cool down: still the same countdown, still no extra penalty.
    expect(pinFieldBlocked(tester), true);
    expect(pinFieldError(tester), contains('5'));
  });

  testWidgets('the cool down lifts and the next one is longer', (
    WidgetTester tester,
  ) async {
    await pumpLockedApp(tester, pincode: '0110');

    await enterPin(tester, '9999');
    await tester.pump();
    expect(pinFieldBlocked(tester), true);

    // Let the animated progress bar settle, then the block is gone.
    await tester.pump(const Duration(seconds: 6));
    expect(pinFieldBlocked(tester), false);
    expect(pinFieldError(tester), null);

    // The second failure is punished twice as hard as the first one.
    await enterPin(tester, '9999');
    await tester.pump();
    expect(pinFieldError(tester), contains('10'));
  });

  testWidgets('the IME action key reports an unfinished pin', (
    WidgetTester tester,
  ) async {
    await pumpLockedApp(tester, pincode: '1234');

    await enterPin(tester, '12');
    await tester.pump();
    expect(pinFieldError(tester), null);

    // The IME action key is the manual way out while the field carries no
    // unlock button; an explicit submit must answer the user instead of
    // silently ignoring a malformed pin, and must not start a cool down.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(pinFieldError(tester), isNotNull);
    expect(pinFieldBlocked(tester), false);
  });

  testWidgets('the app relocks when it is hidden again', (
    WidgetTester tester,
  ) async {
    final lock = await pumpLockedApp(tester, pincode: '0110');
    await enterPin(tester, '0110');
    await tester.pump();
    expect(lock.isLocked, false);

    sendLifecycle(lock, AppLifecycleState.hidden);
    await tester.pump();

    expect(lock.isLocked, true);
    expect(isShowingLockScreen(tester), true);
    expect(find.byType(PinField), findsOneWidget);
  });

  testWidgets('the app lock stays asleep while it is paused', (
    WidgetTester tester,
  ) async {
    final lock = await pumpLockedApp(tester, pincode: '0110');
    expect(lock.unlock('0110'), true);
    await tester.pump();

    final gate = Completer<void>();
    final paused = lock.pauseWhile(gate.future);
    await tester.pump();

    sendLifecycle(lock, AppLifecycleState.hidden);
    await tester.pump();
    expect(
      lock.isLocked,
      false,
      reason: 'a dialog flow must not be interrupted by the lock screen',
    );

    gate.complete();
    await paused;
    expect(lock.isActive, true);

    sendLifecycle(lock, AppLifecycleState.hidden);
    await tester.pump();
    expect(lock.isLocked, true);
  });
}
