part of 'arrow.dart';

class Context {
  Context._(this.request, this.params) : response = request.response;

  final HttpRequest request;
  final HttpResponse response;
  final Map<String, String> params;

  bool _ended = false;
  bool _aborted = false;
  final Map<String, Object?> _store = {};
  String? _cachedBody;
  Object? _cachedJson;

  Map<String, String> get query => request.uri.queryParameters;
  bool get aborted => _aborted;
  bool get isHead => request.method.toUpperCase() == 'HEAD';

  void status(int code) {
    response.statusCode = code;
  }

  Future<String> body() async {
    if (_cachedBody != null) {
      return _cachedBody!;
    }
    _cachedBody = await utf8.decoder.bind(request).join();
    return _cachedBody!;
  }

  Future<Object?> jsonBody() async {
    if (_cachedJson != null) {
      return _cachedJson;
    }
    final raw = await body();
    if (raw.isEmpty) {
      _cachedJson = null;
      return null;
    }
    _cachedJson = jsonDecode(raw);
    return _cachedJson;
  }

  Future<void> text(String value, {int? statusCode}) async {
    if (statusCode != null) {
      response.statusCode = statusCode;
    }
    response.headers.contentType = ContentType.text;
    if (!isHead) {
      response.write(value);
    }
    await _close();
  }

  Future<void> json(Object value, {int? statusCode}) async {
    if (statusCode != null) {
      response.statusCode = statusCode;
    }
    response.headers.contentType = ContentType.json;
    if (!isHead) {
      response.write(jsonEncode(value));
    }
    await _close();
  }

  void abort() {
    _aborted = true;
  }

  Future<void> abortWithStatus(int statusCode, {String? message}) async {
    _aborted = true;
    response.statusCode = statusCode;
    if (message != null && !isHead) {
      response.write(message);
    }
    await _close();
  }

  Future<void> abortWithText(String value, {int statusCode = 403}) async {
    _aborted = true;
    response.statusCode = statusCode;
    response.headers.contentType = ContentType.text;
    if (!isHead) {
      response.write(value);
    }
    await _close();
  }

  Future<void> abortWithJson(Object value, {int statusCode = 403}) async {
    _aborted = true;
    response.statusCode = statusCode;
    response.headers.contentType = ContentType.json;
    if (!isHead) {
      response.write(jsonEncode(value));
    }
    await _close();
  }

  void set(String key, Object? value) {
    _store[key] = value;
  }

  T? get<T>(String key) {
    final value = _store[key];
    if (value is T) {
      return value;
    }
    return null;
  }

  T? param<T>(String name) {
    final raw = params[name];
    if (raw == null) {
      return null;
    }
    if (T == String) {
      return raw as T;
    }
    if (T == int) {
      return int.tryParse(raw) as T?;
    }
    if (T == double) {
      return double.tryParse(raw) as T?;
    }
    if (T == bool) {
      if (raw == 'true') {
        return true as T;
      }
      if (raw == 'false') {
        return false as T;
      }
      return null;
    }
    return null;
  }

  Future<void> _close() async {
    if (_ended) {
      return;
    }
    _ended = true;
    await response.close();
  }

  Future<void> _closeIfNeeded() async {
    if (!_ended) {
      await _close();
    }
  }
}
