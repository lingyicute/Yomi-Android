import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yomi/config/themes.dart';

void main() {
  testWidgets('LyiThemes pins the pre-3.38 page transitions', (
    WidgetTester tester,
  ) async {
    late ThemeData built;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            built = LyiThemes.buildTheme(context, Brightness.light);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(
      built.platform,
      TargetPlatform.android,
      reason: 'the linux host test framework resolves to android',
    );
    expect(
      built.pageTransitionsTheme.builders[TargetPlatform.android],
      isA<ZoomPageTransitionsBuilder>(),
      reason: 'Flutter >= 3.38 would default to PredictiveBack/FadeForwards',
    );
    expect(
      const PageTransitionsTheme().builders[TargetPlatform.android],
      isNot(isA<ZoomPageTransitionsBuilder>()),
      reason: 'sanity check: the framework default is no longer zoom',
    );
    expect(
      built.pageTransitionsTheme.builders[TargetPlatform.iOS],
      isA<CupertinoPageTransitionsBuilder>(),
    );
    expect(
      built.pageTransitionsTheme.builders[TargetPlatform.linux],
      isA<FadeUpwardsPageTransitionsBuilder>(),
    );
    // ThemeData must actually hand the theme to a route.
    expect(built.pageTransitionsTheme, same(LyiThemes.pageTransitionsTheme));
  });
}
