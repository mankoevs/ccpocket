import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class BridgeEndpointDiscovery {
  static const _registryUrl =
      'https://gist.githubusercontent.com/mankoevs/'
      'd8154455bb0fa966be69102c571532c6/raw/ccpocket-bridge.json';

  static bool manages(String wsUrl) {
    final host = Uri.tryParse(wsUrl)?.host.toLowerCase();
    return host == 'macbook-air-5.tail9af04f.ts.net' ||
        host?.endsWith('.trycloudflare.com') == true;
  }

  static Future<String> resolve(
    String savedUrl, {
    http.Client? client,
    Uri? registryUri,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    if (!manages(savedUrl)) return savedUrl;

    final ownClient = client == null;
    final httpClient = client ?? http.Client();
    try {
      final registry =
          registryUri ??
          Uri.parse(_registryUrl).replace(
            queryParameters: {
              't': DateTime.now().millisecondsSinceEpoch.toString(),
            },
          );
      final response = await httpClient.get(registry).timeout(timeout);
      if (response.statusCode != 200) return savedUrl;

      final payload = jsonDecode(response.body);
      if (payload is! Map<String, dynamic>) return savedUrl;
      final rawEndpoints = payload['endpoints'];
      if (rawEndpoints is! List) return savedUrl;

      final savedUri = Uri.tryParse(savedUrl);
      if (savedUri == null) return savedUrl;
      final candidates = <String>[savedUrl];
      for (final value in rawEndpoints.whereType<String>()) {
        final uri = Uri.tryParse(value);
        if (uri == null ||
            uri.scheme != 'wss' ||
            uri.host.isEmpty ||
            !manages(value)) {
          continue;
        }
        final candidate = uri.replace(
          queryParameters: savedUri.queryParameters,
        );
        if (!candidates.contains(candidate.toString())) {
          candidates.add(candidate.toString());
        }
      }
      return await _firstHealthy(candidates, httpClient, timeout) ?? savedUrl;
    } catch (_) {
      return savedUrl;
    } finally {
      if (ownClient) httpClient.close();
    }
  }

  static Future<String?> _firstHealthy(
    List<String> candidates,
    http.Client client,
    Duration timeout,
  ) {
    final result = Completer<String?>();
    var remaining = candidates.length;
    for (final candidate in candidates) {
      () async {
        try {
          final wsUri = Uri.parse(candidate);
          final healthUri = wsUri.replace(
            scheme: 'https',
            path: '/health',
            queryParameters: const {},
          );
          final response = await client.get(healthUri).timeout(timeout);
          if (response.statusCode == 200 && !result.isCompleted) {
            result.complete(candidate);
          }
        } catch (_) {
          // Try the remaining public route.
        } finally {
          remaining--;
          if (remaining == 0 && !result.isCompleted) result.complete(null);
        }
      }();
    }
    return result.future;
  }
}
