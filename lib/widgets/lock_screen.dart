import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:yomi/config/themes.dart';
import 'package:yomi/l10n/l10n.dart';
import 'package:yomi/widgets/app_lock.dart';
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});
  @override
  State<LockScreen> createState() => _LockScreenState();
}
class _LockScreenState extends State<LockScreen> {
  String? _errorText;
  int _coolDownSeconds = 5;
  bool _inputBlocked = false;
  final TextEditingController _textEditingController = TextEditingController();
  void tryUnlock(String text) async {
    setState(() {
      _errorText = null;
    });
    if (text.length < 4) return;
    final enteredPin = int.tryParse(text);
    if (enteredPin == null || text.length != 4) {
      setState(() {
        _errorText = L10n.of(context).invalidInput;
      });
      _textEditingController.clear();
      return;
    }
    if (AppLock.of(context).unlock(enteredPin.toString())) {
      setState(() {
        _inputBlocked = false;
        _errorText = null;
      });
      _textEditingController.clear();
      return;
    }
    setState(() {
      _errorText = L10n.of(context).wrongPinEntered(_coolDownSeconds);
      _inputBlocked = true;
    });
    Future.delayed(Duration(seconds: _coolDownSeconds)).then((_) {
      if (!mounted) return;
      setState(() {
        _inputBlocked = false;
        _coolDownSeconds *= 2;
        _errorText = null;
      });
    });
    _textEditingController.clear();
  }
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const pillRadius = BorderRadius.all(Radius.circular(32));
    return Scaffold(
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
                  onChanged: tryUnlock,
                  onSubmitted: tryUnlock,
                  style: TextStyle(
                    fontSize: 32,
                    letterSpacing: 14,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(4),
                  ],
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: colorScheme.surfaceContainerHighest,
                    errorText: _errorText,
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
                if (_inputBlocked)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
