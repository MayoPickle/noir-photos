import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'secure_store.dart';

class ApiException implements Exception {
  ApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class ApiClient {
  ApiClient({
    required this.baseUrl,
    required SecureStore store,
    http.Client? httpClient,
  })  : _store = store,
        _http = httpClient ?? http.Client();

  final String baseUrl;
  final SecureStore _store;
  final http.Client _http;

  Future<Map<String, String>> _headers({bool auth = true}) async {
    final headers = <String, String>{'content-type': 'application/json'};
    if (auth) {
      final token = await _store.readToken();
      if (token != null) headers['authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  Future<dynamic> _decode(http.Response response) async {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      return jsonDecode(response.body);
    }
    var message = response.reasonPhrase ?? 'Request failed';
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      message = body['detail']?.toString() ?? message;
    } catch (_) {}
    throw ApiException(response.statusCode, message);
  }

  Future<void> startOtp(String email, String purpose) async {
    await _decode(
      await _http.post(
        _uri('/auth/otp/start'),
        headers: await _headers(auth: false),
        body: jsonEncode({'email': email, 'purpose': purpose}),
      ),
    );
  }

  Future<Map<String, dynamic>> register({
    required String email,
    required String otp,
    required String publicKey,
    required Map<String, dynamic> keyBundle,
    required Map<String, dynamic> device,
  }) async {
    return await _decode(
      await _http.post(
        _uri('/auth/register'),
        headers: await _headers(auth: false),
        body: jsonEncode({
          'email': email,
          'otp': otp,
          'public_key': publicKey,
          'key_bundle': keyBundle,
          'device': device,
        }),
      ),
    ) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> login({
    required String email,
    required String otp,
    required Map<String, dynamic> device,
  }) async {
    return await _decode(
      await _http.post(
        _uri('/auth/login/verify'),
        headers: await _headers(auth: false),
        body: jsonEncode({'email': email, 'otp': otp, 'device': device}),
      ),
    ) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> me() async {
    return await _decode(
            await _http.get(_uri('/account/me'), headers: await _headers()))
        as Map<String, dynamic>;
  }

  Future<void> changePassword(Map<String, dynamic> keyBundle) async {
    await _decode(
      await _http.post(
        _uri('/account/password/change'),
        headers: await _headers(),
        body: jsonEncode({'key_bundle': keyBundle}),
      ),
    );
  }

  Future<void> deleteAccount() async {
    await _decode(
        await _http.delete(_uri('/account'), headers: await _headers()));
  }

  Future<List<dynamic>> collections() async {
    return await _decode(
            await _http.get(_uri('/collections'), headers: await _headers()))
        as List<dynamic>;
  }

  Future<Map<String, dynamic>> createCollection(
      Map<String, dynamic> body) async {
    return await _decode(
      await _http.post(_uri('/collections'),
          headers: await _headers(), body: jsonEncode(body)),
    ) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> lookupRecipient(String email) async {
    return await _decode(
      await _http.get(_uri('/sharing/lookup', {'email': email}),
          headers: await _headers()),
    ) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> shareCollection(
      String collectionId, Map<String, dynamic> body) async {
    return await _decode(
      await _http.post(
        _uri('/collections/$collectionId/share'),
        headers: await _headers(),
        body: jsonEncode(body),
      ),
    ) as Map<String, dynamic>;
  }

  Future<List<dynamic>> files(String collectionId) async {
    return await _decode(
      await _http.get(_uri('/files', {'collection_id': collectionId}),
          headers: await _headers()),
    ) as List<dynamic>;
  }

  Future<Map<String, dynamic>> uploadSession({
    required String collectionId,
    required String objectType,
    required int sizeBytes,
    String? checksum,
  }) async {
    return await _decode(
      await _http.post(
        _uri('/files/upload-session'),
        headers: await _headers(),
        body: jsonEncode({
          'collection_id': collectionId,
          'object_type': objectType,
          'size_bytes': sizeBytes,
          'checksum': checksum,
        }),
      ),
    ) as Map<String, dynamic>;
  }

  Future<void> putEncryptedObject({
    required String uploadUrl,
    required Uint8List bytes,
    required Map<String, String> headers,
  }) async {
    final response =
        await _http.put(Uri.parse(uploadUrl), headers: headers, body: bytes);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, 'Object upload failed');
    }
  }

  Future<Map<String, dynamic>> commitFile(Map<String, dynamic> body) async {
    return await _decode(
      await _http.post(_uri('/files/commit'),
          headers: await _headers(), body: jsonEncode(body)),
    ) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> downloadFile(String fileId) async {
    return await _decode(
      await _http.get(_uri('/files/$fileId/download-url'),
          headers: await _headers()),
    ) as Map<String, dynamic>;
  }

  Future<Uint8List> getEncryptedObject(String downloadUrl) async {
    final response = await _http.get(Uri.parse(downloadUrl));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, 'Object download failed');
    }
    return response.bodyBytes;
  }

  Future<List<dynamic>> searchIndexes(
      {String? collectionId, String? modelVersion}) async {
    return await _decode(
      await _http.get(
        _uri('/search-index', {
          if (collectionId != null) 'collection_id': collectionId,
          if (modelVersion != null) 'model_version': modelVersion,
        }),
        headers: await _headers(),
      ),
    ) as List<dynamic>;
  }

  Future<Map<String, dynamic>> upsertSearchIndex(
      Map<String, dynamic> body) async {
    return await _decode(
      await _http.put(_uri('/search-index'),
          headers: await _headers(), body: jsonEncode(body)),
    ) as Map<String, dynamic>;
  }

  Future<void> deleteSearchIndex(
      {required String fileId, required String modelVersion}) async {
    await _decode(
      await _http.delete(
        _uri('/search-index/$fileId', {'model_version': modelVersion}),
        headers: await _headers(),
      ),
    );
  }

  Future<Map<String, dynamic>> sync(int cursor) async {
    return await _decode(
      await _http.get(_uri('/sync', {'cursor': cursor.toString()}),
          headers: await _headers()),
    ) as Map<String, dynamic>;
  }
}
