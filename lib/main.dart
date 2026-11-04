import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'geofence_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GeofenceApp());
}

// ============================================================
// APPLICATION
// ============================================================

class GeofenceApp extends StatelessWidget {
  const GeofenceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GeoMap',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFEEEEEE),
      ),
      home: const GeofenceCheckinScreen(),
    );
  }
}

// ============================================================
// SCREEN
// ============================================================

class GeofenceCheckinScreen extends StatefulWidget {
  const GeofenceCheckinScreen({super.key});

  @override
  State<GeofenceCheckinScreen> createState() => _GeofenceCheckinScreenState();
}

class _GeofenceCheckinScreenState extends State<GeofenceCheckinScreen> {
  GoogleMapController? _mapController;

  StreamSubscription<Position>? _positionSubscription;
  Position? _currentLocation;

  Geofence? _geofence;

  bool _isLoadingGeofence = true;
  bool _isLoadingLocation = true;
  bool _locationPermissionGranted = false;
  bool _isInGeofence = false;
  bool _isCheckingIn = false;

  String? _geofenceError;
  String? _locationError;

  double? _currentDistance;

  static const LatLng _fallbackLocation = LatLng(6.4297, 100.2698);

  // ── Computed properties ──────────────────────────────────────

  LatLng get _targetLocation =>
      _geofence == null
          ? _fallbackLocation
          : LatLng(_geofence!.latitude, _geofence!.longitude);

  double get _targetLatitude =>
      _geofence?.latitude ?? _fallbackLocation.latitude;
  double get _targetLongitude =>
      _geofence?.longitude ?? _fallbackLocation.longitude;
  double get _geofenceRadiusMeters => _geofence?.radiusMeters ?? 0.0;

