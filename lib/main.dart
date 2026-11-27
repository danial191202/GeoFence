import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'geofence_service.dart';
import 'guard_card.dart';

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
  Position? _currentLocation;
  Geofence? _geofence;
  ActiveSchedule? _activeSchedule;
  SecurityGuard? _guard;

  /// Logged-in guard: 1 = Malik, 2 = Hafiz, 3 = Amir (GUARD_ID in SECURITY_GUARD)
  static const int _guardId = 3;

  bool _isLoadingGeofence = true;
  bool _isLoadingSchedule = true;
  bool _isLoadingLocation = true;
  bool _isInGeofence = false;
  bool _isCheckingIn = false;

  String? _geofenceError;
  String? _locationError;

  double? _currentDistance;
  String _movementTrend = 'Stationary';

  // ── Computed properties ──────────────────────────────────────

  double get _targetLatitude => _geofence?.latitude ?? 0.0;
  double get _targetLongitude => _geofence?.longitude ?? 0.0;
  double get _geofenceRadiusMeters => _geofence?.radiusMeters ?? 0.0;

  // ── Init ─────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // Schedule first: the geofence choice depends on the schedule's GEOFENCE_ID.
    await _fetchSchedule();
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
      if (geofences.isEmpty) {
        throw Exception('No geofence records found in Oracle database.');
      }

      if (!mounted) return;
      setState(() {
        // If an active schedule specifies a geofenceId, prioritize matching it
        if (_activeSchedule?.geofenceId != null) {
          final matched = geofences
              .where((g) => g.geofenceId == _activeSchedule!.geofenceId)
              .toList();
          _geofence = matched.isNotEmpty ? matched.first : geofences.first;
        } else {
          _geofence = geofences.first;
        }
        _isLoadingGeofence = false;
        _geofenceError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _geofence = null;
        _isLoadingGeofence = false;
        _geofenceError = 'Database/backend offline: $e';
      });
    }
  } //Original

  // ── Fetch active schedule & guard info ───────────────────────

  Future<void> _fetchSchedule() async {
    if (!mounted) return;
    setState(() {
      _isLoadingSchedule = true;
    });

    try {
      final service = GeofenceService();
      final results = await Future.wait([
        service.fetchActiveSchedule(guardId: _guardId),
        service.fetchGuard(_guardId), // SECURITY_GUARD row for the card
      ]);
      if (!mounted) return;
      setState(() {
        _activeSchedule = results[0] as ActiveSchedule?;
        _guard = results[1] as SecurityGuard?;
        _isLoadingSchedule = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingSchedule = false;
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

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 20),
      );

      if (!mounted) return;
      _updateLocation(position);
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

  void _updateLocation(Position position) {
    if (!mounted || _geofence == null) return;

    final distance = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      _targetLatitude,
      _targetLongitude,
    );

    String trend = _movementTrend;
    if (_currentDistance != null) {
      final diff = distance - _currentDistance!;
      if (diff < -0.3) {
        trend = 'Moving closer ↓';
      } else if (diff > 0.3) {
        trend = 'Moving away ↑';
      } else if (position.speed < 0.3) {
        trend = 'Stationary';
      }
    }

    setState(() {
      _currentLocation = position;
      _currentDistance = distance;
      _movementTrend = trend;
      _isInGeofence = distance <= _geofenceRadiusMeters;
      _isLoadingLocation = false;
      _locationError = null;
    });
  }

  Future<void> _retry() async {
    if (_geofence == null) await _fetchGeofence();
    if (_activeSchedule == null) await _fetchSchedule();
    if (_geofence != null) await _initializeLocation();
  }

  Future<void> _refreshGPS() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 20),
      );

      _updateLocation(position);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location updated successfully')),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to update location: $e')));
    }
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
      setState(() {
        _currentDistance = distance;
        _isInGeofence = false;
      });
      _showSnack(
        'You are ${distance.toStringAsFixed(1)} m away. Move closer.',
        Colors.red,
      );
      return;
    }

    setState(() => _isCheckingIn = true);
    try {
      final guardId = _guardId;
      final geofenceId = _geofence!.geofenceId;
      final scheduleId = _activeSchedule?.scheduleId;

      await GeofenceService().saveCheckin(
        guardId: guardId,
        geofenceId: geofenceId,
        scheduleId: scheduleId,
        userLatitude: _currentLocation!.latitude,
        userLongitude: _currentLocation!.longitude,
        distanceMeters: distance,
        verificationStatus: 'VERIFIED',
      );

      if (!mounted) return;
      _showSnack('Check-in successful! Saved to Oracle.', Colors.green);

      // Refresh schedule to reflect completed state
      await _fetchSchedule();
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

  // ── Status text helpers ───────────────────────────────────────

  String get _statusText {
    if (_isLoadingGeofence) return 'Loading geofence...';
    if (_geofenceError != null) return 'Error: ${_geofenceError!}';
    if (_isLoadingLocation) return 'Getting your location...';
    if (_locationError != null) return _locationError!;
    if (_currentDistance == null) return 'Waiting for GPS...';

    final movementInfo = _movementTrend != 'Stationary'
        ? ' • $_movementTrend'
        : '';

    if (_isInGeofence) {
      return '✓ Inside — ${_currentDistance!.toStringAsFixed(1)} m from ${_geofence!.zoneName}$movementInfo';
    }
    return '${_currentDistance!.toStringAsFixed(1)} m away (radius ${_geofenceRadiusMeters.toStringAsFixed(0)} m)$movementInfo';
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

  Widget _buildCheckpointImage() {
    return Container(
      color: Colors.white,
      child: Image.asset(
        'assets/images/dmdc.jpg',
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(painter: _WireframeCrossPainter()),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'image location',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[800],
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Checkpoint place',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Security Guard Info Card ─────────────────────────────────

  Widget _buildSecurityGuardCard() {
    return GuardCard(
      guard: _guard,
      schedule: _activeSchedule,
      isLoading: _isLoadingSchedule,
    );
  }

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
            tooltip: 'Refresh GPS',
            onPressed: _refreshGPS,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.black54),
            tooltip: 'Reload',
            onPressed: _initializeApp,
          ),
        ],
      ),

      body: SafeArea(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── CHECKPOINT IMAGE ──────────────────────────────────
              SizedBox(
                height: 200,
                width: double.infinity,
                child: _buildCheckpointImage(),
              ),

              // ── LOCATION BAR ──────────────────────────────────────
              Container(
                color: Colors.grey[400],
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _geofence?.zoneName ?? 'Loading...',
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
                        style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_geofenceError != null || _locationError != null)
                      GestureDetector(
                        onTap: _retry,
                        child: const Padding(
                          padding: EdgeInsets.only(left: 8),
                          child: Icon(
                            Icons.refresh,
                            size: 16,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // ── LIVE MOVEMENT / DISTANCE CARD ─────────────────────
              if (_currentDistance != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _isInGeofence
                            ? Colors.green.shade400
                            : Colors.orange.shade400,
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'DISTANCE TO CHECKPOINT',
                                  style: TextStyle(
                                    fontSize: 10,
                                    letterSpacing: 0.8,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Text(
                                      '${_currentDistance!.toStringAsFixed(1)} m',
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                        color: _isInGeofence
                                            ? Colors.green.shade700
                                            : Colors.black87,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '/ ${_geofenceRadiusMeters.toStringAsFixed(0)} m radius',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _isInGeofence
                                      ? '✓ ${(_geofenceRadiusMeters - _currentDistance!).toStringAsFixed(1)} m inside radius limit'
                                      : '⚠ ${(_currentDistance! - _geofenceRadiusMeters).toStringAsFixed(1)} m outside ${_geofenceRadiusMeters.toStringAsFixed(0)}m radius',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: _isInGeofence
                                        ? Colors.green.shade800
                                        : Colors.red.shade700,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: _movementTrend.contains('closer')
                                    ? Colors.green.shade50
                                    : _movementTrend.contains('away')
                                    ? Colors.orange.shade50
                                    : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: _movementTrend.contains('closer')
                                      ? Colors.green.shade400
                                      : _movementTrend.contains('away')
                                      ? Colors.orange.shade400
                                      : Colors.grey.shade300,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _movementTrend.contains('closer')
                                        ? Icons.arrow_downward_rounded
                                        : _movementTrend.contains('away')
                                        ? Icons.arrow_upward_rounded
                                        : Icons.place_outlined,
                                    size: 14,
                                    color: _movementTrend.contains('closer')
                                        ? Colors.green.shade700
                                        : _movementTrend.contains('away')
                                        ? Colors.orange.shade800
                                        : Colors.grey.shade700,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _movementTrend,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: _movementTrend.contains('closer')
                                          ? Colors.green.shade700
                                          : _movementTrend.contains('away')
                                          ? Colors.orange.shade800
                                          : Colors.grey.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Divider(height: 1, thickness: 1),
                        ),
                        // ── WHERE WE ARE (LIVE GPS) ──
                        Row(
                          children: [
                            const Icon(
                              Icons.person_pin_circle_outlined,
                              size: 15,
                              color: Colors.blue,
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                'Your Location: ${_currentLocation != null ? '${_currentLocation!.latitude.toStringAsFixed(6)}, ${_currentLocation!.longitude.toStringAsFixed(6)}' : 'Locating...'}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.black87,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        // ── CHECKPOINT TARGET ──
                        Row(
                          children: [
                            const Icon(
                              Icons.flag_outlined,
                              size: 15,
                              color: Colors.red,
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                'Checkpoint: ${_geofence != null ? '${_targetLatitude.toStringAsFixed(6)}, ${_targetLongitude.toStringAsFixed(6)} (${_geofence!.zoneName})' : 'Loading from database...'}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[700],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

              // ── SECURITY GUARD INFO CARD ──────────────────────────
              _buildSecurityGuardCard(),

              // ── CHECK-IN BUTTON ───────────────────────────────────
              Padding(
                padding: EdgeInsets.fromLTRB(40, 8, 40, bottomPad + 24),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _buttonEnabled ? _checkIn : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isInGeofence
                          ? const Color(0xFF4A855A)
                          : const Color(0xFF7E9785),
                      foregroundColor: Colors.black87,
                      disabledBackgroundColor: Colors.grey[400],
                      elevation: 0,
                      side: const BorderSide(
                        color: Color(0xFF0091EA),
                        width: 2.5,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(2),
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
        ),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}

// ============================================================
// WIREFRAME PLACEHOLDER PAINTER
// ============================================================

class _WireframeCrossPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final borderPaint = Paint()
      ..color = Colors.black87
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final crossPaint = Paint()
      ..color = Colors.black54
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Outer border
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), borderPaint);

    // Diagonal lines across (X)
    canvas.drawLine(
      const Offset(0, 0),
      Offset(size.width, size.height),
      crossPaint,
    );
    canvas.drawLine(Offset(0, size.height), Offset(size.width, 0), crossPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
