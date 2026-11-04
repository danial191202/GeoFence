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
      title: 'GeoMap Check-In',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
      ),
      home: const GeofenceCheckinScreen(),
    );
  }
}

// ============================================================
// DESIGN TOKENS
// ============================================================

class _AppColors {
  static const surface = Color(0xFF0F1117);
  static const card = Color(0xFF1A1D27);
  static const cardBorder = Color(0xFF2A2D3A);
  static const accent = Color(0xFF6C63FF);
  static const success = Color(0xFF22C55E);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFEF4444);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF8B8FA8);
  static const textMuted = Color(0xFF4A4D5E);
}

// ============================================================
// GEOFENCE CHECK-IN SCREEN
// ============================================================

class GeofenceCheckinScreen extends StatefulWidget {
  const GeofenceCheckinScreen({super.key});

  @override
  State<GeofenceCheckinScreen> createState() => _GeofenceCheckinScreenState();
}

class _GeofenceCheckinScreenState extends State<GeofenceCheckinScreen>
    with TickerProviderStateMixin {
  // Google Maps
  GoogleMapController? _mapController;

  // GPS
  StreamSubscription<Position>? _positionSubscription;
  Position? _currentLocation;

  // Oracle geofence data
  Geofence? _geofence;

  // Loading and error states
  bool _isLoadingGeofence = true;
  bool _isLoadingLocation = true;
  bool _locationPermissionGranted = false;
  bool _isInGeofence = false;
  bool _isCheckingIn = false;

  String? _geofenceError;
  String? _locationError;

  double? _currentDistance;

  // Animation controllers
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _buttonController;
  late Animation<double> _buttonScaleAnimation;

  static const LatLng _fallbackLocation = LatLng(6.4297, 100.2698);

  // ============================================================
  // DYNAMIC GEOFENCE PROPERTIES
  // ============================================================

  LatLng get _targetLocation {
    if (_geofence == null) return _fallbackLocation;
    return LatLng(_geofence!.latitude, _geofence!.longitude);
  }

  double get _targetLatitude =>
      _geofence?.latitude ?? _fallbackLocation.latitude;
  double get _targetLongitude =>
      _geofence?.longitude ?? _fallbackLocation.longitude;
  double get _geofenceRadiusMeters => _geofence?.radiusMeters ?? 0.0;

  // ============================================================
  // INITIALIZATION
  // ============================================================

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _buttonController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );

    _buttonScaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _buttonController, curve: Curves.easeOut),
    );

    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await _fetchPropertyDataFromOracle();

    if (!mounted) return;

    if (_geofence == null) {
      setState(() {
        _isLoadingLocation = false;
        _locationError =
            'Unable to load geofence data. '
            'Please check your backend connection.';
      });
      return;
    }

    await _initializeLocation();
  }

  // ============================================================
  // FETCH GEOFENCE FROM ORACLE THROUGH SPRING BOOT
  // ============================================================

  Future<void> _fetchPropertyDataFromOracle() async {
    if (!mounted) return;

    setState(() {
      _isLoadingGeofence = true;
      _geofenceError = null;
    });

    try {
      final List<Geofence> geofences = await GeofenceService().fetchGeofences();

      if (geofences.isEmpty) {
        throw Exception('No geofence records found in Oracle.');
      }

      if (!mounted) return;

      setState(() {
        _geofence = geofences.first;
        _isLoadingGeofence = false;
        _geofenceError = null;
      });

      debugPrint('========== GEOFENCE DATA ==========');
      debugPrint('ID: ${_geofence!.geofenceId}');
      debugPrint('Location: ${_geofence!.locationName}');
      debugPrint('Latitude: ${_geofence!.latitude}');
      debugPrint('Longitude: ${_geofence!.longitude}');
      debugPrint('Radius: ${_geofence!.radiusMeters} metres');
      debugPrint('===================================');

      await _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(_targetLocation, 18),
      );
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _geofence = null;
        _isLoadingGeofence = false;
        _geofenceError = error.toString();
      });

      debugPrint('GEOFENCE API ERROR: $error');
    }
  }

  // ============================================================
  // LOCATION INITIALIZATION
  // ============================================================

  Future<void> _initializeLocation() async {
    if (!mounted) return;

    setState(() {
      _isLoadingLocation = true;
      _locationError = null;
    });

    try {
      final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        throw Exception('Location services are disabled. Please enable GPS.');
      }

      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        throw Exception('Location permission was denied.');
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception(
          'Location permission is permanently denied. '
          'Enable it in application settings.',
        );
      }

      if (!mounted) return;

      setState(() {
        _locationPermissionGranted = true;
      });

      final Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 20),
      );

      if (!mounted) return;

      _updateCurrentLocation(position);
      _startLocationStream();
    } on TimeoutException {
      if (!mounted) return;

      setState(() {
        _locationError =
            'GPS did not return a location within 20 seconds. '
            'Check the emulator location and try again.';
        _isLoadingLocation = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _locationError = error.toString().replaceFirst('Exception: ', '');
        _isLoadingLocation = false;
      });
    }
  }

  // ============================================================
  // CONTINUOUS LOCATION UPDATES
  // ============================================================

  void _startLocationStream() {
    _positionSubscription?.cancel();

    _positionSubscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 1,
          ),
        ).listen(
          (Position position) {
            if (!mounted) return;
            _updateCurrentLocation(position);
          },
          onError: (Object error) {
            if (!mounted) return;

            setState(() {
              _locationError = 'GPS update error: $error';
              _isLoadingLocation = false;
            });

            debugPrint('GPS STREAM ERROR: $error');
          },
        );
  }

  // ============================================================
  // UPDATE CURRENT LOCATION AND CALCULATE DISTANCE
  // ============================================================

  void _updateCurrentLocation(Position position) {
    if (!mounted || _geofence == null) return;

    final double distance = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      _targetLatitude,
      _targetLongitude,
    );

    final bool insideGeofence = distance <= _geofenceRadiusMeters;

    setState(() {
      _currentLocation = position;
      _currentDistance = distance;
      _isInGeofence = insideGeofence;
      _isLoadingLocation = false;
      _locationError = null;
    });

    if (_mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLng(LatLng(position.latitude, position.longitude)),
      );
    }

    debugPrint(
      'Distance from geofence: ${distance.toStringAsFixed(2)} metres',
    );
    debugPrint('Inside geofence: $insideGeofence');
  }

  // ============================================================
  // RETRY
  // ============================================================

  Future<void> _retryLocation() async {
    if (_geofence == null) {
      await _fetchPropertyDataFromOracle();
    }

    if (_geofence != null) {
      await _initializeLocation();
    }
  }

  Future<void> _goToCurrentLocation() async {
    if (_currentLocation == null) {
      await _retryLocation();
      return;
    }

    await _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(_currentLocation!.latitude, _currentLocation!.longitude),
        18,
      ),
    );
  }

  // ============================================================
  // CHECK-IN
  // ============================================================

  Future<void> _checkIn() async {
    if (_geofence == null) {
      _showMessage('Geofence data is unavailable.', _AppColors.danger);
      return;
    }

    if (_currentLocation == null) {
      _showMessage('Waiting for GPS location...', _AppColors.warning);
      return;
    }

    final double latestDistance = Geolocator.distanceBetween(
      _currentLocation!.latitude,
      _currentLocation!.longitude,
      _targetLatitude,
      _targetLongitude,
    );

    if (latestDistance > _geofenceRadiusMeters) {
      setState(() {
        _currentDistance = latestDistance;
        _isInGeofence = false;
      });

      _showMessage(
        'Check-in denied. You are ${latestDistance.toStringAsFixed(1)} m away.',
        _AppColors.danger,
      );

      return;
    }

    await _buttonController.forward();
    await _buttonController.reverse();

    setState(() {
      _isCheckingIn = true;
    });

    try {
      // DEMO ONLY:
      // This does not save a check-in record to Oracle yet.
      // A backend check-in endpoint will be implemented next.

      await Future.delayed(const Duration(milliseconds: 400));

      if (!mounted) return;

      _showMessage('✓  Check-in successful!', _AppColors.success);
    } catch (error) {
      if (!mounted) return;

      _showMessage('Check-in failed: $error', _AppColors.danger);
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingIn = false;
        });
      }
    }
  }

  // ============================================================
  // MESSAGE
  // ============================================================

  void _showMessage(String message, Color color) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        elevation: 0,
      ),
    );
  }

  // ============================================================
  // MAP MARKERS
  // ============================================================

  Set<Marker> get _markers {
    final Set<Marker> markers = {};

    if (_geofence != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('property'),
          position: _targetLocation,
          infoWindow: InfoWindow(
            title: _geofence!.locationName,
            snippet: 'Geofence destination',
          ),
        ),
      );
    }

    if (_currentLocation != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('current_location'),
          position: LatLng(
            _currentLocation!.latitude,
            _currentLocation!.longitude,
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
          infoWindow: const InfoWindow(title: 'Your current location'),
        ),
      );
    }

    return markers;
  }

  // ============================================================
  // GEOFENCE CIRCLE
  // ============================================================

  Set<Circle> get _geofenceCircles {
    if (_geofence == null) return {};

    return {
      Circle(
        circleId: const CircleId('property_geofence'),
        center: _targetLocation,
        radius: _geofenceRadiusMeters,
        fillColor: _AppColors.accent.withValues(alpha: 0.15),
        strokeColor: _AppColors.accent,
        strokeWidth: 2,
      ),
    };
  }

  // ============================================================
  // STATUS HELPERS
  // ============================================================

  ({IconData icon, String title, String subtitle, Color color, bool loading})
  get _statusInfo {
    if (_isLoadingGeofence) {
      return (
        icon: Icons.cloud_sync_rounded,
        title: 'Syncing geofence',
        subtitle: 'Connecting to backend…',
        color: _AppColors.warning,
        loading: true,
      );
    }
    if (_geofenceError != null) {
      return (
        icon: Icons.cloud_off_rounded,
        title: 'Geofence unavailable',
        subtitle: _geofenceError!,
        color: _AppColors.danger,
        loading: false,
      );
    }
    if (_isLoadingLocation) {
      return (
        icon: Icons.gps_not_fixed_rounded,
        title: 'Acquiring GPS',
        subtitle: 'Waiting for device location…',
        color: _AppColors.warning,
        loading: true,
      );
    }
    if (_locationError != null) {
      return (
        icon: Icons.location_off_rounded,
        title: 'Location error',
        subtitle: _locationError!,
        color: _AppColors.danger,
        loading: false,
      );
    }
    if (_currentLocation == null || _currentDistance == null) {
      return (
        icon: Icons.gps_not_fixed_rounded,
        title: 'No location',
        subtitle: 'Coordinates are unavailable.',
        color: _AppColors.warning,
        loading: false,
      );
    }
    if (_isInGeofence) {
      return (
        icon: Icons.verified_rounded,
        title: 'Inside geofence',
        subtitle:
            '${_currentDistance!.toStringAsFixed(1)} m from ${_geofence!.locationName}',
        color: _AppColors.success,
        loading: false,
      );
    }
    return (
      icon: Icons.location_on_rounded,
      title: 'Outside geofence',
      subtitle:
          '${_currentDistance!.toStringAsFixed(1)} m away · radius ${_geofenceRadiusMeters.toStringAsFixed(0)} m',
      color: _AppColors.warning,
      loading: false,
    );
  }

  String get _buttonLabel {
    if (_isCheckingIn) return 'Checking in…';
    if (_isLoadingGeofence) return 'Loading geofence…';
    if (_isLoadingLocation) return 'Waiting for GPS…';
    if (_geofence == null) return 'Geofence unavailable';
    if (_isInGeofence) return 'Check In';
    return 'Outside geofence';
  }

  bool get _buttonEnabled =>
      _geofence != null &&
      _currentLocation != null &&
      !_isLoadingLocation &&
      !_isLoadingGeofence &&
      !_isCheckingIn;

  // ============================================================
  // WIDGETS
  // ============================================================

  Widget _buildStatusPill() {
    final s = _statusInfo;
    final bool needsRetry =
        _geofenceError != null ||
        _locationError != null ||
        (!_isLoadingLocation && _currentLocation == null);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.3),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: Container(
        key: ValueKey(s.title),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: s.color.withValues(alpha: 0.35)),
          boxShadow: [
            BoxShadow(
              color: s.color.withValues(alpha: 0.08),
              blurRadius: 12,
              spreadRadius: 0,
            ),
          ],
        ),
        child: Row(
          children: [
            // Animated icon container
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: s.color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: s.loading
                  ? Padding(
                      padding: const EdgeInsets.all(10),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: s.color,
                      ),
                    )
                  : Icon(s.icon, color: s.color, size: 20),
            ),
            const SizedBox(width: 12),

            // Text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.title,
                    style: TextStyle(
                      color: s.color,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    s.subtitle,
                    style: const TextStyle(
                      color: _AppColors.textSecondary,
                      fontSize: 11.5,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Retry button
            if (needsRetry)
              GestureDetector(
                onTap: _retryLocation,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _AppColors.cardBorder,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.refresh_rounded,
                    color: _AppColors.textSecondary,
                    size: 18,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: _AppColors.textSecondary,
            fontSize: 12,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: _AppColors.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildCheckInButton() {
    final Color activeColor =
        _isInGeofence ? _AppColors.success : _AppColors.textMuted;
    final Color bgColor =
        _buttonEnabled
            ? (_isInGeofence ? _AppColors.success : _AppColors.card)
            : _AppColors.card;

    return ScaleTransition(
      scale: _buttonScaleAnimation,
      child: GestureDetector(
        onTap: _buttonEnabled ? _checkIn : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          width: double.infinity,
          height: 56,
          decoration: BoxDecoration(
            gradient: _buttonEnabled && _isInGeofence
                ? const LinearGradient(
                    colors: [Color(0xFF22C55E), Color(0xFF16A34A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: _buttonEnabled && _isInGeofence ? null : bgColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _buttonEnabled
                  ? (_isInGeofence
                      ? _AppColors.success
                      : _AppColors.cardBorder)
                  : _AppColors.cardBorder,
            ),
            boxShadow: _buttonEnabled && _isInGeofence
                ? [
                    BoxShadow(
                      color: _AppColors.success.withValues(alpha: 0.35),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isCheckingIn) ...[
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
              ] else ...[
                Icon(
                  _isInGeofence
                      ? Icons.how_to_reg_rounded
                      : Icons.location_disabled_rounded,
                  color: _buttonEnabled
                      ? Colors.white
                      : _AppColors.textMuted,
                  size: 20,
                ),
                const SizedBox(width: 10),
              ],
              Text(
                _buttonLabel,
                style: TextStyle(
                  color: _buttonEnabled
                      ? Colors.white
                      : _AppColors.textMuted,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // MAIN USER INTERFACE
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final double bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: _AppColors.surface,
      extendBodyBehindAppBar: true,

      // ── Transparent App Bar ───────────────────────────────────
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: _AppColors.accent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.location_on_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'GeoMap',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
            if (_geofence != null) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _AppColors.accent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _AppColors.accent.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    _geofence!.locationName,
                    style: const TextStyle(
                      color: _AppColors.accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          // My location button
          _AppBarAction(
            icon: Icons.my_location_rounded,
            tooltip: 'My location',
            onTap: _goToCurrentLocation,
          ),
          _AppBarAction(
            icon: Icons.refresh_rounded,
            tooltip: 'Refresh',
            onTap: _initializeApp,
          ),
          const SizedBox(width: 8),
        ],
      ),

      body: Column(
        children: [
          // ── GOOGLE MAP (fills most of the screen) ─────────────
          Expanded(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _targetLocation,
                zoom: 18,
              ),

              onMapCreated: (GoogleMapController controller) {
                _mapController = controller;

                if (_geofence != null) {
                  controller.animateCamera(
                    CameraUpdate.newLatLngZoom(_targetLocation, 18),
                  );
                }
              },

              markers: _markers,
              circles: _geofenceCircles,

              myLocationEnabled:
                  _locationPermissionGranted && _currentLocation != null,

              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              compassEnabled: true,
              mapType: MapType.normal,
            ),
          ),

          // ── BOTTOM PANEL ──────────────────────────────────────
          Container(
            decoration: const BoxDecoration(
              color: _AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black54,
                  blurRadius: 24,
                  offset: Offset(0, -4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 16),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _AppColors.textMuted,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),

                // Status pill
                _buildStatusPill(),

                // Info rows + button
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    0,
                    16,
                    bottomPadding + 16,
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: _AppColors.card,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: _AppColors.cardBorder),
                        ),
                        child: Column(
                          children: [
                            _buildInfoRow(
                              'Geofence radius',
                              _geofence == null
                                  ? '—'
                                  : '${_geofenceRadiusMeters.toStringAsFixed(0)} m',
                            ),
                            const SizedBox(height: 8),
                            _buildInfoRow(
                              'GPS accuracy',
                              _currentLocation == null
                                  ? '—'
                                  : '± ${_currentLocation!.accuracy.toStringAsFixed(1)} m',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildCheckInButton(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // CLEANUP
  // ============================================================

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _mapController?.dispose();
    _pulseController.dispose();
    _buttonController.dispose();
    super.dispose();
  }
}

// ============================================================
// REUSABLE APP BAR ACTION BUTTON
// ============================================================

class _AppBarAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _AppBarAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black38,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white12),
          ),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
      ),
    );
  }
}
