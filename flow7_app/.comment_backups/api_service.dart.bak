import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../main.dart'; // backendBaseUrl değişkeninin burada tanımlandığı varsayılıyor.

// --- ÖZEL HATA SINIFLARI ---

/// API'den gelen hataları (4xx, 5xx) temsil etmek için standart bir exception sınıfı.
/// Sunucunun döndürdüğü 'detail' mesajını içerir.
class ApiException implements Exception {
  final String message;
  final int statusCode;

  ApiException(this.message, this.statusCode);

  @override
  String toString() => message; // Kullanıcı arayüzünde doğrudan gösterilebilir.
}

/// Quiz limitine ulaşıldığında fırlatılır.
class QuizLimitException implements Exception {
  final String message;
  QuizLimitException(this.message);
  @override
  String toString() => message;
}

/// Meydan okuma (challenge) limitine ulaşıldığında fırlatılır.
class ChallengeLimitException implements Exception {
  final String message;
  ChallengeLimitException(this.message);
  @override
  String toString() => message;
}


class ApiService {
  /// Her istek için standart yetkilendirme başlıklarını oluşturur.
  Map<String, String> _getAuthHeaders(String idToken) {
    return {
      'Content-Type': 'application/json; charset=UTF-8',
      // Backend (main.py) Bearer token bekliyor.
      'Authorization': 'Bearer $idToken',
    };
  }
  
  /// Sunucudan gelen yanıtları işleyen merkezi yardımcı fonksiyon.
  /// Başarılı ise JSON gövdesini çözer, hatalı ise ApiException fırlatır.
  dynamic _handleResponse(http.Response response) {
    // UTF-8 kodlaması ile gövdeyi güvenli bir şekilde çöz
    final String responseBody = utf8.decode(response.bodyBytes);
    
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.statusCode == 204) { // 204 No Content durumunda gövde boş olur.
        return null;
      }
      return jsonDecode(responseBody);
    } else {
      // Hata durumunda, sunucunun gönderdiği 'detail' mesajını ayıkla.
      String errorMessage = "Bir hata oluştu.";
      if (responseBody.isNotEmpty) {
        try {
          final errorJson = jsonDecode(responseBody);
          // FastAPI genellikle hatayı 'detail' anahtarı altında gönderir.
          errorMessage = errorJson['detail'] ?? errorMessage;
        } catch (e) {
          // JSON çözülemezse, ham metni hata olarak kullan.
          errorMessage = responseBody;
        }
      }
      throw ApiException(errorMessage, response.statusCode);
    }
  }

  // =======================================================================
  // Flow7 - PLANLAMA API METOTLARI
  // =======================================================================

  /// Belirtilen tarih aralığındaki kullanıcı planlarını getirir.
  /// Backend endpoint: GET /api/plans?start_date=YYYY-MM-DD&end_date=YYYY-MM-DD
  Future<List<Map<String, dynamic>>> getUserPlans(String idToken, DateTime start, DateTime end) async {
    final df = DateFormat('yyyy-MM-dd');
    final uri = Uri.parse("$backendBaseUrl/api/plans")
        .replace(queryParameters: {'start_date': df.format(start), 'end_date': df.format(end)});
    
    final response = await http.get(uri, headers: _getAuthHeaders(idToken));
    final decoded = _handleResponse(response);
    
    // Dönen sonucun bir liste olduğunu doğrula
    return List<Map<String, dynamic>>.from(decoded);
  }

  /// Mevcut kullanıcı için yeni bir plan oluşturur.
  /// Backend endpoint: POST /api/plans
  Future<Map<String, dynamic>> createPlan(String idToken, Map<String, dynamic> payload) async {
    final uri = Uri.parse("$backendBaseUrl/api/plans");
    
    final response = await http.post(
      uri,
      headers: _getAuthHeaders(idToken),
      body: jsonEncode(payload),
    );

    return _handleResponse(response);
  }

  /// YENİ: Mevcut bir planı günceller.
  /// Backend endpoint: PUT /api/plans/{planId}
  Future<Map<String, dynamic>> updatePlan(String idToken, String planId, Map<String, dynamic> payload) async {
    final uri = Uri.parse("$backendBaseUrl/api/plans/$planId");

    final response = await http.put(
      uri,
      headers: _getAuthHeaders(idToken),
      body: jsonEncode(payload),
    );

    return _handleResponse(response);
  }

  /// Belirtilen ID'ye sahip planı siler.
  /// Backend endpoint: DELETE /api/plans/{planId}
  Future<void> deletePlan(String idToken, String planId) async {
    final uri = Uri.parse("$backendBaseUrl/api/plans/$planId");
    
    final response = await http.delete(uri, headers: _getAuthHeaders(idToken));
    
    // deletePlan 204 No Content döndüreceği için _handleResponse'u doğrudan kullanabiliriz.
    _handleResponse(response);
  }
  
  // =======================================================================
  // DİĞER API METOTLARI (Mevcut haliyle korundu)
  // =======================================================================

  /// Mevcut kullanıcı aboneliğini günceller.
  /// Backend endpoint: PUT /user/subscription/
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
    // Payload, backend'deki ThemePreferenceUpdate şemasına uygun olmalıdır: {"theme": "DARK"}
    final payload = jsonEncode({'theme': theme.toUpperCase()}); 

    final response = await http.put(
      uri,
      headers: _getAuthHeaders(idToken),
      body: payload,
    );

    return _handleResponse(response);
  }

  /// Mevcut kullanıcı profilini getirir.
  /// Backend endpoint: GET /user/profile/
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

  /// Kullanıcının dil tercihini günceller.
  /// Backend endpoint: PUT /user/language/  body: {"language_code": "tr"}
  Future<void> updateLanguage(String idToken, String languageCode) async {
    final uri = Uri.parse("$backendBaseUrl/user/language/");
    final response = await http.put(
      uri,
      headers: _getAuthHeaders(idToken),
      body: jsonEncode({'language_code': languageCode}),
    );
    _handleResponse(response);
  }

  /// Kullanıcının bildirim tercihlerini günceller.
  /// Backend endpoint: PUT /user/notifications/  body: {"enabled": true}
  Future<void> updateNotificationSetting(String idToken, bool enabled) async {
    final uri = Uri.parse("$backendBaseUrl/user/notifications/");
    final response = await http.put(
      uri,
      headers: _getAuthHeaders(idToken),
      body: jsonEncode({'enabled': enabled}),
    );
    _handleResponse(response);
  }
}
