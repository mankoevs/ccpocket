import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/logger.dart';

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
      final response = await httpClient
          .get(
            registry,
            headers: const {
              'Accept': 'application/vnd.github+json',
              'User-Agent': 'CC-Pocket',
            },
          )
          .timeout(timeout);
      if (response.statusCode != 200) {
        logger.warning(
          '[bridge-discovery] Registry returned ${response.statusCode}',
        );
        return savedUrl;
      }

      final responsePayload = jsonDecode(response.body);
      final payload = _readDiscoveryPayload(responsePayload);
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
        final candidate = savedUri.hasQuery
            ? uri.replace(queryParameters: savedUri.queryParameters)
            : uri;
        if (!candidates.contains(candidate.toString())) {
          candidates.add(candidate.toString());
        }
      }
      return await _firstHealthy(candidates, httpClient, timeout) ?? savedUrl;
    } catch (error) {
      logger.warning('[bridge-discovery] Registry lookup failed', error);
      return savedUrl;
    } finally {
      if (ownClient) httpClient.close();
    }
  }

  static Future<String> resolveHttpBaseUrl(
    String savedHttpBaseUrl, {
    http.Client? client,
    Uri? registryUri,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final uri = Uri.tryParse(savedHttpBaseUrl);
    if (uri == null) return savedHttpBaseUrl;

    final wsUrl = uri
        .replace(scheme: uri.scheme == 'https' ? 'wss' : 'ws')
        .toString();
    final resolvedWsUrl = await resolve(
      wsUrl,
      client: client,
      registryUri: registryUri,
      timeout: timeout,
    );
    final resolvedUri = Uri.tryParse(resolvedWsUrl);
    if (resolvedUri == null) return savedHttpBaseUrl;

    return Uri(
      scheme: resolvedUri.scheme == 'wss' ? 'https' : 'http',
      host: resolvedUri.host,
      port: resolvedUri.hasPort ? resolvedUri.port : null,
      path: resolvedUri.path,
    ).toString();
  }

  static dynamic _readDiscoveryPayload(dynamic responsePayload) {
    if (responsePayload is! Map<String, dynamic>) return null;
    final files = responsePayload['files'];
    if (files is Map<String, dynamic>) {
      final file = files['ccpocket-bridge.json'];
      if (file is! Map<String, dynamic>) return null;
      final content = file['content'];
      if (content is! String) return null;
      return jsonDecode(content);
    }
    return responsePayload;
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
          final healthUri = Uri(
            scheme: 'https',
            host: wsUri.host,
            port: wsUri.hasPort ? wsUri.port : null,
            path: '/health',
          );
          final response = await client.get(healthUri).timeout(timeout);
          logger.info(
            '[bridge-discovery] Health ${wsUri.host}: ${response.statusCode}',
          );
          if (response.statusCode == 200 && !result.isCompleted) {
            result.complete(candidate);
          }
        } catch (error) {
          logger.warning(
            '[bridge-discovery] Health ${Uri.parse(candidate).host} failed',
            error,
          );
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
