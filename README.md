<!-- 
This README describes the package. If you publish this package to pub.dev,
this README's contents appear on the landing page for your package.

For information about how to write a good package README, see the guide for
[writing package pages](https://dart.dev/tools/pub/writing-package-pages). 

For general information about developing packages, see the Dart guide for
[creating packages](https://dart.dev/guides/libraries/create-packages)
and the Flutter guide for
[developing packages and plugins](https://flutter.dev/to/develop-packages). 
-->

Arrow is a tiny web framework, built on Dart's `dart:io` `HttpServer`. 

## Features

- Simple HTTP routing (`GET`, `POST`, `PUT`, `DELETE`)
- Path parameters with `{param}` syntax
- Middleware support
- Route groups with prefixes
- Route-level middleware per endpoint
- Chainable group API
- Custom error handling
- 404/405 handlers
- Typed path params: `{id:int}`, `{id:uuid}`
- Context store via `ctx.set` / `ctx.get`
- Parameter helpers: `ctx.param<T>('id')`
- JSON body parsing: `ctx.jsonBody()`
- `HEAD` falls back to `GET` when not explicitly defined
- Minimal `Context` helpers for text and JSON responses

## Getting started

Add the package to your project and create an `Arrow` app.

## Usage

```dart
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
    await ctx.json(
      {'error': 'internal_error', 'message': error.toString()},
      statusCode: 500,
    );
  });

  app.onNotFound((ctx) async {
    await ctx.json({'error': 'not_found'}, statusCode: 404);
  });

  app.onMethodNotAllowed((ctx, allowed) async {
    await ctx.json(
      {'error': 'method_not_allowed', 'allowed': allowed},
      statusCode: 405,
    );
  });

  app.get('/hello', (ctx) async {
    await ctx.text('hello');
  });

  final api = app.group('/api')
    ..use((ctx, next) async {
      final token = ctx.request.headers.value('authorization');
      if (token == null || token.isEmpty) {
        await ctx.abortWithJson(
          {'error': 'unauthorized'},
          statusCode: 401,
        );
        return;
      }
      await next();
    })
    ..get('/users/{id}', (ctx) async {
      ctx.set('userId', ctx.params['id']);
      await ctx.json({'id': ctx.params['id']});
    })
    ..get('/users/{id:int}/posts', (ctx) async {
      final userId = ctx.param<int>('id');
      await ctx.json({'userId': userId, 'posts': []});
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
```

## Additional information

This is a minimal framework intended for learning and small services. It can be
extended with middleware, groups, and more advanced routing as needed.
