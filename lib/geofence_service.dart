import 'dart:convert';

import 'package:http/http.dart' as http;

class Geofence {
  final int geofenceId;
  final String locationName;
  final double latitude;
  final double longitude;
  final double radiusMeters;

  const Geofence({
    required this.geofenceId,
    required this.locationName,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
  });

  factory Geofence.fromJson(Map<String, dynamic> json) {
    return Geofence(
      geofenceId: (json['geofenceId'] as num).toInt(),
      locationName: json['locationName'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      radiusMeters: (json['radiusMeters'] as num).toDouble(),
    );
  }
}

class GeofenceService {
  // ── URL Configuration ───────────────────────────────────────────────────────
  // Use the emulator alias when running in the Android Emulator.
  // Use your PC's LAN IP when running on a real device connected to the same
  // Wi-Fi network as the Spring Boot backend.
  //
  // Android Emulator  → http://10.0.2.2:8082/api/geofences
  // Real device (LAN) → http://10.14.3.137:8082/api/geofences
  //
  // Set [_useEmulator] to true for emulator, false for a real device.
  static const bool _useEmulator = false;

  static const String _emulatorUrl = 'http://10.0.2.2:8082/api/geofences';
  static const String _deviceUrl   = 'http://10.14.3.137:8082/api/geofences';

  static String get apiUrl => _useEmulator ? _emulatorUrl : _deviceUrl;

  Future<List<Geofence>> fetchGeofences() async {
    try {
      final response = await http
          .get(Uri.parse(apiUrl))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final dynamic decodedData = jsonDecode(response.body);

        if (decodedData is! List) {
          throw Exception('Invalid API response format.');
        }

        return decodedData.map((item) {
          return Geofence.fromJson(item as Map<String, dynamic>);
        }).toList();
      }

      throw Exception('API request failed. Status: ${response.statusCode}');
    } catch (error) {
      throw Exception('Unable to retrieve geofence: $error');
    }
  }
}
