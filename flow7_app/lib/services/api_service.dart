import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../main.dart'; // backendBaseUrl değişkeninin burada tanımlandığı varsayılıyor.


class ApiException implements Exception {
  final String message;
  final int statusCode;

  ApiException(this.message, this.statusCode);

  @override
  String toString() => message; // Kullanıcı arayüzünde doğrudan gösterilebilir.
}

class QuizLimitException implements Exception {
  final String message;
  QuizLimitException(this.message);
  @override
  String toString() => message;
}

class ChallengeLimitException implements Exception {
  final String message;
  ChallengeLimitException(this.message);
  @override
  String toString() => message;
}


class ApiService {
  Map<String, String> _getAuthHeaders(String idToken) {
    return {
      'Content-Type': 'application/json; charset=UTF-8',
      'Authorization': 'Bearer $idToken',
    };
  }
  
  dynamic _handleResponse(http.Response response) {
    final String responseBody = utf8.decode(response.bodyBytes);
    
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.statusCode == 204) { // 204 No Content durumunda gövde boş olur.
        return null;
      }
      return jsonDecode(responseBody);
    } else {
      String errorMessage = "Bir hata oluştu.";
      if (responseBody.isNotEmpty) {
        try {
          final errorJson = jsonDecode(responseBody);
          errorMessage = errorJson['detail'] ?? errorMessage;
        } catch (e) {
          errorMessage = responseBody;
        }
      }
      throw ApiException(errorMessage, response.statusCode);
    }
  }


  Future<List<Map<String, dynamic>>> getUserPlans(String idToken, DateTime start, DateTime end) async {
    final df = DateFormat('yyyy-MM-dd');
    final uri = Uri.parse("$backendBaseUrl/api/plans")
        .replace(queryParameters: {'start_date': df.format(start), 'end_date': df.format(end)});
    
    final response = await http.get(uri, headers: _getAuthHeaders(idToken));
    final decoded = _handleResponse(response);
    
    return List<Map<String, dynamic>>.from(decoded);
  }

  Future<Map<String, dynamic>> createPlan(String idToken, Map<String, dynamic> payload) async {
    final uri = Uri.parse("$backendBaseUrl/api/plans");
    
    final response = await http.post(
      uri,
      headers: _getAuthHeaders(idToken),
      body: jsonEncode(payload),
    );

    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> updatePlan(String idToken, String planId, Map<String, dynamic> payload) async {
    final uri = Uri.parse("$backendBaseUrl/api/plans/$planId");

    final response = await http.put(
      uri,
      headers: _getAuthHeaders(idToken),
      body: jsonEncode(payload),
    );

    return _handleResponse(response);
  }

  Future<void> deletePlan(String idToken, String planId) async {
    final uri = Uri.parse("$backendBaseUrl/api/plans/$planId");
    
    final response = await http.delete(uri, headers: _getAuthHeaders(idToken));
    
    _handleResponse(response);
  }
  

  Future<Map<String, dynamic>> updateSubscription(String idToken, String level, int days) async {
    final uri = Uri.parse("$backendBaseUrl/user/subscription/");
    final payload = jsonEncode({'level': level, 'days': days});

    final response = await http.put(
      uri,
      headers: _getAuthHeaders(idToken),
      body: payload,
    );

    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> updateThemePreference(String idToken, String theme) async {
    final uri = Uri.parse("$backendBaseUrl/user/theme/");
    final payload = jsonEncode({'theme': theme.toUpperCase()}); 

    final response = await http.put(
      uri,
      headers: _getAuthHeaders(idToken),
      body: payload,
    );

    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> getUserProfile(String idToken) async {
    final uri = Uri.parse("$backendBaseUrl/user/profile/");
    final response = await http.get(uri, headers: _getAuthHeaders(idToken));
    return _handleResponse(response);
  }

  Future<Map<String, String>> getTopics() async {
    final uri = Uri.parse("$backendBaseUrl/topics/");
    final response = await http.get(uri);
    final data = _handleResponse(response);
    return Map<String, String>.from(data);
  }

  Future<List<String>> getUserTopics(String idToken) async {
     final uri = Uri.parse("$backendBaseUrl/user/topics/");
     final response = await http.get(uri, headers: _getAuthHeaders(idToken));
     final data = _handleResponse(response);
     return List<String>.from(data);
  }

  Future<void> setUserTopics(String idToken, List<String> topics) async {
     final uri = Uri.parse("$backendBaseUrl/user/topics/");
     final response = await http.put(
       uri,
       headers: _getAuthHeaders(idToken),
       body: jsonEncode(topics),
     );
     _handleResponse(response);
  }
  
  Future<List<Map<String, dynamic>>> getQuizQuestions(String idToken, {int limit = 3, String? lang, bool preview = false}) async {
    final uri = Uri.parse("$backendBaseUrl/quiz/?limit=$limit${lang != null ? '&lang=$lang' : ''}${preview ? '&preview=true' : ''}");
    final response = await http.get(uri, headers: _getAuthHeaders(idToken));
    if (response.statusCode == 429) {
      throw QuizLimitException(utf8.decode(response.bodyBytes));
    }
    final data = _handleResponse(response);
    return List<Map<String, dynamic>>.from(data);
  }

  Future<void> updateLanguage(String idToken, String languageCode) async {
    final uri = Uri.parse("$backendBaseUrl/user/language/");
    final response = await http.put(
      uri,
      headers: _getAuthHeaders(idToken),
      body: jsonEncode({'language_code': languageCode}),
    );
    _handleResponse(response);
  }

  Future<void> updateNotificationSetting(String idToken, bool enabled) async {
    final uri = Uri.parse("$backendBaseUrl/user/notifications/");
    final response = await http.put(
      uri,
      headers: _getAuthHeaders(idToken),
      body: jsonEncode({'enabled': enabled}),
    );
    _handleResponse(response);
  }

  // Device token management
  Future<void> registerDeviceToken(String idToken, String token, {String provider = 'fcm'}) async {
    final uri = Uri.parse("$backendBaseUrl/user/device_tokens/");
    final response = await http.post(uri, headers: _getAuthHeaders(idToken), body: jsonEncode({'token': token, 'provider': provider}));
    _handleResponse(response);
  }

  Future<List<String>> getUserDeviceTokens(String idToken) async {
    final uri = Uri.parse("$backendBaseUrl/user/device_tokens/");
    final response = await http.get(uri, headers: _getAuthHeaders(idToken));
    final data = _handleResponse(response);
    return List<String>.from(data.map((e) => e['token']));
  }

  Future<void> deleteDeviceToken(String idToken, String token) async {
    final uri = Uri.parse("$backendBaseUrl/user/device_tokens/${Uri.encodeComponent(token)}");
    final response = await http.delete(uri, headers: _getAuthHeaders(idToken));
    _handleResponse(response);
  }
}
