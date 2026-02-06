part of 'arrow.dart';

typedef Handler = FutureOr<void> Function(Context ctx);
typedef Next = Future<void> Function();
typedef Middleware = FutureOr<void> Function(Context ctx, Next next);
typedef ErrorHandler =
    FutureOr<void> Function(Context ctx, Object error, StackTrace stackTrace);
typedef NotFoundHandler = FutureOr<void> Function(Context ctx);
typedef MethodNotAllowedHandler =
    FutureOr<void> Function(Context ctx, List<String> allowedMethods);
