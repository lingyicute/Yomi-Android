import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:flutter_highlighter/flutter_highlighter.dart';
import 'package:flutter_highlighter/themes/shades-of-purple.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;
import 'package:matrix/matrix.dart';

import 'package:yomi/l10n/l10n.dart';
import 'package:yomi/utils/event_checkbox_extension.dart';
import 'package:yomi/widgets/avatar.dart';
import 'package:yomi/widgets/future_loading_dialog.dart';
import 'package:yomi/widgets/mxc_image.dart';
import '../../../utils/url_launcher.dart';

class HtmlMessage extends StatefulWidget {
  final String html;
  final Room room;
  final Color textColor;
  final double fontSize;
  final TextStyle linkStyle;
  final void Function(LinkableElement) onOpen;
  final String? eventId;
  final Set<Event>? checkboxCheckedEvents;
  final bool limitHeight;
  final TextStyle? textStyle;

  const HtmlMessage({
    super.key,
    required this.html,
    required this.room,
    required this.fontSize,
    required this.linkStyle,
    this.textColor = Colors.black,
    required this.onOpen,
    this.eventId,
    this.checkboxCheckedEvents,
    this.limitHeight = true,
    this.textStyle,
  });

  @override
  State<HtmlMessage> createState() => _HtmlMessageState();
}

class _HtmlMessageState extends State<HtmlMessage> {
  /// The rendered [InlineSpan] tree for the current inputs.
  ///
  /// Rendering HTML into spans is expensive: it walks the DOM, runs the
  /// linkify regex over every text node and constructs widgets for pills,
  /// images, code blocks etc. The *timeline* rebuilds every visible message
  /// on every event update, so doing this per build made text-heavy chats
  /// stutter badly (~30 messages x 1-3 ms of span construction per update).
  ///
  /// We cache the finished span tree on the State and only re-render when one
  /// of the inputs that the spans embed actually changes. All context-bound
  /// callbacks in the tree reference [context] of this State, so the cache is
  /// automatically discarded (and rebuilt with a fresh context) when the
  /// message is scrolled out of view and back in.
  InlineSpan? _cachedSpan;
  String? _cachedHtml;
  String? _cachedPlainText;
  double? _cachedFontSize;
  Color? _cachedTextColor;
  TextStyle? _cachedLinkStyle;
  String? _cachedCheckboxFingerprint;

  static String _checkboxFingerprint(Set<Event>? events) {
    if (events == null || events.isEmpty) return '';
    // The aggregated-events set is mutated in place by the SDK, so we cannot
    // rely on its identity. The ids change whenever a checkbox reaction is
    // added or redacted.
    final ids = events.map((e) => e.eventId).toList()..sort();
    return ids.join(',');
  }

  void _updateCache(HtmlMessage w) {
    if (_cachedSpan != null &&
        w.html == _cachedHtml &&
        w.fontSize == _cachedFontSize &&
        w.textColor == _cachedTextColor &&
        w.linkStyle == _cachedLinkStyle &&
        _checkboxFingerprint(w.checkboxCheckedEvents) ==
            _cachedCheckboxFingerprint) {
      return;
    }
    final parsed = _parseCached(w.html);
    _cachedSpan = _renderHtml(parsed, context);
    _cachedPlainText = _extractPlainText(parsed);
    _cachedHtml = w.html;
    _cachedFontSize = w.fontSize;
    _cachedTextColor = w.textColor;
    _cachedLinkStyle = w.linkStyle;
    _cachedCheckboxFingerprint = _checkboxFingerprint(w.checkboxCheckedEvents);
  }

  /// LRU cache for parsed HTML documents.
  ///
  /// Parsing HTML is expensive and every text message went through
  /// [parser.parse] on every single build before — a top scrolling hot spot.
  /// Parsed documents are treated as read-only here, so they can be shared.
  static final Map<String, dom.Element> _parsedHtmlCache = {};
  static const int _parsedHtmlCacheMaxSize = 200;

