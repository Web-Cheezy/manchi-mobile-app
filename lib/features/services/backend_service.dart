import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:manchi_app/utils/user_facing_errors.dart';

class SessionExpiredException implements Exception {
  final String message;
  const SessionExpiredException([
    this.message = 'Your session may have expired. Please sign in again.',
  ]);

  @override
  String toString() => message;
}

class BackendService {
  static const _storage = FlutterSecureStorage();
  static const String _rawBaseUrl = String.fromEnvironment('MANCHI_BASE_URL');

  static String get _baseUrl {
    final trimmed = _rawBaseUrl.trim();
    if (trimmed.isEmpty) {
      throw StateError(
        'MANCHI_BASE_URL is not set. '
        'Pass --dart-define=MANCHI_BASE_URL=<url> when running or building.',
      );
    }
    final normalized =
        trimmed.endsWith('/') ? trimmed.substring(0, trimmed.length - 1) : trimmed;
    final uri = Uri.tryParse(normalized);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw StateError('MANCHI_BASE_URL is invalid: "$_rawBaseUrl"');
    }
    return normalized;
  }

  /// Validates compile-time API URL. Call once from [main] before [runApp].
  static void ensureConfigured() {
    _baseUrl;
  }

  /// Returns a user-friendly message; never exposes raw response body.
  static String _userMessage(int statusCode, String body, String fallback) {
    final fromBody = UserFacingErrors.messageFromResponseBody(statusCode, body);
    if (fromBody != null && fromBody.isNotEmpty) return fromBody;
    if (statusCode == 401) return 'Incorrect email or password. Please try again.';
    if (statusCode == 403) return 'You don\'t have permission to do that.';
    if (statusCode == 404) return 'We couldn\'t find that. Please try again.';
    if (statusCode == 422) return 'That email may already be in use. Try signing in or use a different email.';
    if (statusCode >= 500) return 'Our servers are busy. Please try again in a moment.';
    return fallback;
  }

  static Map<String, String> get _commonHeaders => {
        'Content-Type': 'application/json',
      };

  static const Map<String, String> _menuHeaders = {
        'Content-Type': 'application/json',
      };

  static Future<Map<String, String>> _getAuthHeaders() async {
    final token = await _storage.read(key: 'auth_token');
    return {
      ..._commonHeaders,
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<Map<String, String>> _requireAuthHeaders() async {
    final headers = await _getAuthHeaders();
    if (!headers.containsKey('Authorization')) {
      throw const SessionExpiredException();
    }
    return headers;
  }

  static Future<void> _handleAuthFailure(http.Response response) async {
    if (response.statusCode == 401 || response.statusCode == 403) {
      await signOut();
      throw const SessionExpiredException();
    }
  }

  static bool isSessionExpiredError(Object error) {
    if (error is SessionExpiredException) return true;
    final msg = error.toString().toLowerCase();
    return msg.contains('401') ||
        msg.contains('403') ||
        msg.contains('session may have expired') ||
        msg.contains('unauthorized') ||
        msg.contains('forbidden');
  }

  // --- Auth ---

  /// Sign up: create account with email + password and return a session (no email confirmation).
  static Future<Map<String, dynamic>> signUpWithPassword(
    String email,
    String password,
  ) async {
    final url = Uri.parse('$_baseUrl/api/auth/signup');
    final response = await http.post(
      url,
      headers: _commonHeaders,
      body: jsonEncode({'email': email, 'password': password}),
    );
    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = jsonDecode(response.body);
      if (data is Map && data['session'] != null) {
        final session = data['session'];
        if (session is Map && session['access_token'] != null) {
          await _storage.write(
            key: 'auth_token',
            value: session['access_token'].toString(),
          );
        }
      }
      return Map<String, dynamic>.from(data as Map);
    } else {
      throw Exception(_userMessage(
        response.statusCode,
        response.body,
        'We couldn\'t create your account. Please try again or use a different email.',
      ));
    }
  }

  static Future<void> _persistSessionFromAuthResponse(Map<String, dynamic> data) async {
    final session = data['session'];
    if (session is Map && session['access_token'] != null) {
      await _storage.write(
        key: 'auth_token',
        value: session['access_token'].toString(),
      );
    }
  }

  static Future<void> forgotPassword(String email) async {
    final url = Uri.parse('$_baseUrl/api/auth/forgot-password');
    final response = await http.post(
      url,
      headers: _commonHeaders,
      body: jsonEncode({'email': email.trim()}),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(_userMessage(
        response.statusCode,
        response.body,
        'We couldn\'t send a reset code. Please try again.',
      ));
    }
  }

  static Future<Map<String, dynamic>> resetPassword({
    required String email,
    required String token,
    required String password,
  }) async {
    final url = Uri.parse('$_baseUrl/api/auth/reset-password');
    final response = await http.post(
      url,
      headers: _commonHeaders,
      body: jsonEncode({
        'email': email.trim(),
        'token': token.trim(),
        'password': password,
      }),
    );
    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = jsonDecode(response.body);
      final map = data is Map<String, dynamic>
          ? data
          : Map<String, dynamic>.from(data as Map);
      await _persistSessionFromAuthResponse(map);
      return map;
    }
    throw Exception(_userMessage(
      response.statusCode,
      response.body,
      'We couldn\'t reset your password. Please check the code and try again.',
    ));
  }

  /// Sign in with email + password.
  static Future<Map<String, dynamic>> signInWithPassword(String email, String password) async {
    final url = Uri.parse('$_baseUrl/api/auth/login');
    final response = await http.post(
      url,
      headers: _commonHeaders,
      body: jsonEncode({'email': email, 'password': password}),
    );
    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = jsonDecode(response.body);
      if (data['session'] != null && data['session']['access_token'] != null) {
        await _storage.write(key: 'auth_token', value: data['session']['access_token']);
      }
      return data;
    } else {
      throw Exception(_userMessage(
        response.statusCode,
        response.body,
        'Incorrect email or password. Please try again.',
      ));
    }
  }

  static Future<void> sendOtp(String email) async {
    final url = Uri.parse('$_baseUrl/api/auth/otp');
    final response = await http.post(
      url,
      headers: _commonHeaders,
      body: jsonEncode({'email': email}),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(_userMessage(
        response.statusCode,
        response.body,
        'We couldn\'t send the code. Please check your email address and try again.',
      ));
    }
  }

  static Future<Map<String, dynamic>> verifyOtp(String email, String token) async {
    final url = Uri.parse('$_baseUrl/api/auth/verify');
    final response = await http.post(
      url,
      headers: _commonHeaders,
      body: jsonEncode({'email': email, 'token': token}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['session'] != null && data['session']['access_token'] != null) {
        await _storage.write(key: 'auth_token', value: data['session']['access_token']);
      }
      return data;
    } else {
      throw Exception(_userMessage(
        response.statusCode,
        response.body,
        'Invalid or expired code. Please try again or request a new code.',
      ));
    }
  }

  static Future<Map<String, dynamic>?> getCurrentUser() async {
    final url = Uri.parse('$_baseUrl/api/auth/user');
    final headers = await _getAuthHeaders();
    if (!headers.containsKey('Authorization')) return null; // No token

    final response = await http.get(url, headers: headers);
    await _handleAuthFailure(response);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data is Map<String, dynamic>) {
        if (data.containsKey('user') && data['user'] is Map) {
          return data['user'];
        }
        if (data.containsKey('data')) {
           final inner = data['data'];
           if (inner is Map && inner.containsKey('user')) {
             return inner['user'];
           }
           if (inner is Map) return inner as Map<String, dynamic>;
        }
      }
      return data;
    }
    return null;
  }

  static Future<void> signOut() async {
    try {
      final headers = await _getAuthHeaders();
      if (headers.containsKey('Authorization')) {
        await http.post(
          Uri.parse('$_baseUrl/api/auth/signout'),
          headers: headers,
        );
      }
    } catch (_) {}
    await _storage.delete(key: 'auth_token');
  }

  static Future<void> unregisterFcmToken(String fcmToken) async {
    try {
      final headers = await _getAuthHeaders();
      if (!headers.containsKey('Authorization')) return;
      await http.post(
        Uri.parse('$_baseUrl/api/fcm/unregister'),
        headers: headers,
        body: jsonEncode({'fcm_token': fcmToken}),
      );
    } catch (_) {}
  }

  static Future<void> deleteAccount({String? reason}) async {
    final url = Uri.parse('$_baseUrl/api/account/delete');
    final headers = await _requireAuthHeaders();
    final response = await http.post(
      url,
      headers: headers,
      body: jsonEncode({
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      }),
    );
    await _handleAuthFailure(response);

    if (response.statusCode == 200 ||
        response.statusCode == 201 ||
        response.statusCode == 204) {
      return;
    }

    throw Exception(_userMessage(
      response.statusCode,
      response.body,
      'We couldn\'t delete your account right now. Please try again.',
    ));
  }

  // --- Profile ---

  static Future<Map<String, dynamic>?> getProfile(String userId) async {
    final url = Uri.parse('$_baseUrl/api/profile?userId=$userId');
    final headers = await _requireAuthHeaders();
    final response = await http.get(url, headers: headers);
    await _handleAuthFailure(response);
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      
      // Handle list response
      if (data is List && data.isNotEmpty) return data.first;
      
      // Handle map response
      if (data is Map<String, dynamic>) {
        if (data.containsKey('data')) {
           final inner = data['data'];
           if (inner is List && inner.isNotEmpty) return inner.first;
           if (inner is Map<String, dynamic>) return inner;
        }
        return data;
      }
      return null;
    }
    return null;
  }

  static Future<void> upsertProfile({
    required String id,
    required String fullName,
    required String phoneNumber,
  }) async {
    final url = Uri.parse('$_baseUrl/api/profile');
    final headers = await _requireAuthHeaders();
    final response = await http.post(
      url,
      headers: headers,
      body: jsonEncode({
        'id': id,
        'full_name': fullName,
        'phone_number': phoneNumber,
      }),
    );
    await _handleAuthFailure(response);

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(_userMessage(
        response.statusCode,
        response.body,
        'We couldn\'t save your details. Please try again.',
      ));
    }
  }

  // --- Menu ---

  static Map<String, String> _menuQueryParams({
    String? storeCode,
    String? stateName,
    int? categoryId,
  }) {
    return {
      if (storeCode != null && storeCode.isNotEmpty) 'store': storeCode,
      if (storeCode != null && storeCode.isNotEmpty) 'location': storeCode,
      if (stateName != null && stateName.isNotEmpty) 'state': stateName,
      if (categoryId != null) 'categoryId': '$categoryId',
    };
  }

  static List<dynamic> _extractListPayload(dynamic data) {
    if (data is List) return data;
    if (data is Map) {
      const keys = ['data', 'categories', 'foods', 'sides', 'items', 'results'];
      for (final key in keys) {
        final value = data[key];
        if (value is List) return value;
      }
    }
    return [];
  }

  static Map<String, dynamic>? _extractMapPayload(dynamic data) {
    if (data is Map) {
      final map = data is Map<String, dynamic>
          ? data
          : Map<String, dynamic>.from(data);
      const listKeys = ['foods', 'data', 'items', 'results'];
      for (final key in listKeys) {
        final value = map[key];
        if (value is List && value.isNotEmpty && value.first is Map) {
          return Map<String, dynamic>.from(value.first as Map);
        }
      }
      const mapKeys = ['food', 'item', 'result'];
      for (final key in mapKeys) {
        final value = map[key];
        if (value is Map) return Map<String, dynamic>.from(value);
      }
      return map;
    }
    return null;
  }

  static Future<List<dynamic>> getCategories({
    String? storeCode,
    String? stateName,
  }) async {
    final url = Uri.parse('$_baseUrl/api/categories').replace(
      queryParameters: _menuQueryParams(
        storeCode: storeCode,
        stateName: stateName,
      ),
    );
    final response = await http.get(url, headers: _menuHeaders);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return _extractListPayload(data);
    }
    return [];
  }

  static Future<List<dynamic>> getFoods({
    String? storeCode,
    String? stateName,
    int? categoryId,
  }) async {
    final url = Uri.parse('$_baseUrl/api/foods').replace(
      queryParameters: _menuQueryParams(
        storeCode: storeCode,
        stateName: stateName,
        categoryId: categoryId,
      ),
    );
    final response = await http.get(url, headers: _menuHeaders);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return _extractListPayload(data);
    }
    return [];
  }

  static Future<Map<String, dynamic>> getFoodDetail(
    int id, {
    String? storeCode,
    String? stateName,
  }) async {
    final url = Uri.parse('$_baseUrl/api/foods').replace(
      queryParameters: {
        'id': '$id',
        ..._menuQueryParams(
          storeCode: storeCode,
          stateName: stateName,
        ),
      },
    );
    final response = await http.get(url, headers: _menuHeaders);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data is List && data.isNotEmpty) return data.first;
      final payload = _extractMapPayload(data);
      if (payload != null) return payload;
    }
    throw Exception('We couldn\'t load this item. Please try again.');
  }

  static Future<Map<String, dynamic>?> getMenu({
    String? storeCode,
    String? stateName,
  }) async {
    final url = Uri.parse('$_baseUrl/api/menu').replace(
      queryParameters: _menuQueryParams(
        storeCode: storeCode,
        stateName: stateName,
      ),
    );
    final response = await http.get(url, headers: _menuHeaders);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data is Map<String, dynamic>) return data;
      if (data is Map) return Map<String, dynamic>.from(data);
    }
    return null;
  }

  static Future<List<dynamic>> getSides({
    String? storeCode,
    String? stateName,
  }) async {
    final url = Uri.parse('$_baseUrl/api/sides').replace(
      queryParameters: _menuQueryParams(
        storeCode: storeCode,
        stateName: stateName,
      ),
    );
    final response = await http.get(url, headers: _menuHeaders);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return _extractListPayload(data);
    }
    return [];
  }

  // --- Orders ---

  static Future<Map<String, dynamic>> createOrder({
    required double totalAmount,
    required double vat,
    required String deliveryAddress,
    required String? location,
    required String? deliveryLga,
    required List<Map<String, dynamic>> items,
    required String deliveryMethod,
    String? orderNote,
  }) async {
    final url = Uri.parse('$_baseUrl/api/orders');
    final headers = await _requireAuthHeaders();
    final body = <String, dynamic>{
      'total_amount': totalAmount,
      'vat': vat,
      'delivery_address': deliveryAddress,
      'location': location,
      'items': items,
      'delivery_method': deliveryMethod,
    };
    if (deliveryLga != null && deliveryLga.trim().isNotEmpty) {
      body['delivery_lga'] = deliveryLga.trim();
    }
    final trimmedNote = orderNote?.trim();
    if (trimmedNote != null && trimmedNote.isNotEmpty) {
      body['order_note'] = trimmedNote.length > 500
          ? trimmedNote.substring(0, 500)
          : trimmedNote;
    }
    final response = await http.post(
      url,
      headers: headers,
      body: jsonEncode(body),
    );
    await _handleAuthFailure(response);

    if (response.statusCode == 200 || response.statusCode == 201) {
      final body = jsonDecode(response.body);
      // If backend returns a list (e.g., from a Supabase insert), return the first item
      if (body is List && body.isNotEmpty) {
        return body.first;
      }
      return body;
    } else {
      throw Exception(_userMessage(
        response.statusCode,
        response.body,
        'We couldn\'t place your order. Please try again.',
      ));
    }
  }

  static Future<List<dynamic>> getOrders() async {
    final url = Uri.parse('$_baseUrl/api/orders');
    final headers = await _requireAuthHeaders();
    final response = await http.get(url, headers: headers);
    await _handleAuthFailure(response);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data is List) return data;
      if (data is Map<String, dynamic>) {
        if (data.containsKey('data')) {
          final inner = data['data'];
          if (inner is List) return inner;
          if (inner is Map && inner.containsKey('orders') && inner['orders'] is List) {
            return inner['orders'] as List<dynamic>;
          }
        }
        if (data.containsKey('orders') && data['orders'] is List) {
          return data['orders'] as List<dynamic>;
        }
      }
      return [];
    }
    return [];
  }

  static Future<Map<String, dynamic>> getOrderById(String orderId) async {
    final url = Uri.parse('$_baseUrl/api/orders/$orderId');
    final headers = await _requireAuthHeaders();
    final response = await http.get(url, headers: headers);
    await _handleAuthFailure(response);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data is Map<String, dynamic>) return data;
      if (data is Map) return Map<String, dynamic>.from(data);
    }
    throw Exception('We couldn\'t load this order. Please try again.');
  }

  // --- Transport (LGA fare configuration) ---

  /// Fetches admin-configured delivery price (transport cost) for a given LGA.
  /// If the backend route is not implemented yet, this returns `null` and
  /// the UI can fall back to any local pricing logic.
  static Future<int?> getTransportPriceForLga(String lga) async {
    final safeLga = lga.trim();
    if (safeLga.isEmpty) return null;

    int? parsePrice(dynamic json) {
      if (json == null) return null;

      // Direct number
      if (json is num) return json.toInt();

      // Map response
      if (json is Map) {
        final raw = json['price'] ?? json['transport_cost'] ?? json['transportCost'];
        if (raw is num) return raw.toInt();
        return int.tryParse(raw?.toString() ?? '');
      }

      // List response
      if (json is List && json.isNotEmpty) {
        return parsePrice(json.first);
      }

      // Envelope responses
      if (json is Map<String, dynamic>) {
        if (json['data'] != null) return parsePrice(json['data']);
        if (json['transport_prices'] != null) return parsePrice(json['transport_prices']);
        if (json['transportPrice'] != null) return parsePrice(json['transportPrice']);
      }

      return null;
    }

    // Try a couple of common endpoint shapes; your backend can settle on one later.
    final endpoints = [
      Uri.parse('$_baseUrl/api/transport_prices?lga=$safeLga'),
      Uri.parse('$_baseUrl/api/transport_prices/$safeLga'),
    ];

    for (final url in endpoints) {
      try {
        final response = await http.get(url, headers: _commonHeaders);
        if (response.statusCode != 200) continue;
        final data = jsonDecode(response.body);
        final price = parsePrice(data);
        if (price != null) return price;
      } catch (_) {}
    }

    return null;
  }

  // --- Payments ---

  static int? _parseOrderId(dynamic raw) {
    if (raw == null) return null;
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw.toString());
  }

  static int? orderIdFromResponse(Map<String, dynamic> response) {
    final direct = _parseOrderId(response['order_id'] ?? response['orderId']);
    if (direct != null) return direct;
    if (response['data'] is Map) {
      final data = response['data'] as Map;
      return _parseOrderId(data['order_id'] ?? data['orderId'] ?? data['id']);
    }
    return _parseOrderId(response['id']);
  }

  static Future<Map<String, dynamic>> initializeTransaction({
    required String email,
    required double amount,
    required String location,
    required String orderId,
  }) async {
    final int amountInKobo = (amount * 100).round();
    final url = Uri.parse('$_baseUrl/api/paystack/initialize');
    final headers = await _requireAuthHeaders();
    final response = await http.post(
      url,
      headers: headers,
      body: jsonEncode({
        'email': email,
        'amount': amountInKobo,
        'location': location,
        'metadata': {'orderId': orderId},
      }),
    );
    await _handleAuthFailure(response);

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      throw Exception(_userMessage(
        response.statusCode,
        response.body,
        'We couldn\'t start the payment. Please try again.',
      ));
    }
  }

  static Future<Map<String, dynamic>> verifyTransaction(String reference) async {
    final url = Uri.parse('$_baseUrl/api/paystack/verify?reference=$reference');
    final headers = await _requireAuthHeaders();
    final response = await http.get(url, headers: headers);
    await _handleAuthFailure(response);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception(_userMessage(
        response.statusCode,
        response.body,
        'We couldn\'t confirm your payment. Please check your order history or try again.',
      ));
    }
  }

  // --- Addresses ---

  static Future<List<dynamic>> getAddresses() async {
    final url = Uri.parse('$_baseUrl/api/addresses');
    final headers = await _requireAuthHeaders();
    final response = await http.get(url, headers: headers);
    await _handleAuthFailure(response);
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data is List) return data;
      if (data is Map && data.containsKey('data') && data['data'] is List) return data['data'];
      return [];
    }
    return [];
  }

  static Future<Map<String, dynamic>> saveAddress(Map<String, dynamic> addressData, String userId) async {
    final url = Uri.parse('$_baseUrl/api/addresses');
    final headers = await _requireAuthHeaders();
    final response = await http.post(
      url,
      headers: headers,
      body: jsonEncode({
        ...addressData,
        'user_id': userId, // snake_case
        'userId': userId, // camelCase
      }),
    );
    await _handleAuthFailure(response);

    if (response.statusCode == 200 || response.statusCode == 201) {
      final body = jsonDecode(response.body);
      if (body is List && body.isNotEmpty) return body.first;
      if (body is Map<String, dynamic>) {
        if (body.containsKey('data') && body['data'] is Map) return body['data'];
        return body;
      }
      return body;
    } else {
      throw Exception(_userMessage(
        response.statusCode,
        response.body,
        'We couldn\'t save your address. Please try again.',
      ));
    }
  }

  static Future<void> updateAddress(String addressId, Map<String, dynamic> addressData) async {
    final url = Uri.parse('$_baseUrl/api/addresses/$addressId');
    // Using PUT or PATCH depending on your API preference, usually PUT for full update
    final response = await http.put(
      url,
      headers: await _requireAuthHeaders(),
      body: jsonEncode(addressData),
    );
    await _handleAuthFailure(response);

    if (response.statusCode != 200) {
      throw Exception(_userMessage(
        response.statusCode,
        response.body,
        'We couldn\'t update your address. Please try again.',
      ));
    }
  }

  static Future<void> deleteAddress(String addressId) async {
    final url = Uri.parse('$_baseUrl/api/addresses/$addressId');
    final response = await http.delete(url, headers: await _requireAuthHeaders());
    await _handleAuthFailure(response);

    if (response.statusCode != 200) {
      throw Exception(_userMessage(
        response.statusCode,
        response.body,
        'We couldn\'t remove that address. Please try again.',
      ));
    }
  }

  // --- FCM (push notifications) ---

  /// Register FCM token for this user so backend can send order/status/admin notifications.
  static Future<void> registerFcmToken({
    required String fcmToken,
    required String platform,
    String? deviceId,
    String? appVersion,
  }) async {
    final url = Uri.parse('$_baseUrl/api/fcm/register');
    final body = <String, dynamic>{
      'fcm_token': fcmToken,
      'platform': platform,
      if (deviceId != null && deviceId.isNotEmpty) 'device_id': deviceId,
      if (appVersion != null && appVersion.isNotEmpty) 'app_version': appVersion,
    };
    final response = await http.post(
      url,
      headers: await _requireAuthHeaders(),
      body: jsonEncode(body),
    );
    await _handleAuthFailure(response);
    if (response.statusCode != 200 && response.statusCode != 201) {
      if (kDebugMode) {
        debugPrint(
          'FCM token registration failed with status ${response.statusCode}',
        );
      }
    }
  }

  // --- Notifications (backend-stored list; backend saves when sending FCM) ---

  /// Fetch notifications for the current user from the backend.
  /// Returns empty list if not authenticated or API not implemented.
  static Future<List<Map<String, dynamic>>> getNotifications() async {
    final headers = await _getAuthHeaders();
    if (!headers.containsKey('Authorization')) return []; // No token

    final url = Uri.parse('$_baseUrl/api/notifications');
    final response = await http.get(url, headers: headers);
    await _handleAuthFailure(response);
    if (response.statusCode != 200) return [];

    final data = jsonDecode(response.body);
    if (data is List) {
      return List<Map<String, dynamic>>.from(
          data.map((e) => e as Map<String, dynamic>));
    }
    if (data is Map<String, dynamic>) {
      if (data.containsKey('data')) {
        final inner = data['data'];
        if (inner is List) {
          return List<Map<String, dynamic>>.from(
              inner.map((e) => e as Map<String, dynamic>));
        }
        if (inner is Map && inner.containsKey('notifications') && inner['notifications'] is List) {
          return List<Map<String, dynamic>>.from(
              (inner['notifications'] as List).map((e) => e as Map<String, dynamic>));
        }
      }
      final list = data['notifications'] ?? data['data'];
      if (list is List) {
        return List<Map<String, dynamic>>.from(
            list.map((e) => e as Map<String, dynamic>));
      }
    }
    return [];
  }

  /// Mark a notification as read. Backend can use PATCH /api/notifications/:id with { "is_read": true }.
  static Future<bool> markNotificationRead(String notificationId) async {
    final headers = await _getAuthHeaders();
    if (!headers.containsKey('Authorization')) return false;

    final url = Uri.parse('$_baseUrl/api/notifications/$notificationId');
    final response = await http.patch(
      url,
      headers: headers,
      body: jsonEncode({'is_read': true}),
    );
    await _handleAuthFailure(response);
    return response.statusCode == 200 || response.statusCode == 204;
  }

  /// Optional: clear all notifications for the current user (if backend supports it).
  static Future<bool> clearNotifications() async {
    final headers = await _getAuthHeaders();
    if (!headers.containsKey('Authorization')) return false;

    final url = Uri.parse('$_baseUrl/api/notifications/clear');
    final response = await http.post(url, headers: headers);
    await _handleAuthFailure(response);
    return response.statusCode == 200 || response.statusCode == 204;
  }
}
