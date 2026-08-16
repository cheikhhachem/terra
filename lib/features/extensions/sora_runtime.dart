// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:convert';
import 'dart:async';
import 'dart:isolate';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_qjs/flutter_qjs.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:pointycastle/export.dart';

import 'sora_network.dart';

class SoraRuntimeException implements Exception {
  const SoraRuntimeException(this.message);
  final String message;
  @override
  String toString() => message;
}

class SoraRuntime {
  SoraRuntime({this.timeout = const Duration(minutes: 1)});
  final Duration timeout;
  Future<SendPort>? _worker;
  Future<void> _previous = Future.value();
  bool _disposed = false;

  Future<Object?> invoke(
    String script,
    String function,
    List<Object?> arguments,
  ) async {
    final waitFor = _previous;
    final done = Completer<void>();
    _previous = done.future;
    await waitFor;
    try {
      if (_disposed) throw const SoraRuntimeException('Runtime is closed.');
      final response = ReceivePort();
      (await (_worker ??= _startWorker())).send({
        'payload': jsonEncode({
          'script': script,
          'function': function,
          'arguments': arguments,
          'timeout': timeout.inMilliseconds,
        }),
        'reply': response.sendPort,
      });
      final Object? value;
      try {
        value = await response.first.timeout(timeout);
      } finally {
        response.close();
      }
      final decoded = jsonDecode(value as String) as Map<String, dynamic>;
      if (decoded['error'] != null) {
        throw SoraRuntimeException(decoded['error'].toString());
      }
      return decoded['result'];
    } on TimeoutException {
      throw SoraRuntimeException(
        '$function timed out after ${timeout.inSeconds} seconds.',
      );
    } catch (error) {
      if (error is SoraRuntimeException) rethrow;
      throw SoraRuntimeException('$function failed: $error');
    } finally {
      done.complete();
    }
  }

  Future<SendPort> _startWorker() async {
    final ready = ReceivePort();
    await Isolate.spawn(_soraRuntimeWorker, ready.sendPort);
    final port = await ready.first as SendPort;
    ready.close();
    return port;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _worker?.then((port) => port.send(const {'type': 'dispose'}));
  }
}

Future<void> _soraRuntimeWorker(SendPort ready) async {
  final commands = ReceivePort();
  ready.send(commands.sendPort);
  QuickJsRuntime2? runtime;
  await for (final message in commands) {
    if (message is! Map) continue;
    if (message['type'] == 'dispose') {
      runtime?.dispose();
      commands.close();
      return;
    }
    final reply = message['reply'] as SendPort;
    try {
      final payload = jsonDecode(message['payload'] as String) as Map;
      final timeout = Duration(milliseconds: payload['timeout'] as int);
      runtime ??= _createRuntime(timeout);
      final function = payload['function'].toString();
      final call = await runtime.evaluateAsync('''(async function() {
$_bridge
${payload['script']}
if (typeof $function !== "function") throw new Error("Missing function: $function");
return $function(...${jsonEncode(payload['arguments'])});
})()''', sourceUrl: 'terra-call.js');
      if (call.isError) throw SoraRuntimeException(call.stringResult);
      final result = await runtime.handlePromise(call, timeout: timeout);
      if (result.isError) throw SoraRuntimeException(result.stringResult);
      reply.send(jsonEncode({'result': result.stringResult}));
    } catch (error) {
      reply.send(jsonEncode({'error': error.toString()}));
    }
  }
}

