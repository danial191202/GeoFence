// This is a basic Flutter widget test for the Geofence Check-in app.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:geofence_checkin/main.dart';

void main() {
  testWidgets('Geofence check-in app smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());

    // Verify that the header text 'GeoMap' is displayed on the screen.
    expect(find.text('GeoMap'), findsOneWidget);

    // Verify that the 'Check-In' button exists.
    expect(find.text('Check-In'), findsOneWidget);
  });
}