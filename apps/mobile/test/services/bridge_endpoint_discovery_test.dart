import 'package:ccpocket/services/bridge_endpoint_discovery.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('selects a healthy fallback and preserves authentication', () async {
    final registry = Uri.parse('https://registry.example/discovery.json');
    final client = MockClient((request) async {
      if (request.url == registry) {
        return http.Response(
          '{"endpoints":["wss://backup.trycloudflare.com"]}',
          200,
        );
      }
      if (request.url.host == 'backup.trycloudflare.com') {
        return http.Response('{"status":"ok"}', 200);
      }
      return http.Response('', 503);
    });

    final result = await BridgeEndpointDiscovery.resolve(
      'wss://macbook-air-5.tail9af04f.ts.net?token=secret',
      client: client,
      registryUri: registry,
    );

    expect(result, 'wss://backup.trycloudflare.com?token=secret');
  });

  test('does not query discovery for unrelated bridges', () async {
    var requested = false;
    final client = MockClient((_) async {
      requested = true;
      return http.Response('', 500);
    });

    final result = await BridgeEndpointDiscovery.resolve(
      'wss://other.example.com?token=secret',
      client: client,
    );

    expect(result, 'wss://other.example.com?token=secret');
    expect(requested, isFalse);
  });

  test('never forwards authentication to an untrusted registry host', () async {
    final registry = Uri.parse('https://registry.example/discovery.json');
    final client = MockClient((request) async {
      if (request.url == registry) {
        return http.Response(
          '{"endpoints":["wss://attacker.example/collect"]}',
          200,
        );
      }
      expect(request.url.host, 'macbook-air-5.tail9af04f.ts.net');
      return http.Response('{"status":"ok"}', 200);
    });

    final result = await BridgeEndpointDiscovery.resolve(
      'wss://macbook-air-5.tail9af04f.ts.net?token=secret',
      client: client,
      registryUri: registry,
    );

    expect(result, 'wss://macbook-air-5.tail9af04f.ts.net?token=secret');
  });
}