  // ── Init ─────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await _fetchGeofence();
    if (!mounted) return;
    if (_geofence == null) {
      setState(() {
        _isLoadingLocation = false;
        _locationError = 'Unable to load geofence. Check backend connection.';
      });
      return;
    }
    await _initializeLocation();
  }

  // ── Fetch geofence ───────────────────────────────────────────

  Future<void> _fetchGeofence() async {
    if (!mounted) return;
    setState(() {
      _isLoadingGeofence = true;
      _geofenceError = null;
    });

    try {
      final geofences = await GeofenceService().fetchGeofences();
      if (geofences.isEmpty) throw Exception('No geofence records found.');

      if (!mounted) return;
      setState(() {
        _geofence = geofences.first;
        _isLoadingGeofence = false;
      });

      await _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(_targetLocation, 18),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _geofence = null;
        _isLoadingGeofence = false;
        _geofenceError = e.toString();
      });
    }
  }

  // ── Location ─────────────────────────────────────────────────

  Future<void> _initializeLocation() async {
    if (!mounted) return;
    setState(() {
      _isLoadingLocation = true;
      _locationError = null;
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception('GPS is disabled.');

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        throw Exception('Location permission denied.');
      }
      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permission permanently denied.');
      }

      if (!mounted) return;
      setState(() => _locationPermissionGranted = true);

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 20),
      );

      if (!mounted) return;
      _updateLocation(position);
      _startStream();
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _locationError = 'GPS timed out. Try again.';
        _isLoadingLocation = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _locationError = e.toString().replaceFirst('Exception: ', '');
        _isLoadingLocation = false;
      });
    }
  }

  void _startStream() {
    _positionSubscription?.cancel();
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 1,
      ),
    ).listen(
      (p) { if (mounted) _updateLocation(p); },
      onError: (e) {
        if (!mounted) return;
        setState(() {
          _locationError = 'GPS error: $e';
          _isLoadingLocation = false;
        });
      },
    );
  }

  void _updateLocation(Position position) {
    if (!mounted || _geofence == null) return;

    final distance = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      _targetLatitude,
      _targetLongitude,
    );

    setState(() {
      _currentLocation = position;
      _currentDistance = distance;
      _isInGeofence = distance <= _geofenceRadiusMeters;
      _isLoadingLocation = false;
      _locationError = null;
    });

    _mapController?.animateCamera(
      CameraUpdate.newLatLng(LatLng(position.latitude, position.longitude)),
    );
  }

  Future<void> _retry() async {
    if (_geofence == null) await _fetchGeofence();
    if (_geofence != null) await _initializeLocation();
  }

  Future<void> _goToMyLocation() async {
    if (_currentLocation == null) { await _retry(); return; }
    await _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(_currentLocation!.latitude, _currentLocation!.longitude),
        18,
      ),
    );
  }

  // ── Check-in ─────────────────────────────────────────────────

  Future<void> _checkIn() async {
    if (_geofence == null || _currentLocation == null) return;

    final distance = Geolocator.distanceBetween(
      _currentLocation!.latitude,
      _currentLocation!.longitude,
      _targetLatitude,
      _targetLongitude,
    );

    if (distance > _geofenceRadiusMeters) {
      setState(() { _currentDistance = distance; _isInGeofence = false; });
      _showSnack(
        'You are ${distance.toStringAsFixed(1)} m away. Move closer.',
        Colors.red,
      );
      return;
    }

    setState(() => _isCheckingIn = true);
    try {
      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      _showSnack('Check-in successful!', Colors.green);
    } catch (e) {
      if (!mounted) return;
      _showSnack('Check-in failed: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isCheckingIn = false);
    }
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ── Map data ─────────────────────────────────────────────────

  Set<Marker> get _markers {
    final markers = <Marker>{};

    if (_geofence != null) {
      markers.add(Marker(
        markerId: const MarkerId('property'),
        position: _targetLocation,
        infoWindow: InfoWindow(title: _geofence!.locationName),
      ));
    }

    if (_currentLocation != null) {
      markers.add(Marker(
        markerId: const MarkerId('me'),
        position: LatLng(_currentLocation!.latitude, _currentLocation!.longitude),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: const InfoWindow(title: 'You are here'),
      ));
    }

    return markers;
  }

  Set<Circle> get _circles {
    if (_geofence == null) return {};
    return {
      Circle(
        circleId: const CircleId('fence'),
        center: _targetLocation,
        radius: _geofenceRadiusMeters,
        fillColor: Colors.blue.withValues(alpha: 0.15),
        strokeColor: Colors.blue,
        strokeWidth: 2,
      ),
    };
  }

  // ── Status text helpers ───────────────────────────────────────

  String get _statusText {
    if (_isLoadingGeofence) return 'Loading geofence...';
    if (_geofenceError != null) return 'Error: ${_geofenceError!}';
    if (_isLoadingLocation) return 'Getting your location...';
    if (_locationError != null) return _locationError!;
    if (_currentDistance == null) return 'Waiting for GPS...';
    if (_isInGeofence) {
      return '✓  Inside — ${_currentDistance!.toStringAsFixed(1)} m from ${_geofence!.locationName}';
    }
    return '${_currentDistance!.toStringAsFixed(1)} m away (radius ${_geofenceRadiusMeters.toStringAsFixed(0)} m)';
  }

  Color get _statusColor {
    if (_geofenceError != null || _locationError != null) return Colors.red;
    if (_isLoadingGeofence || _isLoadingLocation || _currentDistance == null) {
      return Colors.orange;
    }
    return _isInGeofence ? Colors.green : Colors.orange;
  }

  bool get _buttonEnabled =>
      _geofence != null &&
      _currentLocation != null &&
      !_isLoadingLocation &&
      !_isLoadingGeofence &&
      !_isCheckingIn;

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: const Color(0xFFEEEEEE),

      // ── App Bar ──────────────────────────────────────────────
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        centerTitle: true,
        title: const Text(
          'GeoMap',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 20,
            color: Colors.black87,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location, color: Colors.black54),
            tooltip: 'My location',
            onPressed: _goToMyLocation,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.black54),
            tooltip: 'Refresh',
            onPressed: _initializeApp,
          ),
        ],
      ),

      body: Column(
        children: [
          // ── MAP ───────────────────────────────────────────────
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.40,
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _targetLocation,
                zoom: 18,
              ),
              onMapCreated: (controller) {
                _mapController = controller;
                if (_geofence != null) {
                  controller.animateCamera(
                    CameraUpdate.newLatLngZoom(_targetLocation, 18),
                  );
                }
              },
              markers: _markers,
              circles: _circles,
              myLocationEnabled:
                  _locationPermissionGranted && _currentLocation != null,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: true,
              mapToolbarEnabled: false,
              compassEnabled: false,
              mapType: MapType.normal,
            ),
          ),

          // ── LOCATION BAR ──────────────────────────────────────
          Container(
            color: Colors.grey[400],
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _geofence?.locationName ?? 'Loading...',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Location',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_drop_down, color: Colors.black54),
              ],
            ),
          ),

          // ── STATUS ────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _statusColor,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _statusText,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[700],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_geofenceError != null || _locationError != null)
                  GestureDetector(
                    onTap: _retry,
                    child: const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(Icons.refresh, size: 16, color: Colors.grey),
                    ),
                  ),
              ],
            ),
          ),

          // ── SPACER ────────────────────────────────────────────
          const Spacer(),

          // ── CHECK-IN BUTTON ───────────────────────────────────
          Padding(
            padding: EdgeInsets.fromLTRB(40, 0, 40, bottomPad + 32),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _buttonEnabled ? _checkIn : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isInGeofence
                      ? const Color(0xFF4CAF50)
                      : Colors.grey[400],
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey[300],
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                child: _isCheckingIn
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        _isLoadingGeofence
                            ? 'Loading...'
                            : _isLoadingLocation
                            ? 'Getting GPS...'
                            : 'Check-In',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _mapController?.dispose();
    super.dispose();
  }
}