QuickJsRuntime2 _createRuntime(Duration timeout) {
  final runtime = QuickJsRuntime2(
    timeout: timeout.inMilliseconds,
    memoryLimit: 64 * 1024 * 1024,
  );
  runtime.onMessage('__sora_log', (dynamic raw) {
    if (raw is List && raw.isNotEmpty) {
      debugPrint('[Terra extension] ${raw.first}');
    }
    return null;
  });
  runtime.onMessage('__sora_fetch', (dynamic raw) async {
    final args = raw is Map
        ? raw.map((key, value) => MapEntry(key.toString(), value))
        : <String, dynamic>{};
    final response = await soraRequest(
      args['url']?.toString() ?? '',
      headers: _headers(args['headers']),
      method: args['method']?.toString() ?? 'GET',
      body: args['body'],
      redirect: args['redirect'] != false,
      encoding: args['encoding']?.toString() ?? 'utf-8',
      timeout: timeout,
    );
    return response.toJson();
  });
  runtime.onMessage('cryptoHandler', (dynamic raw) {
    final args = raw is List ? raw : const [];
    return _cryptoHandler(
      args.firstOrNull?.toString() ?? '',
      args.elementAtOrNull(1)?.toString() ?? '',
      args.elementAtOrNull(2)?.toString() ?? '',
      args.elementAtOrNull(3) == true,
    );
  });
  final epubCache = <String, _EpubBook>{};
  runtime.onMessage('parseEpub', (dynamic raw) async {
    final args = raw is List ? raw : const [];
    final url = args.elementAtOrNull(1)?.toString() ?? '';
    final book = epubCache[url] ??= await _loadEpub(
      url,
      _headers(args.elementAtOrNull(2)),
      timeout,
    );
    return jsonEncode({
      'title': book.title,
      'author': book.author,
      'chapters': book.chapters.keys.toList(),
    });
  });
  runtime.onMessage('parseEpubChapter', (dynamic raw) async {
    final args = raw is List ? raw : const [];
    final url = args.elementAtOrNull(1)?.toString() ?? '';
    final book = epubCache[url] ??= await _loadEpub(
      url,
      _headers(args.elementAtOrNull(2)),
      timeout,
    );
    return book.chapters[args.elementAtOrNull(3)?.toString()] ?? '';
  });
  _installDomBridge(runtime);
  return runtime;
}

class _EpubBook {
  const _EpubBook({
    required this.title,
    required this.author,
    required this.chapters,
  });
  final String title;
  final String author;
  final Map<String, String> chapters;
}

Future<_EpubBook> _loadEpub(
  String url,
  Map<String, String> headers,
  Duration timeout,
) async {
  final uri = Uri.parse(url);
  final client = HttpClient()..connectionTimeout = timeout;
  final bytes = BytesBuilder(copy: false);
  try {
    final request = await client.getUrl(uri).timeout(timeout);
    headers.forEach(request.headers.set);
    final response = await request.close().timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('HTTP ${response.statusCode}', uri: uri);
    }
    await for (final chunk in response.timeout(timeout)) {
      if (bytes.length + chunk.length > 100 * 1024 * 1024) {
        throw const HttpException('EPUB exceeds 100 MB.');
      }
      bytes.add(chunk);
    }
  } finally {
    client.close(force: true);
  }
  final archive = ZipDecoder().decodeBytes(bytes.takeBytes());
  final files = <String, Uint8List>{};
  for (final file in archive.files.where((file) => file.isFile)) {
    final content = file.readBytes();
    if (content != null) files[file.name] = content;
  }
  String text(String path) =>
      utf8.decode(files[path] ?? const [], allowMalformed: true);
  final container = text('META-INF/container.xml');
  final packagePath = RegExp(
    r'''full-path\s*=\s*["']([^"']+)["']''',
    caseSensitive: false,
  ).firstMatch(container)?.group(1);
  if (packagePath == null) throw const FormatException('Invalid EPUB package.');
  final package = text(packagePath);
  String metadata(String tag) =>
      html_parser
          .parseFragment(
            RegExp(
                  '<(?:dc:)?$tag[^>]*>([\\s\\S]*?)</(?:dc:)?$tag>',
                  caseSensitive: false,
                ).firstMatch(package)?.group(1) ??
                '',
          )
          .text
          ?.trim() ??
      '';
  final manifest = <String, String>{};
  final mediaTypes = <String, String>{};
  for (final match in RegExp(
    r'<item\b([^>]*)/?>',
    caseSensitive: false,
  ).allMatches(package)) {
    final attributes = match.group(1) ?? '';
    String attribute(String name) =>
        RegExp(
          '$name\\s*=\\s*["\\\']([^"\\\']+)["\\\']',
          caseSensitive: false,
        ).firstMatch(attributes)?.group(1) ??
        '';
    final id = attribute('id');
    if (id.isNotEmpty) {
      manifest[id] = attribute('href');
      mediaTypes[id] = attribute('media-type');
    }
  }
  var spine = RegExp(
    r'''<itemref\b[^>]*idref\s*=\s*["']([^"']+)["'][^>]*/?>''',
    caseSensitive: false,
  ).allMatches(package).map((match) => match.group(1)!).toList();
  if (spine.isEmpty) {
    spine = manifest.keys
        .where((id) => mediaTypes[id] == 'application/xhtml+xml')
        .toList();
  }
  final chapters = <String, String>{};
  for (final id in spine) {
    final href = manifest[id];
    if (href == null || href.isEmpty) continue;
    final path = Uri.parse(packagePath).resolve(href).path;
    final content = text(path);
    if (content.isEmpty) continue;
    final document = html_parser.parse(content);
    var title = document.querySelector('h1, h2, h3')?.text.trim() ?? '';
    title = title.isEmpty
        ? document.querySelector('title')?.text.trim() ?? ''
        : title;
    title = title.isEmpty ? Uri.parse(href).pathSegments.last : title;
    var unique = title;
    var suffix = 2;
    while (chapters.containsKey(unique)) unique = '$title ($suffix++)';
    chapters[unique] = document.body?.innerHtml ?? content;
  }
  return _EpubBook(
    title: metadata('title'),
    author: metadata('creator'),
    chapters: chapters,
  );
}

