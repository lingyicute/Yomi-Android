import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'package:yomi/config/isrg_x1.dart';

class CustomHttpClient {
  static HttpClient customHttpClient(String? cert) {
    final context = SecurityContext.defaultContext;

    try {
      if (cert != null) {
        final bytes = utf8.encode(cert);
        context.setTrustedCertificatesBytes(bytes);
      }
    } on TlsException catch (e) {
      if (e.osError != null &&
          e.osError!.message.contains('CERT_ALREADY_IN_HASH_TABLE')) {
      } else {
        rethrow;
      }
    }

    return HttpClient(context: context)
      // Long-poll `/sync` holds the TCP connection for up to 20s. The default
      // 15s idle timeout would otherwise recycle the socket between polls.
      ..idleTimeout = const Duration(seconds: 90)
      ..connectionTimeout = const Duration(seconds: 20);
  }

  static http.Client createHTTPClient() => IOClient(customHttpClient(ISRG_X1));
}
