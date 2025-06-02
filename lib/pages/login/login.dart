import 'dart:async';

import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:yomi/l10n/l10n.dart';
import 'package:yomi/utils/localized_exception_extension.dart';
import 'package:yomi/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:yomi/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:yomi/widgets/future_loading_dialog.dart';
import 'package:yomi/widgets/matrix.dart';
import '../../utils/platform_infos.dart';
import 'login_view.dart';

class Login extends StatefulWidget {
  const Login({super.key});

  @override
  LoginController createState() => LoginController();
}

class LoginController extends State<Login> {
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  String? usernameError;
  String? passwordError;
  bool loading = false;
  bool showPassword = false;

  void toggleShowPassword() =>
      setState(() => showPassword = !loading && !showPassword);

  void login() async {
    final matrix = Matrix.of(context);
    if (usernameController.text.isEmpty) {
      setState(() => usernameError = L10n.of(context).pleaseEnterYourUsername);
    } else {
      // 验证用户名格式
      validateUsername(usernameController.text);
      
      // 如果有错误，直接返回
      if (usernameError != null) {
        return;
      }
    }
    if (passwordController.text.isEmpty) {
      setState(() => passwordError = L10n.of(context).pleaseEnterYourPassword);
    } else {
      setState(() => passwordError = null);
    }

    if (usernameController.text.isEmpty || passwordController.text.isEmpty || usernameError != null) {
      return;
    }

    setState(() => loading = true);

    _coolDown?.cancel();

    try {
      // 构建正确的用户名格式 @username:92li.uk
      // 移除可能的前导@符号
      String cleanUsername = usernameController.text;
      if (cleanUsername.startsWith('@')) {
        cleanUsername = cleanUsername.substring(1);
      }
      final username = "@${cleanUsername}:92li.uk";
      AuthenticationIdentifier identifier = AuthenticationUserIdentifier(user: username);
      
      await matrix.getLoginClient().login(
            LoginType.mLoginPassword,
            identifier: identifier,
            // To stay compatible with older server versions
            // ignore: deprecated_member_use
            user: username,
            password: passwordController.text,
            initialDeviceDisplayName: PlatformInfos.clientName,
          );
    } on MatrixException catch (exception) {
      setState(() => passwordError = exception.errorMessage);
      return setState(() => loading = false);
    } catch (exception) {
      setState(() => passwordError = exception.toString());
      return setState(() => loading = false);
    }

    if (mounted) setState(() => loading = false);
  }

  Timer? _coolDown;

  void checkWellKnownWithCoolDown(String userId) async {
    _coolDown?.cancel();
    // 由于使用固定服务器，此方法不再需要执行额外操作
    // 验证用户名格式
    validateUsername(userId);
  }

  void validateUsername(String userId) {
    // 检查用户名是否包含非法字符
    final hasInvalidChars = userId.contains(':') || userId.contains('@');
    
    setState(() {
      if (hasInvalidChars) {
        usernameError = '用户名不应包含 @ 或 : 字符';
      } else {
        usernameError = null;
      }
    });
  }

  void _checkWellKnown(String userId) async {
    // 同样不再需要检查 well-known
  }

  void passwordForgotten() async {
    final input = await showTextInputDialog(
      useRootNavigator: false,
      context: context,
      title: L10n.of(context).passwordForgotten,
      message: L10n.of(context).enterAnEmailAddress,
      okLabel: L10n.of(context).ok,
      cancelLabel: L10n.of(context).cancel,
      initialText:
          usernameController.text.isEmail ? usernameController.text : '',
      hintText: L10n.of(context).enterAnEmailAddress,
      keyboardType: TextInputType.emailAddress,
    );
    if (input == null) return;
    final clientSecret = DateTime.now().millisecondsSinceEpoch.toString();
    final response = await showFutureLoadingDialog(
      context: context,
      future: () =>
          Matrix.of(context).getLoginClient().requestTokenToResetPasswordEmail(
                clientSecret,
                input,
                sendAttempt++,
              ),
    );
    if (response.error != null) return;
    final password = await showTextInputDialog(
      useRootNavigator: false,
      context: context,
      title: L10n.of(context).passwordForgotten,
      message: L10n.of(context).chooseAStrongPassword,
      okLabel: L10n.of(context).ok,
      cancelLabel: L10n.of(context).cancel,
      hintText: '******',
      obscureText: true,
      minLines: 1,
      maxLines: 1,
    );
    if (password == null) return;
    final ok = await showOkAlertDialog(
      useRootNavigator: false,
      context: context,
      title: L10n.of(context).weSentYouAnEmail,
      message: L10n.of(context).pleaseClickOnLink,
      okLabel: L10n.of(context).iHaveClickedOnLink,
    );
    if (ok != OkCancelResult.ok) return;
    final data = <String, dynamic>{
      'new_password': password,
      'logout_devices': false,
      "auth": AuthenticationThreePidCreds(
        type: AuthenticationTypes.emailIdentity,
        threepidCreds: ThreepidCreds(
          sid: response.result!.sid,
          clientSecret: clientSecret,
        ),
      ).toJson(),
    };
    final success = await showFutureLoadingDialog(
      context: context,
      future: () => Matrix.of(context).getLoginClient().request(
            RequestType.POST,
            '/client/v3/account/password',
            data: data,
          ),
    );
    if (success.error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.of(context).passwordHasBeenChanged)),
      );
      usernameController.text = input;
      passwordController.text = password;
      login();
    }
  }

  static int sendAttempt = 0;

  @override
  Widget build(BuildContext context) => LoginView(this);
}

extension on String {
  static final RegExp _phoneRegex =
      RegExp(r'^[+]*[(]{0,1}[0-9]{1,4}[)]{0,1}[-\s\./0-9]*$');
  static final RegExp _emailRegex = RegExp(r'(.+)@(.+)\.(.+)');

  bool get isEmail => _emailRegex.hasMatch(this);

  bool get isPhoneNumber => _phoneRegex.hasMatch(this);
}
