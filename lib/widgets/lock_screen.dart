import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:yomi/config/themes.dart';
import 'package:yomi/l10n/l10n.dart';
import 'package:yomi/widgets/app_lock.dart';

/// Length of the app lock passcode. [AppLock.isActive] only accepts a four
/// digit pincode, so the lock screen must not accept anything else either.
const int _pinLength = 4;

final RegExp _pinRegExp = RegExp('^\\d{$_pinLength}\$');

class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String? _errorText;
  int _coolDownSeconds = 5;
  int _coolDownRemainingSeconds = 0;
  bool _inputBlocked = false;
  Timer? _coolDownTimer;
  final TextEditingController _textEditingController = TextEditingController();

  // TODO-DIAG(v2): throwaway on-screen diagnostics — delete this block.
  String _diag = 'DIAG-v2 · 尚未收到 onChanged';
  String _ctrlDiag = 'CTRL · 值未变化';
  final List<String> _probeLog = <String>['—— 探针日志（新事件在上）——'];
  late final _InputProbe _probeDelta = _InputProbe(
    label: 'A·delta',
    enableDeltaModel: true,
    log: _probeLogLine,
  );
  late final _InputProbe _probePlain = _InputProbe(
    label: 'B·plain',
    enableDeltaModel: false,
    log: _probeLogLine,
  );

  @override
  void initState() {
    super.initState();
    _textEditingController.addListener(_diagControllerChanged);
  }

  void _diagControllerChanged() {
    final value = _textEditingController.value;
    setState(() {
      _ctrlDiag =
          'CTRL len=${value.text.length} comp=${value.composing} sel=${value.selection}';
    });
  }

  void _probeLogLine(String line) {
    setState(() {
      _probeLog.insert(1, line);
      if (_probeLog.length > 13) _probeLog.removeLast();
    });
  }

  Widget _probeBox(_InputProbe probe, String hint) {
    final obscured = probe.obscuredText;
    return InkWell(
      onTap: () => setState(probe.attach),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.redAccent),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          obscured.isEmpty
              ? '$hint\n点这里→用键盘输PIN'
              : '$hint\n$obscured (len=${probe.textLength})',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12),
        ),
      ),
    );
  }

  /// Compares [text] against the stored pin and unlocks the app.
  ///
  /// The pin is compared as a plain string and is never converted to a
  /// number: `int.tryParse('0110').toString()` is `'110'`, which never
  /// matches the stored pin and made such pins impossible to unlock
  /// (upstream fix for fluffychat#2388).
  ///
  /// Whether a keystroke is already worth submitting is decided by the
  /// caller, exactly like upstream does it, so that an explicit submit -
  /// the return key or the unlock button - always answers the user instead
  /// of silently doing nothing.
  Future<void> tryUnlock(String text) async {
    text = text.trim();

    // TODO-DIAG(v1): throwaway
    if (mounted) {
      setState(
        () => _diag = 'tryUnlock("$text") '
            'blocked=$_inputBlocked regex=${_pinRegExp.hasMatch(text)}',
      );
    }

    // While the cool down runs, the field is read only and the countdown
    // below it is the only feedback worth showing.
    if (_inputBlocked) return;

    if (!_pinRegExp.hasMatch(text)) {
      setState(() => _errorText = L10n.of(context).invalidInput);
      return;
    }

    final unlocked = AppLock.of(context).unlock(text);
    // TODO-DIAG(v1): throwaway
    setState(() => _diag += ' unlock=$unlocked');
    if (unlocked) {
      _textEditingController.clear();
      return;
    }

    setState(() {
      _errorText = L10n.of(context).wrongPinEntered(_coolDownSeconds);
      _textEditingController.clear();
      _inputBlocked = true;
      _coolDownRemainingSeconds = _coolDownSeconds;
    });
    _startCoolDown();
  }

  /// Blocks the input and counts the cool down down one second at a time.
  ///
  /// A timer and not an animation callback owns the state, because the app
  /// has to unlock the field even while it is backgrounded or while the
  /// system asks for reduced motion.
  void _startCoolDown() {
    _coolDownTimer?.cancel();
    _coolDownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      // The countdown can outlive the lock screen on the frame it is
      // removed, so every tick has to re-check mounted before setState.
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (timer.tick >= _coolDownSeconds) {
        timer.cancel();
        _coolDownTimer = null;
        // Doubles the penalty after every finished cool down, like upstream.
        _coolDownSeconds *= 2;
        setState(() {
          _inputBlocked = false;
          _coolDownRemainingSeconds = 0;
          _errorText = null;
        });
        return;
      }
      setState(() {
        _coolDownRemainingSeconds = _coolDownSeconds - timer.tick;
        _errorText =
            L10n.of(context).wrongPinEntered(_coolDownSeconds - timer.tick);
      });
    });
  }

  @override
  void dispose() {
    _coolDownTimer?.cancel();
    // TODO-DIAG(v2): throwaway
    _textEditingController.removeListener(_diagControllerChanged);
    _probeDelta.detach();
    _probePlain.detach();
    _textEditingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const pillRadius = BorderRadius.all(Radius.circular(32));
    // Own ScaffoldMessenger: the lock screen is an overlay above the whole
    // app, so a message must not be delivered to a deactivated Scaffold of
    // the page hidden below it.
    return ScaffoldMessenger(
      child: Scaffold(
        appBar: AppBar(
          title: Text(L10n.of(context).pleaseEnterYourPin),
          centerTitle: true,
        ),
        extendBodyBehindAppBar: true,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: LyiThemes.columnWidth,
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  Center(
                    child: SvgPicture.asset(
                      'assets/logo.svg',
                      width: 256,
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _textEditingController,
                    textInputAction: TextInputAction.done,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    autofocus: true,
                    textAlign: TextAlign.center,
                    readOnly: _inputBlocked,
                    onChanged: (text) {
                      // TODO-DIAG(v1): throwaway
                      setState(
                        () => _diag = 'onChanged("$text") '
                            'len=${text.length} cu=${text.codeUnits}',
                      );
                      // Unlock as soon as the fourth digit is typed; before
                      // that the user is still entering the pin.
                      if (text.trim().length >= _pinLength) tryUnlock(text);
                    },
                    onSubmitted: tryUnlock,
                    style: TextStyle(
                      fontSize: 32,
                      letterSpacing: 14,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(_pinLength),
                    ],
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest,
                      errorText: _errorText,
                      hintText: '✱✱✱✱',
                      hintStyle: TextStyle(
                        fontSize: 28,
                        letterSpacing: 14,
                        color: colorScheme.onSurfaceVariant.withAlpha(100),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 20,
                      ),
                      border: const OutlineInputBorder(
                        borderRadius: pillRadius,
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: const OutlineInputBorder(
                        borderRadius: pillRadius,
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: pillRadius,
                        borderSide: BorderSide(
                          color: colorScheme.primary,
                          width: 2,
                        ),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius: pillRadius,
                        borderSide: BorderSide(
                          color: colorScheme.error,
                          width: 2,
                        ),
                      ),
                      focusedErrorBorder: OutlineInputBorder(
                        borderRadius: pillRadius,
                        borderSide: BorderSide(
                          color: colorScheme.error,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                  // TODO-DIAG(v1): throwaway
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _diag,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.redAccent,
                      ),
                    ),
                  ),
                  if (_inputBlocked)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.hourglass_top_outlined,
                            size: 18,
                            color: colorScheme.error,
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 96,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                minHeight: 4,
                                value: _coolDownRemainingSeconds /
                                    _coolDownSeconds,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '$_coolDownRemainingSeconds',
                            style: TextStyle(
                              color: colorScheme.error,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  // TODO-DIAG(v2): throwaway
                  Text(
                    _ctrlDiag,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: Colors.blue),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: _probeBox(_probeDelta, '探针A delta=开')),
                      const SizedBox(width: 8),
                      Expanded(child: _probeBox(_probePlain, '探针B delta=关')),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 180),
                    width: double.infinity,
                    color: Colors.black.withAlpha(13),
                    padding: const EdgeInsets.all(6),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final line in _probeLog)
                          Text(
                            line,
                            style: const TextStyle(
                              fontSize: 10,
                              fontFamily: 'monospace',
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// TODO-DIAG(v2): throwaway raw input probe — delete with the other blocks.
/// A minimal [TextInputClient] that logs everything the IME actually sends,
/// bypassing [EditableText] entirely, so the probe shows the raw event
/// stream no matter what the framework's text widget does with it.
class _InputProbe with TextInputClient, DeltaTextInputClient {
  _InputProbe({
    required this.label,
    required this.enableDeltaModel,
    required this.log,
  });

  final String label;
  final bool enableDeltaModel;
  final void Function(String line) log;

  TextInputConnection? _connection;
  TextEditingValue _value = TextEditingValue.empty;

  String get obscuredText => '•' * _value.text.length;
  int get textLength => _value.text.length;

  void attach() {
    if (_connection?.attached ?? false) {
      _connection!.show();
      log('[$label] show() again');
      return;
    }
    _connection = TextInput.attach(
      this,
      TextInputConfiguration(
        inputType: TextInputType.number,
        inputAction: TextInputAction.done,
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        enableDeltaModel: enableDeltaModel,
      ),
    );
    _connection!
      ..setEditingState(_value)
      ..show();
    log('[$label] attached+show');
  }

  void detach() {
    _connection?.close();
    _connection = null;
  }

  @override
  TextEditingValue? get currentTextEditingValue => _value;

  @override
  AutofillScope? get currentAutofillScope => null;

  @override
  void updateEditingValue(TextEditingValue value) {
    _value = value;
    log('[$label] set: len=${value.text.length} '
        'comp=${value.composing} sel=${value.selection}');
  }

  @override
  void updateEditingValueWithDeltas(List<TextEditingDelta> deltas) {
    for (final delta in deltas) {
      _value = delta.apply(_value);
      log('[$label] Δ ${delta.toStringShort()} → len=${_value.text.length}');
    }
  }

  @override
  void performAction(TextInputAction action) {
    log('[$label] action=$action len=${_value.text.length}');
  }

  @override
  void connectionClosed() {
    log('[$label] connectionClosed');
  }

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {
    log('[$label] privateCommand($action)');
  }

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {}

  @override
  void showAutocorrectionPromptRect(int start, int end) {}

  @override
  bool onFocusReceived() {
    log('[$label] onFocusReceived');
    return false;
  }

  @override
  void didChangeInputControl(
    TextInputControl? oldControl,
    TextInputControl? newControl,
  ) {
    log('[$label] inputControlChanged');
  }

  @override
  void showToolbar() {}

  @override
  void insertContent(KeyboardInsertedContent content) {}

  @override
  void insertTextPlaceholder(Size size) {}

  @override
  void removeTextPlaceholder() {}

  @override
  void performSelector(String selectorName) {
    log('[$label] selector($selectorName)');
  }
}