String _cryptoHandler(String text, String iv, String key, bool encrypt) {
  try {
    final cipher = PaddedBlockCipher('AES/CBC/PKCS7')
      ..init(
        encrypt,
        PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(
          ParametersWithIV(
            KeyParameter(Uint8List.fromList(utf8.encode(key))),
            Uint8List.fromList(utf8.encode(iv)),
          ),
          null,
        ),
      );
    final output = cipher.process(
      encrypt
          ? Uint8List.fromList(utf8.encode(text))
          : Uint8List.fromList(base64Decode(text)),
    );
    return encrypt ? base64Encode(output) : utf8.decode(output);
  } on Object {
    return text;
  }
}

void _installDomBridge(QuickJsRuntime2 runtime) {
  final elements = <int, dom.Element?>{};
  var nextKey = 0;
  int store(dom.Element? element) {
    elements[++nextKey] = element;
    return nextKey;
  }

  List<dynamic> args(Object? raw) => raw is List ? raw : const [];
  dom.Element? element(Object? key) => elements[(key as num?)?.toInt()];
  dom.Document document(Object? html) =>
      html_parser.parse(html?.toString() ?? '');
  List<int> storeAll(Iterable<dom.Element> values) =>
      values.map(store).toList();
  List<dom.Element> select(
    List<dom.Element> Function(String selector) query,
    String selector,
  ) {
    final structural = RegExp(
      r''':(containsOwn|contains|has)\((.*?)\)''',
      caseSensitive: false,
    ).firstMatch(selector);
    final indexFilter = RegExp(
      r':(eq|lt|gt)\((-?\d+)\)',
      caseSensitive: false,
    ).firstMatch(selector);
    final first = RegExp(
      r':first(?!-)(?:\b|$)',
      caseSensitive: false,
    ).hasMatch(selector);
    final last = RegExp(
      r':last(?!-)(?:\b|$)',
      caseSensitive: false,
    ).hasMatch(selector);
    final standalone = RegExp(
      r':(?:first|last)(?!-)(?:\b|$)',
      caseSensitive: false,
    );
    List<dom.Element> result;
    try {
      if (structural == null) {
        final standard = selector
            .replaceAll(indexFilter?.group(0) ?? '', '')
            .replaceAll(standalone, '')
            .trim();
        result = query(standard.isEmpty ? '*' : standard);
      } else {
        final prefix = selector.substring(0, structural.start).trim();
        final suffix = selector.substring(structural.end);
        final argument = structural
            .group(2)!
            .trim()
            .replaceAll(RegExp(r'''^["']|["']$'''), '');
        var candidates = query(prefix.isEmpty ? '*' : prefix);
        candidates = candidates.where((item) {
          return switch (structural.group(1)!.toLowerCase()) {
            'has' => item.querySelector(argument) != null,
            'containsown' =>
              item.nodes
                  .whereType<dom.Text>()
                  .map((node) => node.data)
                  .join()
                  .toLowerCase()
                  .contains(argument.toLowerCase()),
            _ => item.text.toLowerCase().contains(argument.toLowerCase()),
          };
        }).toList();
        final relative = suffix.trim();
        if (relative.isEmpty) {
          result = candidates;
        } else if (relative.startsWith('>')) {
          final childSelector = relative.substring(1).trim();
          result = candidates
              .expand(
                (item) => item.children.where(
                  (child) =>
                      child.parent
                          ?.querySelectorAll(childSelector)
                          .contains(child) ??
                      false,
                ),
              )
              .toList();
        } else if (relative.startsWith('+')) {
          final siblingSelector = relative.substring(1).trim();
          result = candidates
              .map((item) => item.nextElementSibling)
              .nonNulls
              .where(
                (item) =>
                    item.parent
                        ?.querySelectorAll(siblingSelector)
                        .contains(item) ??
                    false,
              )
              .toList();
        } else if (relative.startsWith('~')) {
          final siblingSelector = relative.substring(1).trim();
          result = candidates.expand((item) {
            final siblings = item.parent?.children ?? const <dom.Element>[];
            final index = siblings.indexOf(item);
            return siblings
                .skip(index + 1)
                .where(
                  (sibling) =>
                      sibling.parent
                          ?.querySelectorAll(siblingSelector)
                          .contains(sibling) ??
                      false,
                );
          }).toList();
        } else {
          result = candidates
              .expand((item) => item.querySelectorAll(relative))
              .toList();
        }
      }
    } on Object {
      return const [];
    }
    if (indexFilter case final match?) {
      var index = int.parse(match.group(2)!);
      if (index < 0) index = result.length + index;
      result = switch (match.group(1)!.toLowerCase()) {
        'lt' =>
          result.indexed
              .where((item) => item.$1 < index)
              .map((item) => item.$2)
              .toList(),
        'gt' =>
          result.indexed
              .where((item) => item.$1 > index)
              .map((item) => item.$2)
              .toList(),
        _ => index >= 0 && index < result.length ? [result[index]] : [],
      };
    }
    if (first && result.isNotEmpty) return [result.first];
    if (last && result.isNotEmpty) return [result.last];
    return result;
  }

  runtime.onMessage('__terra_dom_reset', (_) {
    elements.clear();
    nextKey = 0;
    return null;
  });
  runtime.onMessage('get_doc_element', (raw) {
    final values = args(raw);
    final doc = document(values.firstOrNull);
    return store(switch (values.elementAtOrNull(1)) {
      'body' => doc.body,
      'documentElement' => doc.documentElement,
      'head' => doc.head,
      _ => doc.parent,
    });
  });
  runtime.onMessage('get_doc_string', (raw) {
    final values = args(raw);
    final doc = document(values.firstOrNull);
    return values.elementAtOrNull(1) == 'text' ? doc.text : doc.outerHtml;
  });
  runtime.onMessage('get_element_string', (raw) {
    final values = args(raw);
    final current = element(values.elementAtOrNull(1));
    return switch (values.firstOrNull) {
          'text' => current?.text,
          'innerHtml' => current?.innerHtml,
          'outerHtml' => current?.outerHtml,
          'className' => current?.className,
          'localName' => current?.localName,
          'namespaceUri' => current?.namespaceUri,
          'getSrc' => current?.attributes['src'],
          'getImg' => current?.attributes['img'],
          'getHref' => current?.attributes['href'],
          _ =>
            current?.attributes['data-src'] ??
                current?.attributes['data-lazy-src'],
        } ??
        '';
  });
  runtime.onMessage('doc_select_first', (raw) {
    final values = args(raw);
    final doc = document(values.firstOrNull);
    return store(
      select(
        (selector) => doc.querySelectorAll(selector),
        values.elementAtOrNull(1)?.toString() ?? '',
      ).firstOrNull,
    );
  });
  runtime.onMessage('doc_select', (raw) {
    final values = args(raw);
    final doc = document(values.firstOrNull);
    return jsonEncode(
      storeAll(
        select(
          (selector) => doc.querySelectorAll(selector),
          values.elementAtOrNull(1)?.toString() ?? '',
        ),
      ),
    );
  });
  runtime.onMessage('ele_selectFirst', (raw) {
    final values = args(raw);
    final current = element(values.elementAtOrNull(1));
    return store(
      current == null
          ? null
          : select(
              (selector) => current.querySelectorAll(selector),
              values.firstOrNull?.toString() ?? '',
            ).firstOrNull,
    );
  });
  runtime.onMessage('ele_select', (raw) {
    final values = args(raw);
    final current = element(values.elementAtOrNull(1));
    return jsonEncode(
      storeAll(
        current == null
            ? const []
            : select(
                (selector) => current.querySelectorAll(selector),
                values.firstOrNull?.toString() ?? '',
              ),
      ),
    );
  });
  runtime.onMessage('ele_element_sibling', (raw) {
    final values = args(raw);
    final current = element(values.elementAtOrNull(1));
    return store(
      values.firstOrNull == 'nextElementSibling'
          ? current?.nextElementSibling
          : current?.previousElementSibling,
    );
  });
  runtime.onMessage('ele_attr', (raw) {
    final values = args(raw);
    return element(values.elementAtOrNull(1))?.attributes[values.firstOrNull
            ?.toString()] ??
        '';
  });
  runtime.onMessage('doc_attr', (raw) {
    final values = args(raw);
    return document(values.firstOrNull).documentElement?.attributes[values
            .elementAtOrNull(1)
            ?.toString()] ??
        '';
  });
  runtime.onMessage('ele_has_attr', (raw) {
    final values = args(raw);
    return element(
          values.elementAtOrNull(1),
        )?.attributes.containsKey(values.firstOrNull?.toString()) ??
        false;
  });
  runtime.onMessage('doc_has_attr', (raw) {
    final values = args(raw);
    return document(values.firstOrNull).documentElement?.attributes.containsKey(
          values.elementAtOrNull(1)?.toString(),
        ) ??
        false;
  });
  runtime.onMessage('doc_get_elements_by', (raw) {
    final values = args(raw);
    final doc = document(values.firstOrNull);
    final name = values.elementAtOrNull(2)?.toString() ?? '';
    final found = switch (values.elementAtOrNull(1)) {
      'children' => doc.children,
      'getElementsByTagName' => doc.getElementsByTagName(name),
      _ => doc.getElementsByClassName(name),
    };
    return jsonEncode(storeAll(found));
  });
  runtime.onMessage('ele_get_elements_by', (raw) {
    final values = args(raw);
    final current = element(values.elementAtOrNull(2));
    final name = values.elementAtOrNull(1)?.toString() ?? '';
    final found = switch (values.firstOrNull) {
      'children' => current?.children,
      'getElementsByTagName' => current?.getElementsByTagName(name),
      _ => current?.getElementsByClassName(name),
    };
    return jsonEncode(storeAll(found ?? const []));
  });
  runtime.onMessage('doc_get_element_by_id', (raw) {
    final values = args(raw);
    return store(
      document(
        values.firstOrNull,
      ).getElementById(values.elementAtOrNull(1)?.toString() ?? ''),
    );
  });
}

