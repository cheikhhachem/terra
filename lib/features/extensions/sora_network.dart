// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const soraResponseLimit = 10 * 1000 * 1000;

class SoraHttpResponse {
  const SoraHttpResponse({
    required this.status,
    required this.headers,
    required this.body,
  });
  final int status;
  final Map<String, String> headers;
  final String body;
  Map<String, dynamic> toJson() => {
    'status': status,
    'headers': headers,
    'body': body,
  };
}

Future<SoraHttpResponse> soraRequest(
  String url, {
  Map<String, String> headers = const {},
  String method = 'GET',
  Object? body,
  bool redirect = true,
  String encoding = 'utf-8',
  Duration timeout = const Duration(seconds: 20),
}) async {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme || !{'http', 'https'}.contains(uri.scheme))
    throw FormatException('Invalid URL: $url');
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final request = await client
        .openUrl(method.toUpperCase(), uri)
        .timeout(timeout);
    request.followRedirects = redirect;
    headers.forEach(request.headers.set);
    if (method.toUpperCase() != 'GET' && body != null)
      request.write(body is String ? body : jsonEncode(body));
    final response = await request.close().timeout(timeout);
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.timeout(timeout)) {
      if (bytes.length + chunk.length > soraResponseLimit)
        throw const HttpException('Response exceeds 10 MB limit.');
      bytes.add(chunk);
    }
    final responseHeaders = <String, String>{};
    response.headers.forEach(
      (name, values) => responseHeaders[name] = values.join(', '),
    );
    return SoraHttpResponse(
      status: response.statusCode,
      headers: responseHeaders,
      body: _decode(bytes.takeBytes(), encoding),
    );
  } finally {
    client.close(force: true);
  }
}

String _decode(Uint8List bytes, String name) {
  switch (name.toLowerCase().replaceAll('_', '-')) {
    case 'ascii':
      return ascii.decode(bytes, allowInvalid: true);
    case 'latin1':
    case 'iso-8859-1':
      return latin1.decode(bytes);
    case 'windows-1252':
    case 'cp1252':
      const controls =
          '\u20ac\u0081\u201a\u0192\u201e\u2026\u2020\u2021\u02c6\u2030\u0160\u2039\u0152\u008d\u017d\u008f\u0090\u2018\u2019\u201c\u201d\u2022\u2013\u2014\u02dc\u2122\u0161\u203a\u0153\u009d\u017e\u0178';
      return String.fromCharCodes(
        bytes.map(
          (byte) => byte >= 0x80 && byte <= 0x9f
              ? controls.codeUnitAt(byte - 0x80)
              : byte,
        ),
      );
    case 'windows-1251':
    case 'cp1251':
      const high =
          '\u0402\u0403\u201a\u0453\u201e\u2026\u2020\u2021\u20ac\u2030\u0409\u2039\u040a\u040c\u040b\u040f\u0452\u2018\u2019\u201c\u201d\u2022\u2013\u2014\u0098\u2122\u0459\u203a\u045a\u045c\u045b\u045f\u00a0\u040e\u045e\u0408\u00a4\u0490\u00a6\u00a7\u0401\u00a9\u0404\u00ab\u00ac\u00ad\u00ae\u0407\u00b0\u00b1\u0406\u0456\u0491\u00b5\u00b6\u00b7\u0451\u2116\u0454\u00bb\u0458\u0405\u0455\u0457';
      return String.fromCharCodes(
        bytes.map(
          (byte) => byte < 0x80
              ? byte
              : byte >= 0xc0
              ? 0x0410 + byte - 0xc0
              : high.codeUnitAt(byte - 0x80),
        ),
      );
    case 'utf16':
    case 'utf-16':
      final little = bytes.length >= 2 && bytes[0] == 0xff && bytes[1] == 0xfe;
      final start =
          bytes.length >= 2 &&
              ((bytes[0] == 0xff && bytes[1] == 0xfe) ||
                  (bytes[0] == 0xfe && bytes[1] == 0xff))
          ? 2
          : 0;
      return String.fromCharCodes([
        for (var i = start; i + 1 < bytes.length; i += 2)
          little ? bytes[i] | bytes[i + 1] << 8 : bytes[i] << 8 | bytes[i + 1],
      ]);
    default:
      return utf8.decode(bytes, allowMalformed: true);
  }
}
