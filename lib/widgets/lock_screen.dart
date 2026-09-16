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
  final GlobalKey<PinFieldState> _pinFieldKey = GlobalKey();

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

    // While the cool down runs, the field is read only and the countdown
    // below it is the only feedback worth showing.
    if (_inputBlocked) return;

    if (!_pinRegExp.hasMatch(text)) {
      setState(() => _errorText = L10n.of(context).invalidInput);
      return;
    }

    if (AppLock.of(context).unlock(text)) {
      _pinFieldKey.currentState?.clear();
      return;
    }

    setState(() {
      _errorText = L10n.of(context).wrongPinEntered(_coolDownSeconds);
      _pinFieldKey.currentState?.clear();
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
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
                  PinField(
                    key: _pinFieldKey,
                    pinLength: _pinLength,
                    blocked: _inputBlocked,
                    errorText: _errorText,
                    // Unlock as soon as the last digit is typed; before
                    // that the user is still entering the pin. The IME
                    // action key stays the manual way out.
                    onCompleted: tryUnlock,
                    onSubmitted: tryUnlock,
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A one-line pin entry that talks to the IME through a hand-rolled
/// [TextInputClient] instead of [EditableText] / [TextField].
///
/// Incoming values go straight from the platform into [text]: there is no
/// composing-region bookkeeping, no input-formatter round trip and a plain
/// non-delta connection, so an IME that keeps a ghost buffer (echoing keys
/// on screen without ever committing them to a real [TextEditingValue],
/// which leaves a [TextField] looking alive while starving its `onChanged`)
/// cannot break the full-pin callback here. After every accepted change the
/// authoritative value is echoed back to the IME, so the keyboard's buffer
/// can not desync from what the app actually holds either.
class PinField extends StatefulWidget {
  const PinField({
    super.key,
    required this.onCompleted,
    required this.onSubmitted,
    this.pinLength = 4,
    this.blocked = false,
    this.errorText,
    this.autofocus = true,
  });

  /// Number of digits the pin consists of; input is capped at this length.
  final int pinLength;

  /// Fired exactly when the pin reaches [pinLength] digits (and again when
  /// it is completed anew after a deletion). Never fires for partial input.
  final ValueChanged<String> onCompleted;

  /// Fired with the current pin when the IME action key is pressed, so an
  /// explicit submit is always answered even for an unfinished pin.
  final ValueChanged<String> onSubmitted;

  /// While blocked, the keyboard is dismissed and the field is inert (the
  /// cool down is running).
  final bool blocked;

  /// Error shown below the field; also switches the frame to the error
  /// color while present.
  final String? errorText;

  /// Whether to open the keyboard as soon as the field appears.
  final bool autofocus;

  @override
  State<PinField> createState() => PinFieldState();
}

class PinFieldState extends State<PinField> with TextInputClient {
  TextEditingValue _value = TextEditingValue.empty;
  TextInputConnection? _connection;

  /// The currently held (sanitized) pin.
  String get text => _value.text;

  /// Whether the input connection to the IME is open.
  bool get isAttached => _connection?.attached ?? false;

  static const _config = TextInputConfiguration(
    inputType: TextInputType.number,
    inputAction: TextInputAction.done,
    obscureText: true,
    autocorrect: false,
    enableSuggestions: false,
  );

  @override
  void initState() {
    super.initState();
    if (widget.autofocus && !widget.blocked) {
      WidgetsBinding.instance.addPostFrameCallback((_) => openKeyboard());
    }
  }

  @override
  void didUpdateWidget(PinField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.blocked && !oldWidget.blocked) {
      _closeConnection();
    } else if (!widget.blocked && oldWidget.blocked && widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) => openKeyboard());
    }
  }

  void openKeyboard() {
    if (widget.blocked || !mounted) return;
    if (isAttached) {
      _connection!.show();
      return;
    }
    _connection = TextInput.attach(this, _config);
    _connection!
      ..setEditingState(_value)
      ..show();
  }

  void _closeConnection() {
    _connection?.close();
    _connection = null;
  }

  /// Clears the pin (after a failed attempt); cancels any pending
  /// completion callbacks by resetting the value first.
  void clear() {
    _apply(TextEditingValue.empty);
  }

  @override
  TextEditingValue? get currentTextEditingValue => _value;

  @override
  AutofillScope? get currentAutofillScope => null;

  @override
  void updateEditingValue(TextEditingValue value) {
    _apply(value);
  }

  void _apply(TextEditingValue value) {
    // Sanitize locally instead of input formatters: digits only, capped at
    // the pin length no matter what the IME sends (bulk pastes included).
    var text = value.text.replaceAll(RegExp(r'\D'), '');
    if (text.length > widget.pinLength) {
      text = text.substring(0, widget.pinLength);
    }
    final wasComplete = _value.text.length == widget.pinLength;
    setState(() {
      _value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    });
    // Echo the authoritative value back so the IME's own buffer stays in
    // sync with what the app accepted.
    if (isAttached) _connection!.setEditingState(_value);
    if (text.length == widget.pinLength && !wasComplete) {
      widget.onCompleted(text);
    }
  }

  @override
  void performAction(TextInputAction action) {
    widget.onSubmitted(_value.text);
  }

  @override
  void connectionClosed() {
    _connection = null;
    if (mounted) setState(() {});
  }

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {}

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {}

  @override
  void showAutocorrectionPromptRect(int start, int end) {}

  @override
  void dispose() {
    _closeConnection();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const pillRadius = BorderRadius.all(Radius.circular(32));
    final text = _value.text;
    // Empty: one star per slot as the placeholder; typing: one dot per
    // accepted digit (slots disappear as before).
    final displayedChars =
        text.isEmpty ? '✱' * widget.pinLength : '•' * text.length;
    final hasError = widget.errorText != null;
    final focused = isAttached && !widget.blocked;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          textField: true,
          obscured: true,
          label: 'PIN',
          child: InkWell(
            onTap: widget.blocked ? null : openKeyboard,
            borderRadius: pillRadius,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 20,
              ),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: pillRadius,
                border: Border.all(
                  width: 2,
                  color: hasError
                      ? colorScheme.error
                      : focused
                          ? colorScheme.primary
                          : Colors.transparent,
                ),
              ),
              // Render each glyph in its own Text instead of one string
              // with letterSpacing: Flutter measures the line box with
              // trailing spacing after the LAST glyph too, so the visible
              // ink ends up letterSpacing / 2 to the left of center.
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < displayedChars.length; i++) ...[
                    if (i > 0) const SizedBox(width: 14),
                    Text(
                      displayedChars[i],
                      style: TextStyle(
                        fontSize: text.isEmpty ? 28 : 32,
                        fontWeight: text.isEmpty ? null : FontWeight.w600,
                        color: text.isEmpty
                            ? colorScheme.onSurfaceVariant.withAlpha(100)
                            : colorScheme.onSurface,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(top: 12, left: 16, right: 16),
            child: Text(
              widget.errorText!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }
}