Map<String, String> _headers(Object? value) => value is Map
    ? value.map((key, value) => MapEntry(key.toString(), value.toString()))
    : const {};

const _bridge = r'''
class MProvider {}
class Client {
  constructor(reqcopyWith) { this.reqcopyWith = reqcopyWith; }
  get(url, headers) { return this.request(url, headers, 'GET'); }
  post(url, headers, body) { return this.request(url, headers, 'POST', body); }
  head(url, headers) { return this.request(url, headers, 'HEAD'); }
  put(url, headers, body) { return this.request(url, headers, 'PUT', body); }
  delete(url, headers, body) { return this.request(url, headers, 'DELETE', body); }
  patch(url, headers, body) { return this.request(url, headers, 'PATCH', body); }
  request(url, headers, method, body) {
    return fetchv2(url, headers || {}, method || 'GET', body || null).then(function(response) {
      return { body: response._data, statusCode: response.status, headers: response.headers };
    });
  }
}
var __terraPreferenceDefaults = {};
class SharedPreferences {
  get(key, defaultValue) { return Object.prototype.hasOwnProperty.call(__terraPreferenceDefaults, key) ? __terraPreferenceDefaults[key] : defaultValue; }
  getString(key, defaultValue) { var value = this.get(key, defaultValue || ''); return value == null ? '' : String(value); }
  getInt(key, defaultValue) { var value = this.get(key, defaultValue || 0); return Number(value); }
  getBool(key, defaultValue) { return Boolean(this.get(key, defaultValue || false)); }
  set() {}
  setString() {}
  setInt() {}
  setBool() {}
}
function cryptoHandler(text, iv, secretKeyString, encrypt) {
  return sendMessage('cryptoHandler', JSON.stringify([text, iv, secretKeyString, encrypt]));
}
async function parseEpub(bookName, url, headers) {
  return JSON.parse(await sendMessage('parseEpub', JSON.stringify([bookName, url, headers])));
}
async function parseEpubChapter(bookName, url, headers, chapterTitle) {
  return await sendMessage('parseEpubChapter', JSON.stringify([bookName, url, headers, chapterTitle]));
}
sendMessage('__terra_dom_reset', '[]');
class Document {
  constructor(html) { this.html = html || ''; }
  _element(type) { return new Element(sendMessage('get_doc_element', JSON.stringify([this.html, type]))); }
  get body() { return this._element('body'); }
  get documentElement() { return this._element('documentElement'); }
  get head() { return this._element('head'); }
  get parent() { return this._element('parent'); }
  get text() { return sendMessage('get_doc_string', JSON.stringify([this.html, 'text'])); }
  get outerHtml() { return sendMessage('get_doc_string', JSON.stringify([this.html, 'outerHtml'])); }
  selectFirst(selector) { return new Element(sendMessage('doc_select_first', JSON.stringify([this.html, selector]))); }
  select(selector) { return JSON.parse(sendMessage('doc_select', JSON.stringify([this.html, selector]))).map(function(key) { return new Element(key); }); }
  querySelector(selector) { return this.selectFirst(selector); }
  querySelectorAll(selector) { return this.select(selector); }
  get children() { return this._elements('children', ''); }
  getElementsByTagName(name) { return this._elements('getElementsByTagName', name); }
  getElementsByClassName(name) { return this._elements('getElementsByClassName', name); }
  getElementById(id) { return new Element(sendMessage('doc_get_element_by_id', JSON.stringify([this.html, id]))); }
  _elements(type, name) { return JSON.parse(sendMessage('doc_get_elements_by', JSON.stringify([this.html, type, name]))).map(function(key) { return new Element(key); }); }
  attr(name) { return sendMessage('doc_attr', JSON.stringify([this.html, name])); }
  hasAttr(name) { return sendMessage('doc_has_attr', JSON.stringify([this.html, name])); }
}
class Element {
  constructor(key) { this.key = key; }
  _string(type) { return sendMessage('get_element_string', JSON.stringify([type, this.key])); }
  get text() { return this._string('text'); }
  get innerHtml() { return this._string('innerHtml'); }
  get outerHtml() { return this._string('outerHtml'); }
  get className() { return this._string('className'); }
  get localName() { return this._string('localName'); }
  get namespaceUri() { return this._string('namespaceUri'); }
  get getSrc() { return this._string('getSrc'); }
  get getImg() { return this._string('getImg'); }
  get getHref() { return this._string('getHref'); }
  get getDataSrc() { return this._string('getDataSrc'); }
  get previousElementSibling() { return this._sibling('previousElementSibling'); }
  get nextElementSibling() { return this._sibling('nextElementSibling'); }
  _sibling(type) { return new Element(sendMessage('ele_element_sibling', JSON.stringify([type, this.key]))); }
  selectFirst(selector) { return new Element(sendMessage('ele_selectFirst', JSON.stringify([selector, this.key]))); }
  select(selector) { return JSON.parse(sendMessage('ele_select', JSON.stringify([selector, this.key]))).map(function(key) { return new Element(key); }); }
  querySelector(selector) { return this.selectFirst(selector); }
  querySelectorAll(selector) { return this.select(selector); }
  get children() { return this._elements('children', ''); }
  getElementsByTagName(name) { return this._elements('getElementsByTagName', name); }
  getElementsByClassName(name) { return this._elements('getElementsByClassName', name); }
  _elements(type, name) { return JSON.parse(sendMessage('ele_get_elements_by', JSON.stringify([type, name, this.key]))).map(function(key) { return new Element(key); }); }
  attr(name) { return sendMessage('ele_attr', JSON.stringify([name, this.key])); }
  getAttribute(name) { return this.attr(name); }
  hasAttr(name) { return sendMessage('ele_has_attr', JSON.stringify([name, this.key])); }
  hasAttribute(name) { return this.hasAttr(name); }
}
var console = {
  log: function() { sendMessage('__sora_log', JSON.stringify(Array.prototype.slice.call(arguments))); },
  error: function() { sendMessage('__sora_log', JSON.stringify(Array.prototype.slice.call(arguments))); }
};
function __soraRequest(url, headers, method, body, redirect, encoding) {
  return sendMessage('__sora_fetch', JSON.stringify({url:url, headers:headers, method:method, body:body, redirect:redirect, encoding:encoding}));
}
function fetch(url, options) {
  options = options || {};
  return fetchv2(
    url,
    options.headers || {},
    options.method || 'GET',
    options.body || null,
    options.redirect !== 'manual',
    'utf-8'
  );
}
function fetchv2(url, headers = {}, method = 'GET', body = null, redirect = true, encoding = 'utf-8') {
  var processedHeaders = headers && typeof headers === 'object' && !Array.isArray(headers) ? headers : {};
  var processedBody = method === 'GET' ? null : body && typeof body === 'object' ? JSON.stringify(body) : body;
  return __soraRequest(url, processedHeaders, method, processedBody, redirect, encoding).then(function(value) {
    return {
      status: value.status,
      headers: value.headers,
      _data: value.body,
      text: function() { return Promise.resolve(this._data); },
      json: function() { try { return Promise.resolve(JSON.parse(this._data)); } catch (e) { return Promise.reject('JSON parse error: ' + e.message); } }
    };
  });
}
var __soraB64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
function btoa(value) {
  var input = String(value), output = '', i = 0;
  while (i < input.length) {
    var a = input.charCodeAt(i++), b = input.charCodeAt(i++), c = input.charCodeAt(i++);
    if (a > 255 || b > 255 || c > 255) throw new TypeError('btoa accepts binary strings only');
    output += __soraB64.charAt(a >> 2) + __soraB64.charAt(((a & 3) << 4) | (b >> 4)) +
      __soraB64.charAt(isNaN(b) ? 64 : ((b & 15) << 2) | (c >> 6)) + __soraB64.charAt(isNaN(c) ? 64 : c & 63);
  }
  return output;
}
function atob(value) {
  var input = String(value).replace(/[\t\n\f\r ]/g, '');
  if (input.length % 4 === 1 || /[^A-Za-z0-9+/=]/.test(input)) throw new TypeError('Invalid base64 input');
  var output = '', i = 0;
  while (i < input.length) {
    var a = __soraB64.indexOf(input.charAt(i++)), b = __soraB64.indexOf(input.charAt(i++));
    var c = __soraB64.indexOf(input.charAt(i++)), d = __soraB64.indexOf(input.charAt(i++));
    output += String.fromCharCode((a << 2) | (b >> 4));
    if (c !== 64 && c !== -1) output += String.fromCharCode(((b & 15) << 4) | (c >> 2));
    if (d !== 64 && d !== -1) output += String.fromCharCode(((c & 3) << 6) | d);
  }
  return output;
}
function log() { console.log.apply(console, arguments); }
function getElementsByTag(html, tag) { var regex = new RegExp('<' + tag + '[^>]*>([\\s\\S]*?)<\\/' + tag + '>', 'gi'), result = [], match; while ((match = regex.exec(html)) !== null) result.push(match[1]); return result; }
function getAttribute(html, tag, attr) { var match = new RegExp('<' + tag + '[^>]*' + attr + '=["\']?([^"\' >]+)["\']?[^>]*>', 'i').exec(html); return match ? match[1] : null; }
function getInnerText(html) { return html.replace(/<[^>]+>/g, '').replace(/\s+/g, ' ').trim(); }
function extractBetween(str, start, end) { var s = str.indexOf(start); if (s < 0) return ''; var e = str.indexOf(end, s + start.length); return e < 0 ? '' : str.substring(s + start.length, e); }
function stripHtml(html) { return html.replace(/<[^>]+>/g, ''); }
function normalizeWhitespace(str) { return str.replace(/\s+/g, ' ').trim(); }
function urlEncode(str) { return encodeURIComponent(str); }
function urlDecode(str) { try { return decodeURIComponent(str); } catch (_) { return str; } }
function htmlEntityDecode(str) { return str.replace(/&([a-zA-Z]+);/g, function(all, entity) { return ({quot:'"', apos:"'", amp:'&', lt:'<', gt:'>'})[entity] || all; }); }
function transformResponse(response, fn) { try { return fn(response); } catch (_) { return response; } }
''';
