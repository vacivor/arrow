part of 'arrow.dart';

class Arrow {
  final _RouterTree _tree = _RouterTree();
  final List<Middleware> _middlewares = [];
  ErrorHandler _errorHandler = _defaultErrorHandler;
  NotFoundHandler _notFoundHandler = _defaultNotFoundHandler;
  MethodNotAllowedHandler _methodNotAllowedHandler =
      _defaultMethodNotAllowedHandler;

  void use(Middleware middleware) => _middlewares.add(middleware);

  void onError(ErrorHandler handler) => _errorHandler = handler;

  void onNotFound(NotFoundHandler handler) => _notFoundHandler = handler;

  void onMethodNotAllowed(MethodNotAllowedHandler handler) =>
      _methodNotAllowedHandler = handler;

  void get(
    String path,
    Handler handler, {
    List<Middleware> middlewares = const [],
  }) => _add('GET', path, handler, middlewares: middlewares);

  void post(
    String path,
    Handler handler, {
    List<Middleware> middlewares = const [],
  }) => _add('POST', path, handler, middlewares: middlewares);

  void put(
    String path,
    Handler handler, {
    List<Middleware> middlewares = const [],
  }) => _add('PUT', path, handler, middlewares: middlewares);

  void delete(
    String path,
    Handler handler, {
    List<Middleware> middlewares = const [],
  }) => _add('DELETE', path, handler, middlewares: middlewares);

  void _add(
    String method,
    String path,
    Handler handler, {
    List<Middleware> middlewares = const [],
  }) {
    final combined = <Middleware>[..._middlewares, ...middlewares];
    _tree.add(method, path, handler, middlewares: combined);
  }

  RouterGroup group(String prefix, [void Function(RouterGroup group)? define]) {
    final group = RouterGroup._(this, _normalizePrefix(prefix), _middlewares);
    if (define != null) {
      define(group);
    }
    return group;
  }

  Future<HttpServer> listen({
    String address = '0.0.0.0',
    int port = 8080,
  }) async {
    final server = await HttpServer.bind(address, port);
    server.listen(_handle);
    _printAccessUrls(server);
    return server;
  }


  Future<void> _printAccessUrls(HttpServer server) async {
    final port = server.port;

    stdout.writeln('🚀  Local   → http://localhost:$port');

    final ip = await _detectLocalIPv4();
    if (ip != null) {
      stdout.writeln('🌐  Network → http://$ip:$port');
    } else {
      stdout.writeln('🌐  Network → unavailable');
    }
  }

  Future<String?> _detectLocalIPv4() async {
    try {
      final interfaces = await NetworkInterface.list();
      for (final face in interfaces) {
        for (final addr in face.addresses) {
          if (addr.type == InternetAddressType.IPv4 &&
              !addr.isLoopback &&
              !addr.address.startsWith('169.254')) {
            return addr.address;
          }
        }
      }
    } catch (_) {
      // ignore
    }
    return null;
  }

  Future<void> _handle(HttpRequest request) async {
    final method = request.method.toUpperCase();
    final pathSegments = request.uri.pathSegments;

    final match = _tree.match(method, pathSegments);
    if (match != null) {
      final ctx = Context._(request, match.params);
      try {
        await match.run(ctx);
      } catch (error, stackTrace) {
        if (!ctx._ended) {
          try {
            await _errorHandler(ctx, error, stackTrace);
          } catch (_) {
            if (!ctx._ended) {
              ctx.response.statusCode = HttpStatus.internalServerError;
              ctx.response.write('Internal Server Error');
            }
          }
        }
      }
      await ctx._closeIfNeeded();
      return;
    }

    if (method == 'HEAD') {
      final getMatch = _tree.match('GET', pathSegments);
      if (getMatch != null) {
        final ctx = Context._(request, getMatch.params);
        try {
          await getMatch.run(ctx);
        } catch (error, stackTrace) {
          if (!ctx._ended) {
            try {
              await _errorHandler(ctx, error, stackTrace);
            } catch (_) {
              if (!ctx._ended) {
                ctx.response.statusCode = HttpStatus.internalServerError;
                if (!ctx.isHead) {
                  ctx.response.write('Internal Server Error');
                }
              }
            }
          }
        }
        await ctx._closeIfNeeded();
        return;
      }
    }

    final allowedMethods = _tree.allowedMethods(pathSegments);
    if (allowedMethods.isNotEmpty) {
      final ctx = Context._(request, const {});
      try {
        await _methodNotAllowedHandler(ctx, allowedMethods.toList()..sort());
      } catch (_) {
        if (!ctx._ended) {
          ctx.response.statusCode = HttpStatus.methodNotAllowed;
          ctx.response.write('Method Not Allowed');
        }
      }
      await ctx._closeIfNeeded();
      return;
    }

    final ctx = Context._(request, const {});
    try {
      await _notFoundHandler(ctx);
    } catch (_) {
      if (!ctx._ended) {
        ctx.response.statusCode = HttpStatus.notFound;
        if (!ctx.isHead) {
          ctx.response.write('Not Found');
        }
      }
    }
    await ctx._closeIfNeeded();
  }
}

