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
  // Android Emulator -> Your computer's localhost
  static const String apiUrl = 'http://10.0.2.2:8082/api/geofences';

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
