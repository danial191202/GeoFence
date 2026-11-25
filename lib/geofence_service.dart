import 'dart:convert';

import 'package:http/http.dart' as http;

class Geofence {
  final int geofenceId;
  final String zoneName;
  final double latitude;
  final double longitude;
  final double radiusMeters;
  final String? status;

  const Geofence({
    required this.geofenceId,
    required this.zoneName,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    this.status,
  });

  /// Alias for compatibility with existing UI references
  String get locationName => zoneName;

  factory Geofence.fromJson(Map<String, dynamic> json) {
    return Geofence(
      geofenceId: (json['geofenceId'] as num?)?.toInt() ?? 0,
      zoneName:
          (json['zoneName'] ?? json['locationName'] ?? 'Checkpoint') as String,
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      radiusMeters: (json['radiusMeters'] as num?)?.toDouble() ?? 0.0,
      status: json['status'] as String?,
    );
  }
}

class ActiveSchedule {
  final int? scheduleId;
  final int? guardId;
  final int? geofenceId;
  final String? patrolDate;
  final int? roundNumber;
  final String? scheduleStatus;
  final String? scheduleStart;
  final String? scheduleEnd;
  final String? fullName;
  final String? guardNumber;
  final String? dutyStatus;
  final String? zoneName;
  final double? latitude;
  final double? longitude;
  final double? radiusMeters;

  const ActiveSchedule({
    this.scheduleId,
    this.guardId,
    this.geofenceId,
    this.patrolDate,
    this.roundNumber,
    this.scheduleStatus,
    this.scheduleStart,
    this.scheduleEnd,
    this.fullName,
    this.guardNumber,
    this.dutyStatus,
    this.zoneName,
    this.latitude,
    this.longitude,
    this.radiusMeters,
  });

  factory ActiveSchedule.fromJson(Map<String, dynamic> json) {
    return ActiveSchedule(
      scheduleId: (json['scheduleId'] as num?)?.toInt(),
      guardId: (json['guardId'] as num?)?.toInt(),
      geofenceId: (json['geofenceId'] as num?)?.toInt(),
      patrolDate: json['patrolDate']?.toString(),
      roundNumber: (json['roundNumber'] as num?)?.toInt(),
      scheduleStatus: json['scheduleStatus']?.toString(),
      scheduleStart: json['scheduleStart']?.toString(),
      scheduleEnd: json['scheduleEnd']?.toString(),
      fullName: json['fullName']?.toString(),
      guardNumber: json['guardNumber']?.toString(),
      dutyStatus: json['dutyStatus']?.toString(),
      zoneName: json['zoneName']?.toString(),
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      radiusMeters: (json['radiusMeters'] as num?)?.toDouble(),
    );
  }
}

class GeofenceService {
  // ── URL Configuration ───────────────────────────────────────────────────────
  // Use the emulator alias (10.0.2.2) when running in Android Emulator.
  // Use physical phone IP when testing on a physical device.
  // Set [_useEmulator] to true for emulator, false for physical phone.
  static const bool _useEmulator = false;

  // Active Android Emulator Base URL (Windows Host localhost:8082)
  static const String _emulatorBaseUrl = 'http://10.0.2.2:8082';

  // Physical phone testing Base URL (your current PC Wi-Fi IP is 10.14.4.115)
  // static const String _deviceBaseUrl = 'http://10.14.3.30:8082';
  static const String _deviceBaseUrl = 'http://10.14.4.95:8082';

  /// Active Base API URL
  static String get baseUrl => _useEmulator ? _emulatorBaseUrl : _deviceBaseUrl;

  /// Checkpoint Geofences Endpoint
  static String get apiUrl => '$baseUrl/api/geofences';

  /// Fetch all active geofence checkpoints from GET /api/geofences
  Future<List<Geofence>> fetchGeofences() async {
    try {
      final response = await http
          .get(Uri.parse(apiUrl))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final dynamic decodedData = jsonDecode(response.body);

        if (decodedData is! List) {
          throw Exception('Invalid API response format: expected a List.');
        }

        return decodedData.map((item) {
          return Geofence.fromJson(item as Map<String, dynamic>);
        }).toList();
      }

      throw Exception('API request failed. Status: ${response.statusCode}');
    } catch (error) {
      throw Exception('Unable to retrieve geofences: $error');
    }
  }

  /// Fetch active patrol schedule and guard details from GET /api/schedules/active?guardId={id}
  Future<ActiveSchedule?> fetchActiveSchedule({int guardId = 1}) async {
    try {
      final url = Uri.parse('$baseUrl/api/schedules/active?guardId=$guardId');
      final response = await http.get(url).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final dynamic decodedData = jsonDecode(response.body);
        if (decodedData is List && decodedData.isNotEmpty) {
          return ActiveSchedule.fromJson(
            decodedData.first as Map<String, dynamic>,
          );
        }
      }
      return null;
    } catch (error) {
      // Return null so the UI can gracefully use clean fallback values
      return null;
    }
  }

  /// Save check-in record to Oracle via POST /api/checkins
  Future<Map<String, dynamic>> saveCheckin({
    required int guardId,
    required int geofenceId,
    int? scheduleId,
    required double userLatitude,
    required double userLongitude,
    double? distanceMeters,
    String verificationStatus = 'VERIFIED',
  }) async {
    try {
      final url = Uri.parse('$baseUrl/api/checkins');
      final Map<String, dynamic> payload = {
        'guardId': guardId,
        'geofenceId': geofenceId,
        'userLatitude': userLatitude,
        'userLongitude': userLongitude,
        'verificationStatus': verificationStatus,
      };
      if (scheduleId != null) {
        payload['scheduleId'] = scheduleId;
      }
      if (distanceMeters != null) {
        payload['distanceMeters'] = distanceMeters;
      }

      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (response.body.isNotEmpty) {
          return jsonDecode(response.body) as Map<String, dynamic>;
        }
        return {'status': 'success'};
      }

      throw Exception(
        'Server returned ${response.statusCode}: ${response.body}',
      );
    } catch (error) {
      throw Exception('Failed to save check-in to Oracle: $error');
    }
  }
}
