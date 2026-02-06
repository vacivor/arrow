import 'dart:async';
import 'dart:io';

import 'package:arrow/arrow.dart';

Future<void> main() async {
  final app = Arrow();

  app.use((ctx, next) async {
    final started = DateTime.now();
    await next();
    final elapsed = DateTime.now().difference(started);
    stdout.writeln('${ctx.request.method} ${ctx.request.uri.path} $elapsed');
  });

  app.onError((ctx, error, stackTrace) async {
    await ctx.json({
      'error': 'internal_error',
      'message': error.toString(),
    }, statusCode: 500);
  });

  app.onNotFound((ctx) async {
    await ctx.json({'error': 'not_found'}, statusCode: 404);
  });

  app.onMethodNotAllowed((ctx, allowed) async {
    await ctx.json({
      'error': 'method_not_allowed',
      'allowed': allowed,
    }, statusCode: 405);
  });

  app.get('/hello', (ctx) async {
    await ctx.text('hello');
  });

  app.group('/api')
    ..use(midw)
    ..get('/users/{id}', user)
    ..get('/users/{id:int}/posts', (ctx) async {
      await ctx.json({'userId': ctx.params['id'], 'posts': []});
    })
    ..get(
      '/health',
      (ctx) async => ctx.text('ok'),
      middlewares: [
        (ctx, next) async {
          ctx.response.headers.add('x-route', 'health');
          await next();
        },
      ],
    );

  await app.listen(port: 8080);
}

FutureOr<void> midw(Context ctx, Next next) async {
  final token = ctx.request.headers.value('authorization');
  if (token == null || token.isEmpty) {
    await ctx.abortWithJson({'error': 'unauthorized'}, statusCode: 401);
    return;
  }
  await next();
}

FutureOr<void> user(Context ctx) async {
  ctx.set('userId', ctx.params['id']);
  await ctx.json({'id': ctx.params['id']});
}