class RouterGroup {
  RouterGroup._(this._app, this._prefix, List<Middleware> middlewares)
    : _middlewares = List<Middleware>.from(middlewares);

  final Arrow _app;
  final String _prefix;
  final List<Middleware> _middlewares;

  void use(Middleware middleware) => _middlewares.add(middleware);

  void get(
    String path,
    Handler handler, {
    List<Middleware> middlewares = const [],
  }) => _add('GET', path, handler, middlewares: middlewares);

  void post(
    String path,
    Handler handler, {
    List<Middleware> middlewares = const [],
  }) => _add('POST', path, handler, middlewares: middlewares);

  void put(
    String path,
    Handler handler, {
    List<Middleware> middlewares = const [],
  }) => _add('PUT', path, handler, middlewares: middlewares);

  void delete(
    String path,
    Handler handler, {
    List<Middleware> middlewares = const [],
  }) => _add('DELETE', path, handler, middlewares: middlewares);

  void _add(
    String method,
    String path,
    Handler handler, {
    List<Middleware> middlewares = const [],
  }) {
    final fullPath = _joinPaths(_prefix, path);
    final combined = <Middleware>[..._middlewares, ...middlewares];
    _app._tree.add(method, fullPath, handler, middlewares: combined);
  }

  RouterGroup group(String prefix, [void Function(RouterGroup group)? define]) {
    final fullPrefix = _joinPaths(_prefix, prefix);
    final group = RouterGroup._(_app, fullPrefix, _middlewares);
    if (define != null) {
      define(group);
    }
    return group;
  }
}

class _RouteEntry {
  _RouteEntry(this.handler, List<Middleware> middlewares)
    : _middlewares = List<Middleware>.from(middlewares);

  final Handler handler;
  final List<Middleware> _middlewares;

  Future<void> run(Context ctx) async {
    Future<void> dispatch(int index) async {
      if (ctx.aborted) {
        return;
      }
      if (index < _middlewares.length) {
        await _middlewares[index](ctx, () => dispatch(index + 1));
        return;
      }
      if (ctx.aborted) {
        return;
      }
      await handler(ctx);
    }

    await dispatch(0);
  }
}

class _Segment {
  _Segment.param(this.name, this.paramType) : isParam = true;

  _Segment.literal(this.name) : isParam = false, paramType = _ParamType.string;

  final String name;
  final bool isParam;
  final _ParamType paramType;
}

List<_Segment> _parse(String path) {
  final raw = path.split('/').where((part) => part.isNotEmpty).toList();
  return raw.map((part) {
    if (part.startsWith('{') && part.endsWith('}') && part.length > 2) {
      final content = part.substring(1, part.length - 1);
      final pieces = content.split(':');
      final name = pieces[0];
      final type = pieces.length > 1 ? pieces[1] : '';
      return _Segment.param(name, _parseParamType(type));
    }
    return _Segment.literal(part);
  }).toList();
}

String _normalizePrefix(String prefix) {
  if (prefix.isEmpty || prefix == '/') {
    return '';
  }
  if (!prefix.startsWith('/')) {
    prefix = '/$prefix';
  }
  if (prefix.endsWith('/')) {
    prefix = prefix.substring(0, prefix.length - 1);
  }
  return prefix;
}

String _joinPaths(String prefix, String path) {
  var base = _normalizePrefix(prefix);
  if (path.isEmpty || path == '/') {
    return base.isEmpty ? '/' : base;
  }
  if (!path.startsWith('/')) {
    path = '/$path';
  }
  if (base.isEmpty) {
    return path;
  }
  return '$base$path';
}