  static dom.Element _parseCached(String html) {
    final cached = _parsedHtmlCache.remove(html);
    if (cached != null) {
      // Move to the end = most recently used.
      _parsedHtmlCache[html] = cached;
      return cached;
    }
    final parsed = parser.parse(html).body ?? dom.Element.html('');
    _parsedHtmlCache[html] = parsed;
    if (_parsedHtmlCache.length > _parsedHtmlCacheMaxSize) {
      _parsedHtmlCache.remove(_parsedHtmlCache.keys.first);
    }
    return parsed;
  }

  /// Text equivalent of the rendered message: mirrors the line breaks that
  /// [_renderWithLineBreaks] inserts around block elements and additionally
  /// keeps the text content that ends up inside [WidgetSpan]s (code blocks,
  /// spoilers, details, ...) which [InlineSpan.toPlainText] would drop.
  ///
  /// Only used to measure whether a message exceeds [collapsedMaxLines], so
  /// small deviations from the actually rendered text are acceptable.
  static String _extractPlainText(dom.Element body) {
    final buffer = StringBuffer();

    void walkNodes(dom.NodeList nodes, {int depth = 1}) {
      // Same protection against pathological nesting as _renderHtml:
      if (depth >= 100) return;
      final onlyElements = nodes.whereType<dom.Element>().toList();
      for (final node in nodes) {
        if (node is! dom.Element) {
          final text = node.text ?? '';
          // Single linebreak nodes between Elements are ignored:
          if (text != '\n') buffer.write(text);
        } else if (allowedHtmlTags.contains(node.localName)) {
          if (node.localName == 'br') {
            buffer.write('\n');
          } else {
            walkNodes(node.nodes, depth: depth + 1);
          }
        }
        // Keep in sync with _renderWithLineBreaks:
        if (node is dom.Element &&
            onlyElements.indexOf(node) < onlyElements.length - 1) {
          if (blockHtmlTags.contains(node.localName)) buffer.write('\n\n');
          if (fullLineHtmlTag.contains(node.localName)) buffer.write('\n');
        }
      }
    }

    walkNodes(body.nodes);
    return buffer.toString();
  }

  /// Keep in sync with: https://spec.matrix.org/latest/client-server-api/#mroommessage-msgtypes
  static const Set<String> allowedHtmlTags = {
    'font',
    'del',
    's',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'blockquote',
    'p',
    'a',
    'ul',
    'ol',
    'sup',
    'sub',
    'li',
    'b',
    'i',
    'u',
    'strong',
    'em',
    'strike',
    'code',
    'hr',
    'br',
    'div',
    'table',
    'thead',
    'tbody',
    'tr',
    'th',
    'td',
    'caption',
    'pre',
    'span',
    'img',
    'details',
    'summary',
    // Not in the allowlist of the matrix spec yet but should be harmless:
    'ruby',
    'rp',
    'rt',
    'html',
    'body',
    // Workaround for https://github.com/lingyicute/yomi-android/issues/507
    'tg-forward',
  };

  /// We add line breaks before these tags:
  static const Set<String> blockHtmlTags = {
    'p',
    'ul',
    'ol',
    'pre',
    'div',
    'table',
    'details',
    'blockquote',
  };

  /// We add line breaks before these tags:
  static const Set<String> fullLineHtmlTag = {
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'li',
  };

  /// Adding line breaks before block elements.
  List<InlineSpan> _renderWithLineBreaks(
    dom.NodeList nodes,
    BuildContext context, {
    int depth = 1,
  }) {
    final onlyElements = nodes.whereType<dom.Element>().toList();
    return [
      for (var i = 0; i < nodes.length; i++) ...[
        // Actually render the node child:
        _renderHtml(nodes[i], context, depth: depth + 1),
        // Add linebreaks between blocks:
        if (nodes[i] is dom.Element &&
            onlyElements.indexOf(nodes[i] as dom.Element) <
                onlyElements.length - 1) ...[
          if (blockHtmlTags.contains((nodes[i] as dom.Element).localName))
            const TextSpan(text: '\n\n'),
          if (fullLineHtmlTag.contains((nodes[i] as dom.Element).localName))
            const TextSpan(text: '\n'),
        ],
      ],
    ];
  }

