import 'package:arrow/arrow.dart';
import 'package:test/test.dart';

void main() {
  test('can register routes', () {
    final app = Arrow();
    app.get('/health', (ctx) async {});
    app.get('/users/{id}', (ctx) async {}, middlewares: [
      (ctx, next) async {
        await next();
      }
    ]);
    final api = app.group('/api')
      ..get('/health', (ctx) async {})
      ..get('/users/{id:int}', (ctx) async {})
      ..use((ctx, next) async => next());
    expect(app, isNotNull);
    expect(api, isNotNull);
  });
}
