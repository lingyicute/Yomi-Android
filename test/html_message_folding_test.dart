import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:yomi/l10n/l10n.dart';
import 'package:yomi/pages/chat/events/html_message.dart';

/// Folding of long messages in the timeline:
///
/// * a message that needs more than [HtmlMessage.collapsedMaxLines] lines is
///   cut off at that limit and flagged with the "message too long" marker,
/// * `limitHeight: false` - the state a message is in while it is selected
///   (long pressed) - shows the message in full,
/// * and folding it back never mangles the message.
void main() {
  final longMessage = List.generate(200, (i) => 'word$i').join(' ');

  testWidgets('long messages fold, the marker shows and selecting unfolds', (
    tester,
  ) async {
    final client = Client('testclient');
    final room = Room(id: '!room:example.org', client: client);

    var limitHeight = true;
    var message = longMessage;
    StateSetter? setState;

    final app = MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: Align(
            alignment: Alignment.topLeft,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 291),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StatefulBuilder(
                    builder: (context, innerSetState) {
                      setState = innerSetState;
                      // The chat shows its messages inside a SelectionArea:
                      // Flutter then wraps the message Text in a MouseRegion,
                      // which is a trap for anything that assumes the text's
                      // first render object is its paragraph.
                      return SelectionArea(
                        child: HtmlMessage(
                          html: message,
                          room: room,
                          fontSize: 14,
                          linkStyle: const TextStyle(color: Colors.blue),
                          onOpen: (_) {},
                          eventId: r'$folding',
                          limitHeight: limitHeight,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    // The localized strings live in a deferred library, which is only loaded
    // for real (not by the fake clock of the widget tester) - without this the
    // localized HtmlMessage never gets built:
    await tester.runAsync(() async {
      await tester.pumpWidget(app);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });

    /// Height of the message paragraph itself:
    double messageHeight() => tester
        .renderObjectList<RenderParagraph>(find.byType(RichText))
        .map((p) => p.size.height)
        .reduce((a, b) => a > b ? a : b);

    bool hasMarker() => find.byIcon(Icons.unfold_more).evaluate().isNotEmpty;

    Future<void> pump() async {
      for (var i = 0; i < 3; i++) {
        await tester.pump();
      }
    }

    await pump();

    expect(setState, isNotNull, reason: 'the message was built');

    // Measure one line of text with a short message:
    message = 'short message';
    setState!(() {});
    await pump();
    final lineHeight = messageHeight();
    expect(hasMarker(), isFalse, reason: 'short messages are not folded');

    // A long message is folded to collapsedMaxLines and marked:
    message = longMessage;
    setState!(() {});
    await pump();
    expect(
      messageHeight(),
      closeTo(HtmlMessage.collapsedMaxLines * lineHeight, lineHeight),
      reason: 'a long message is folded at collapsedMaxLines',
    );
    expect(hasMarker(), isTrue, reason: 'the "too long" marker is shown');

    final foldedHeight = messageHeight();

    // Selecting the message (long press) unfolds it:
    setState!(() => limitHeight = false);
    await pump();
    expect(hasMarker(), isFalse, reason: 'an unfolded message has no marker');
    expect(
      messageHeight(),
      greaterThan(foldedHeight * 2),
      reason: 'the selected message is shown in full, not in one line',
    );

    // ... and folding it back works as well:
    setState!(() => limitHeight = true);
    await pump();
    expect(messageHeight(), foldedHeight);
    expect(hasMarker(), isTrue);
  });

  // The folding has to follow the system font scale: a message that does not
  // fit at 100% may well fit at 50%. The widget is built once and reused, so
  // only the inherited MediaQuery changes - if the folding did not re-check
  // on its own, the marker would stay behind.
  testWidgets('a font scale change re-checks the folding', (tester) async {
    final client = Client('testclient');
    final room = Room(id: '!room:example.org', client: client);
    // ~15 lines at 100% (folded), ~8 lines at 50% (fits):
    final message = List.generate(35, (i) => 'word$i').join(' ');

    var scale = 1.0;
    StateSetter? setState;

    final messageWidget = HtmlMessage(
      html: message,
      room: room,
      fontSize: 14,
      linkStyle: const TextStyle(color: Colors.blue),
      onOpen: (_) {},
      eventId: r'$foldingScale',
      limitHeight: true,
    );

    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: Align(
                alignment: Alignment.topLeft,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 291),
                  child: StatefulBuilder(
                    builder: (context, innerSetState) {
                      setState = innerSetState;
                      return SelectionArea(
                        child: MediaQuery(
                          data: MediaQuery.of(context).copyWith(
                            textScaler: TextScaler.linear(scale),
                          ),
                          child: messageWidget,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });

    Future<void> pump() async {
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
    }

    bool hasMarker() => find.byIcon(Icons.unfold_more).evaluate().isNotEmpty;

    await pump();
    expect(hasMarker(), isTrue, reason: 'folded at 100%');

    setState!(() => scale = 0.5);
    await pump();
    expect(
      hasMarker(),
      isFalse,
      reason: 'at 50% the message fits and must not be marked',
    );

    setState!(() => scale = 1.0);
    await pump();
    expect(hasMarker(), isTrue, reason: 'folded again at 100%');
  });
}