  /// Transforms a Node to an InlineSpan.
  InlineSpan _renderHtml(
    dom.Node node,
    BuildContext context, {
    int depth = 1,
  }) {
    // We must not render elements nested more than 100 elements deep:
    if (depth >= 100) return const TextSpan();

    // This is a text node, so we render it as text:
    if (node is! dom.Element) {
      var text = node.text ?? '';
      // Single linebreak nodes between Elements are ignored:
      if (text == '\n') text = '';

      return LinkifySpan(
        text: text,
        options: const LinkifyOptions(humanize: false),
        linkStyle: widget.linkStyle,
        onOpen: widget.onOpen,
      );
    }

    // We must not render tags which are not in the allow list:
    if (!allowedHtmlTags.contains(node.localName)) return const TextSpan();

    switch (node.localName) {
      case 'br':
        return const TextSpan(text: '\n');
      case 'a':
        final href = node.attributes['href'];
        if (href == null) continue block;
        final matrixId = node.attributes['href']
            ?.parseIdentifierIntoParts()
            ?.primaryIdentifier;
        if (matrixId != null) {
          if (matrixId.sigil == '@') {
            final user = widget.room.unsafeGetUserFromMemoryOrFallback(matrixId);
            return WidgetSpan(
              child: MatrixPill(
                key: Key('user_pill_$matrixId'),
                name: user.calcDisplayname(),
                avatar: user.avatarUrl,
                uri: href,
                outerContext: context,
                fontSize: widget.fontSize,
                color: widget.linkStyle.color,
              ),
            );
          }
          if (matrixId.sigil == '#' || matrixId.sigil == '!') {
            final room = matrixId.sigil == '!'
                ? widget.room.client.getRoomById(matrixId)
                : widget.room.client.getRoomByAlias(matrixId);
            return WidgetSpan(
              child: MatrixPill(
                name: room?.getLocalizedDisplayname() ?? matrixId,
                avatar: room?.avatar,
                uri: href,
                outerContext: context,
                fontSize: widget.fontSize,
                color: widget.linkStyle.color,
              ),
            );
          }
        }
        return WidgetSpan(
          child: Tooltip(
            message: href,
            child: InkWell(
              splashColor: Colors.transparent,
              onTap: () => UrlLauncher(context, href, node.text).launchUrl(),
              child: Text.rich(
                TextSpan(
                  children: _renderWithLineBreaks(
                    node.nodes,
                    context,
                    depth: depth,
                  ),
                  style: widget.linkStyle,
                ),
                style: const TextStyle(height: 1.25),
              ),
            ),
          ),
        );
      case 'li':
        if (!{'ol', 'ul'}.contains(node.parent?.localName)) {
          continue block;
        }
        final eventId = widget.eventId;

        final isCheckbox = node.className == 'task-list-item';
        final checkboxIndex = isCheckbox
            ? node.rootElement
                    .getElementsByClassName('task-list-item')
                    .indexOf(node) +
                1
            : null;
        final checkedByReaction = !isCheckbox
            ? null
            : widget.checkboxCheckedEvents?.firstWhereOrNull(
                (event) => event.checkedCheckboxId == checkboxIndex,
              );
        final staticallyChecked = !isCheckbox
            ? false
            : node.children.first.attributes['checked'] == 'true';

        return WidgetSpan(
          child: Padding(
            padding: EdgeInsets.only(left: widget.fontSize),
            child: Text.rich(
              TextSpan(
                children: [
                  if (node.parent?.localName == 'ul')
                    const TextSpan(text: '• '),
                  if (node.parent?.localName == 'ol')
                    TextSpan(
                      text:
                          '${(node.parent?.nodes.whereType<dom.Element>().toList().indexOf(node) ?? 0) + (int.tryParse(node.parent?.attributes['start'] ?? '1') ?? 1)}. ',
                    ),
                  if (node.className == 'task-list-item')
                    WidgetSpan(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: SizedBox.square(
                          dimension: widget.fontSize,
                          child: Checkbox.adaptive(
                            checkColor: widget.textColor,
                            side: BorderSide(color: widget.textColor),
                            activeColor: widget.textColor.withAlpha(64),
                            visualDensity: VisualDensity.compact,
                            value:
                                staticallyChecked || checkedByReaction != null,
                            onChanged: eventId == null ||
                                    checkboxIndex == null ||
                                    staticallyChecked ||
                                    !widget.room.canSendDefaultMessages ||
                                    (checkedByReaction != null &&
                                        checkedByReaction.senderId !=
                                            widget.room.client.userID)
                                ? null
                                : (_) => showFutureLoadingDialog(
                                      context: context,
                                      future: () => checkedByReaction != null
                                          ? widget.room.redactEvent(
                                              checkedByReaction.eventId,
                                            )
                                          : widget.room.checkCheckbox(
                                              eventId,
                                              checkboxIndex,
                                            ),
                                    ),
                          ),
                        ),
                      ),
                    ),
                  ..._renderWithLineBreaks(
                    node.nodes,
                    context,
                    depth: depth,
                  ),
                ],
                style: TextStyle(fontSize: widget.fontSize, color: widget.textColor),
              ),
            ),
          ),
        );
      case 'blockquote':
        return WidgetSpan(
          child: Container(
            padding: const EdgeInsets.only(left: 8.0),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: widget.textColor,
                  width: 5,
                ),
              ),
            ),
            child: Text.rich(
              TextSpan(
                children: _renderWithLineBreaks(
                  node.nodes,
                  context,
                  depth: depth,
                ),
              ),
              style: TextStyle(
                fontStyle: FontStyle.italic,
                fontSize: widget.fontSize,
                color: widget.textColor,
              ),
            ),
          ),
        );
      case 'code':
        final isInline = node.parent?.localName != 'pre';
        return WidgetSpan(
          child: Material(
            clipBehavior: Clip.hardEdge,
            borderRadius: BorderRadius.circular(4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: HighlightView(
                node.text,
                language: node.className
                        .split(' ')
                        .singleWhereOrNull(
                          (className) => className.startsWith('language-'),
                        )
                        ?.split('language-')
                        .last ??
                    'md',
                theme: shadesOfPurpleTheme,
                padding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: isInline ? 0 : 8,
                ),
                textStyle: TextStyle(
                  fontSize: widget.fontSize,
                  fontFamily: 'RobotoMono',
                ),
              ),
            ),
          ),
        );
      case 'img':
        final mxcUrl = Uri.tryParse(node.attributes['src'] ?? '');
        if (mxcUrl == null || mxcUrl.scheme != 'mxc') {
          return TextSpan(text: node.attributes['alt']);
        }

        final width = double.tryParse(node.attributes['width'] ?? '');
        final height = double.tryParse(node.attributes['height'] ?? '');
        const defaultDimension = 64.0;
        final actualWidth = width ?? height ?? defaultDimension;
        final actualHeight = height ?? width ?? defaultDimension;

        return WidgetSpan(
          child: SizedBox(
            width: actualWidth,
            height: actualHeight,
            child: MxcImage(
              uri: mxcUrl,
              width: actualWidth,
              height: actualHeight,
              isThumbnail: (actualWidth * actualHeight) > (256 * 256),
            ),
          ),
        );
      case 'hr':
        return const WidgetSpan(child: Divider());
      case 'details':
        var obscure = true;
        return WidgetSpan(
          child: StatefulBuilder(
            builder: (context, setState) => InkWell(
              splashColor: Colors.transparent,
              onTap: () => setState(() {
                obscure = !obscure;
              }),
              child: Text.rich(
                TextSpan(
                  children: [
                    WidgetSpan(
                      child: Icon(
                        obscure ? Icons.arrow_right : Icons.arrow_drop_down,
                        size: widget.fontSize * 1.2,
                        color: widget.textColor,
                      ),
                    ),
                    if (obscure)
                      ...node.nodes
                          .where(
                            (node) =>
                                node is dom.Element &&
                                node.localName == 'summary',
                          )
                          .map(
                            (node) => _renderHtml(node, context, depth: depth),
                          )
                    else
                      ..._renderWithLineBreaks(
                        node.nodes,
                        context,
                        depth: depth,
                      ),
                  ],
                ),
                style: TextStyle(
                  fontSize: widget.fontSize,
                  color: widget.textColor,
                ),
              ),
            ),
          ),
        );
      case 'span':
        if (!node.attributes.containsKey('data-mx-spoiler')) {
          continue block;
        }
        var obscure = true;
        return WidgetSpan(
          child: StatefulBuilder(
            builder: (context, setState) => InkWell(
              splashColor: Colors.transparent,
              onTap: () => setState(() {
                obscure = !obscure;
              }),
              child: Text.rich(
                TextSpan(
                  children: _renderWithLineBreaks(
                    node.nodes,
                    context,
                    depth: depth,
                  ),
                ),
                style: TextStyle(
                  fontSize: widget.fontSize,
                  color: widget.textColor,
                  backgroundColor: obscure ? widget.textColor : null,
                ),
              ),
            ),
          ),
        );
      block:
      default:
        return TextSpan(
          style: switch (node.localName) {
            'body' => TextStyle(
                fontSize: widget.fontSize,
                color: widget.textColor,
              ),
            'a' => widget.linkStyle,
            'strong' => const TextStyle(fontWeight: FontWeight.bold),
            'em' || 'i' => const TextStyle(fontStyle: FontStyle.italic),
            'del' ||
            's' ||
            'strikethrough' =>
              const TextStyle(decoration: TextDecoration.lineThrough),
            'u' => const TextStyle(decoration: TextDecoration.underline),
            'h1' => TextStyle(fontSize: widget.fontSize * 1.6, height: 2),
            'h2' => TextStyle(fontSize: widget.fontSize * 1.5, height: 2),
            'h3' => TextStyle(fontSize: widget.fontSize * 1.4, height: 2),
            'h4' => TextStyle(fontSize: widget.fontSize * 1.3, height: 1.75),
            'h5' => TextStyle(fontSize: widget.fontSize * 1.2, height: 1.75),
            'h6' => TextStyle(fontSize: widget.fontSize * 1.1, height: 1.5),
            'span' => TextStyle(
                color: node.attributes['color']?.hexToColor ??
                    node.attributes['data-mx-color']?.hexToColor ??
                    widget.textColor,
                backgroundColor:
                    node.attributes['data-mx-bg-color']?.hexToColor,
              ),
            'sup' =>
              const TextStyle(fontFeatures: [FontFeature.superscripts()]),
            'sub' => const TextStyle(fontFeatures: [FontFeature.subscripts()]),
            _ => null,
          },
          children: _renderWithLineBreaks(
            node.nodes,
            context,
            depth: depth,
          ),
        );
    }
  }

  /// A message longer than this many lines is collapsed in the timeline and
  /// flagged with a "message too long, long-press to view" marker.
  static const int collapsedMaxLines = 10;

  /// Whether the message needs more than [collapsedMaxLines] lines at the
  /// given [maxWidth].
  ///
  /// Runs on the cheap plain-text reconstruction from [_extractPlainText]
  /// instead of the real span tree so it cannot throw on the [WidgetSpan]s
  /// (pills, code blocks, ...) which `TextPainter` cannot lay out without
  /// pre-computed placeholder dimensions.
  bool _exceedsCollapsedHeight(
    BuildContext context,
    double maxWidth,
    TextStyle textStyle,
  ) {
    final plainText = _cachedPlainText!;
    // Every '\n' forces a line break, so more hard line breaks than the limit
    // guarantee an overflow without any measuring:
    final forcedLines = '\n'.allMatches(plainText).length + 1;
    if (forcedLines > collapsedMaxLines) return true;
    // Cheap bail-out for the (vast majority of) short messages: even if every
    // glyph occupied a full em square (worst case, e.g. CJK glyphs), the text
    // could still not fill the remaining lines. Avoids running a whole second
    // text layout for every rendered message. The system text scale enlarges
    // the rendered glyphs, so it has to be part of this pessimistic estimate.
    final textScaler = MediaQuery.textScalerOf(context);
    final fontSize = textScaler.scale(textStyle.fontSize ?? widget.fontSize);
    if (forcedLines + (plainText.length * fontSize) / maxWidth <=
        collapsedMaxLines) {
      return false;
    }
    final textPainter = TextPainter(
      text: TextSpan(text: plainText, style: textStyle),
      textDirection: Directionality.of(context),
      textScaler: textScaler,
      maxLines: collapsedMaxLines,
    )..layout(maxWidth: maxWidth);
    final exceeded = textPainter.didExceedMaxLines;
    textPainter.dispose();
    return exceeded;
  }

  @override
  Widget build(BuildContext context) {
    _updateCache(widget);
    final textStyle = widget.textStyle ??
        TextStyle(
          fontSize: widget.fontSize,
          color: widget.textColor,
        );
    final textWidget = Text.rich(
      _cachedSpan!,
      style: textStyle,
      maxLines: widget.limitHeight ? collapsedMaxLines : null,
      // Hard-cut with an ellipsis rather than TextOverflow.fade: the fade is
      // drawn as a modulated gradient layer which renders as an opaque black
      // gradient covering the last visible line as soon as the span tree
      // contains WidgetSpans (pills, code blocks, quotes, ...).
      // See https://github.com/flutter/flutter/issues/128107
      overflow: TextOverflow.ellipsis,
    );
    if (!widget.limitHeight) return textWidget;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (!_exceedsCollapsedHeight(
          context,
          constraints.maxWidth,
          textStyle,
        )) {
          return textWidget;
        }
        // Same subtle style as the "message was edited" marker, see
        // message.dart:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            textWidget,
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 4.0,
              children: [
                Icon(
                  Icons.unfold_more,
                  size: 14,
                  color: widget.textColor.withAlpha(164),
                ),
                Text(
                  L10n.of(context).messageTooLongLongPressToView,
                  style: TextStyle(
                    fontSize: 11,
                    color: widget.textColor.withAlpha(164),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class MatrixPill extends StatelessWidget {
  final String name;
  final BuildContext outerContext;
  final Uri? avatar;
  final String uri;
  final double? fontSize;
  final Color? color;

  const MatrixPill({
    super.key,
    required this.name,
    required this.outerContext,
    this.avatar,
    required this.uri,
    required this.fontSize,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      splashColor: Colors.transparent,
      onTap: UrlLauncher(outerContext, uri).launchUrl,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Avatar(
            mxContent: avatar,
            name: name,
            size: 16,
          ),
          const SizedBox(width: 6),
          Text(
            name,
            style: TextStyle(
              color: color,
              decorationColor: color,
              decoration: TextDecoration.underline,
              fontSize: fontSize,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}

extension on String {
  Color? get hexToColor {
    var hexCode = this;
    if (hexCode.startsWith('#')) hexCode = hexCode.substring(1);
    if (hexCode.length == 6) hexCode = 'FF$hexCode';
    final colorValue = int.tryParse(hexCode, radix: 16);
    return colorValue == null ? null : Color(colorValue);
  }
}

extension on dom.Element {
  dom.Element get rootElement => parent?.rootElement ?? this;
}
