import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';

class GeofenceCheckinScreen extends StatefulWidget {
  const GeofenceCheckinScreen({Key? key}) : super(key: key);

  @override
  _GeofenceCheckinScreenState createState() => _GeofenceCheckinScreenState();
}

class _GeofenceCheckinScreenState extends State<GeofenceCheckinScreen> {
  GoogleMapController? mapController;
  Position? currentLocation;
  StreamSubscription<Position>? positionStream;

  // Mock data representing what you will fetch from your Oracle DB API
  final double targetLat = 6.4297; // Example: Arau, Perlis
  final double targetLng = 100.2698;
  final double geofenceRadiusInMeters = 100.0; 

  bool isInRadius = false;
  double currentDistance = 0.0;

  @override
  void initState() {
    super.initState();
    _fetchPropertyDataFromOracle(); // Trigger API call on load
    _determinePosition();
  }

  // Placeholder for your backend API call
  Future<void> _fetchPropertyDataFromOracle() async {
    // Example: 
    // final response = await http.get(Uri.parse('https://your-api.com/property/location'));
    // Update targetLat, targetLng, and radius with parsed JSON data
  }

  Future<void> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    
    // Start listening to live location updates
    positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high)
    ).listen((Position position) {
      setState(() {
        currentLocation = position;
        _checkGeofence();
      });

      // Animate map camera to follow user
      mapController?.animateCamera(
        CameraUpdate.newLatLng(LatLng(position.latitude, position.longitude))
      );
    });
  }

  void _checkGeofence() {
    if (currentLocation != null) {
      currentDistance = Geolocator.distanceBetween(
        currentLocation!.latitude,
        currentLocation!.longitude,
        targetLat,
        targetLng,
      );

      setState(() {
        isInRadius = currentDistance <= geofenceRadiusInMeters;
      });
    }
  }

  @override
  void dispose() {
    positionStream?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Secure_Map'),
        backgroundColor: Colors.grey[900],
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Header Bar
          Container(
            width: double.infinity,
            color: Colors.grey[300],
            padding: const EdgeInsets.all(16.0),
            child: const Text(
              'GeoMap',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          
          // Map Area
          Expanded(
            child: currentLocation == null
                ? const Center(child: CircularProgressIndicator())
                : GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: LatLng(currentLocation!.latitude, currentLocation!.longitude),
                      zoom: 16.0,
                    ),
                    myLocationEnabled: true,
                    myLocationButtonEnabled: true,
                    onMapCreated: (GoogleMapController controller) {
                      mapController = controller;
                    },
                    circles: {
                      // Visual representation of the geofence
                      Circle(
                        circleId: const CircleId('geofence'),
                        center: LatLng(targetLat, targetLng),
                        radius: geofenceRadiusInMeters,
                        fillColor: Colors.blue.withOpacity(0.2),
                        strokeColor: Colors.blue,
                        strokeWidth: 2,
                      )
                    },
                  ),
          ),

          // Bottom Action Area
          Container(
            width: double.infinity,
            color: Colors.grey[300],
            padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 32.0),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isInRadius ? Colors.green[700] : Colors.grey,
                padding: const EdgeInsets.symmetric(vertical: 16.0),
              ),
              onPressed: () {
                if (isInRadius) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Check-in Successful!'))
                  );
                  // Add logic to POST check-in time to your backend here
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Incomplete: You are ${currentDistance.toStringAsFixed(0)}m away. Move closer to the property to check in.'),
                      backgroundColor: Colors.red,
                    )
                  );
                }
              },
              child: Text(
                'Check-In',
                style: TextStyle(
                  fontSize: 18, 
                  color: isInRadius ? Colors.white : Colors.black54
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}