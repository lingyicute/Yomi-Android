import 'package:flutter/material.dart';

import 'package:yomi/utils/error_reporter.dart';

class YomiErrorWidget extends StatefulWidget {
  final FlutterErrorDetails details;
  const YomiErrorWidget(this.details, {super.key});

  @override
  State<YomiErrorWidget> createState() => _YomiErrorWidgetState();
}

class _YomiErrorWidgetState extends State<YomiErrorWidget> {
  static final Set<String> knownExceptions = {};
  @override
  void initState() {
    super.initState();

    if (knownExceptions.contains(widget.details.exception.toString())) {
      return;
    }
    knownExceptions.add(widget.details.exception.toString());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ErrorReporter(context, 'Error Widget').onErrorCallback(
        widget.details.exception,
        widget.details.stack,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.orange,
      child: Placeholder(
        child: Center(
          child: Material(
            color: Colors.white.withAlpha(230),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }
}
