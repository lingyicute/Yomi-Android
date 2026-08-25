import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:matrix/matrix.dart';

import 'package:yomi/pages/chat/events/html_message.dart';

/// Micro benchmark demonstrating the impact of the HtmlMessage span-tree
/// cache: message bubbles used to re-parse the HTML + re-run linkify +
/// re-construct the whole InlineSpan tree on every rebuild of the timeline.
///
/// The harness mirrors the real timeline: a stable parent rebuilds only the
/// message bubble (as `updateView` does on every event update).
///
/// Run with: flutter test test/html_message_perf_test.dart
void main() {
  testWidgets('HtmlMessage: cached rebuild is much cheaper than re-render', (
    tester,
  ) async {
    final client = Client('bench');
    final room = Room(id: '!bench:example.org', client: client);

    // A representative formatted text message: bold/italic tags, one
    // matrix-esque <a> link and one raw URL that LinkifySpan has to find.
    const html =
        'Hello <b>world</b>! Check <a href="https://example.com">this link</a>'
        ' and https://example.org/path and some <i>more</i> text here.';

    final ticker = ValueNotifier<int>(0);
    addTearDown(ticker.dispose);

    Widget host({bool forceReRender = false, bool freshState = false}) {
      return MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<int>(
            valueListenable: ticker,
            builder: (context, i, _) => HtmlMessage(
              key: freshState ? ValueKey('s_$i') : null,
              html: html,
              room: room,
              // Alternating the font size invalidates the cache signature:
              // this is what every rebuild used to do anyway (full re-render).
              fontSize: forceReRender ? 13.0 + (i % 2) : 14,
              linkStyle: const TextStyle(color: Colors.blue),
              onOpen: (_) {},
              eventId: r'$bench',
            ),
          ),
        ),
      );
    }

    const iterations = 60;

    // Warm up parser/span caches.
    await tester.pumpWidget(host());

    Future<void> pumpN() async {
      for (var i = 0; i < iterations; i++) {
        ticker.value++;
        await tester.pump();
      }
    }

    // (1) Warm path: same element, same signature every pump. The cached
    // InlineSpan tree is reused; identical widget instances short-circuit
    // the subtree rebuild.
    final warm = Stopwatch()..start();
    await pumpN();
    warm.stop();

    // (2) Cache-miss path: the signature alternates, so the span tree is
    // re-rendered from the DOM on every pump — what used to happen on every
    // single timeline rebuild.
    final reRender = Stopwatch()..start();
    ticker.value++;
    await tester.pumpWidget(host(forceReRender: true));
    await pumpN();
    reRender.stop();

    // (3) Fresh State per pump (message scrolled away and back in).
    final cold = Stopwatch()..start();
    ticker.value++;
    await tester.pumpWidget(host(freshState: true));
    await pumpN();
    cold.stop();

    final warmUs = warm.elapsedMicroseconds / iterations;
    final reRenderUs = reRender.elapsedMicroseconds / iterations;
    final coldUs = cold.elapsedMicroseconds / iterations;
    // ignore: avoid_print
    print(
      'HtmlMessage bubble rebuild per pump: '
      'warm=${warmUs.toStringAsFixed(1)}us '
      'cacheMiss=${reRenderUs.toStringAsFixed(1)}us '
      'freshState=${coldUs.toStringAsFixed(1)}us',
    );

    // The cache must make steady-state rebuilds clearly cheaper than a
    // full re-render, otherwise it would not even pay for itself.
    expect(warmUs, lessThan(reRenderUs * 0.7));
    expect(warmUs, lessThan(coldUs * 0.7));
  });
}