String _normalizeStaticPath(String path) {
  if (path.isEmpty) {
    return '/';
  }
  if (!path.startsWith('/')) {
    path = '/$path';
  }
  if (path.length > 1 && path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  return path;
}

String _pathFromSegments(List<String> segments) {
  if (segments.isEmpty) {
    return '/';
  }
  return '/${segments.join('/')}';
}

enum _ParamType { string, int, uuid }

_ParamType _parseParamType(String raw) {
  switch (raw.toLowerCase()) {
    case 'int':
      return _ParamType.int;
    case 'uuid':
      return _ParamType.uuid;
    case 'string':
    case '':
      return _ParamType.string;
    default:
      return _ParamType.string;
  }
}

bool _validateParam(String value, _ParamType type) {
  switch (type) {
    case _ParamType.int:
      return int.tryParse(value) != null;
    case _ParamType.uuid:
      return _uuidRegex.hasMatch(value);
    case _ParamType.string:
      return true;
  }
}

final RegExp _uuidRegex = RegExp(
  r'^[0-9a-fA-F]{8}-'
  r'[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{12}$',
);

class _RouterTree {
  final Map<String, _RouteNode> _methods = {};
  final Map<String, Map<String, _RouteEntry>> _staticRoutes = {};

  void add(
    String method,
    String path,
    Handler handler, {
    List<Middleware> middlewares = const [],
  }) {
    final segments = _parse(path);
    final isStatic = segments.every((segment) => !segment.isParam);
    final root = _methods.putIfAbsent(method, () => _RouteNode());
    var node = root;
    for (final segment in segments) {
      node = node.childFor(segment);
    }
    final entry = _RouteEntry(handler, middlewares);
    node.route = entry;
    if (isStatic) {
      final byMethod = _staticRoutes.putIfAbsent(method, () => {});
      byMethod[_normalizeStaticPath(path)] = entry;
    }
  }

  _RouteMatch? match(String method, List<String> segments) {
    final byMethod = _staticRoutes[method];
    if (byMethod != null) {
      final staticPath = _pathFromSegments(segments);
      final entry = byMethod[staticPath];
      if (entry != null) {
        return _RouteMatch(entry, const {});
      }
    }
    final root = _methods[method];
    if (root == null) {
      return null;
    }
    return root.match(segments, 0, <String, String>{});
  }

  List<String> allowedMethods(List<String> segments) {
    final allowed = <String>[];
    final staticPath = _pathFromSegments(segments);
    for (final entry in _methods.entries) {
      final staticByMethod = _staticRoutes[entry.key];
      if (staticByMethod != null && staticByMethod.containsKey(staticPath)) {
        allowed.add(entry.key);
        continue;
      }
      final match = entry.value.match(segments, 0, <String, String>{});
      if (match != null) {
        allowed.add(entry.key);
      }
    }
    return allowed;
  }
}

class _RouteMatch {
  _RouteMatch(this.route, this.params);

  final _RouteEntry route;
  final Map<String, String> params;

  Future<void> run(Context ctx) => route.run(ctx);
}

class _RouteNode {
  final Map<String, _RouteNode> staticChildren = {};
  final List<_ParamChild> paramChildren = [];
  _RouteEntry? route;

  _RouteNode childFor(_Segment segment) {
    if (!segment.isParam) {
      return staticChildren.putIfAbsent(segment.name, () => _RouteNode());
    }
    final existing = paramChildren.where((child) {
      return child.name == segment.name && child.type == segment.paramType;
    }).toList();
    if (existing.isNotEmpty) {
      return existing.first.node;
    }
    final child = _ParamChild(segment.name, segment.paramType, _RouteNode());
    paramChildren.add(child);
    paramChildren.sort(_paramChildComparator);
    return child.node;
  }

  _RouteMatch? match(
    List<String> segments,
    int index,
    Map<String, String> params,
  ) {
    if (index == segments.length) {
      if (route == null) {
        return null;
      }
      return _RouteMatch(route!, Map<String, String>.from(params));
    }

    final value = segments[index];
    final staticChild = staticChildren[value];
    if (staticChild != null) {
      final staticMatch = staticChild.match(segments, index + 1, params);
      if (staticMatch != null) {
        return staticMatch;
      }
    }

    for (final child in paramChildren) {
      if (!_validateParam(value, child.type)) {
        continue;
      }
      params[child.name] = value;
      final paramMatch = child.node.match(segments, index + 1, params);
      if (paramMatch != null) {
        return paramMatch;
      }
      params.remove(child.name);
    }

    return null;
  }
}

class _ParamChild {
  _ParamChild(this.name, this.type, this.node);

  final String name;
  final _ParamType type;
  final _RouteNode node;
}

int _paramChildComparator(_ParamChild a, _ParamChild b) {
  return _paramTypeRank(a.type).compareTo(_paramTypeRank(b.type));
}

int _paramTypeRank(_ParamType type) {
  switch (type) {
    case _ParamType.int:
      return 0;
    case _ParamType.uuid:
      return 1;
    case _ParamType.string:
      return 2;
  }
}

FutureOr<void> _defaultErrorHandler(
  Context ctx,
  Object error,
  StackTrace stackTrace,
) async {
  if (ctx.aborted) {
    return;
  }
  ctx.response.statusCode = HttpStatus.internalServerError;
  if (!ctx.isHead) {
    ctx.response.write('Internal Server Error');
  }
}

FutureOr<void> _defaultNotFoundHandler(Context ctx) async {
  if (ctx.aborted) {
    return;
  }
  ctx.response.statusCode = HttpStatus.notFound;
  if (!ctx.isHead) {
    ctx.response.write('Not Found');
  }
}

FutureOr<void> _defaultMethodNotAllowedHandler(
  Context ctx,
  List<String> allowedMethods,
) async {
  if (ctx.aborted) {
    return;
  }
  ctx.response.statusCode = HttpStatus.methodNotAllowed;
  ctx.response.headers.set('Allow', allowedMethods.join(', '));
  if (!ctx.isHead) {
    ctx.response.write('Method Not Allowed');
  }
}
