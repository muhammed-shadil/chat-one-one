import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../models/shared_location.dart';

/// Why the location couldn't be taken.
enum LocationProblem {
  /// Location (GPS) is switched off on the device.
  serviceDisabled,

  /// Permission was refused this time; asking again is allowed.
  denied,

  /// Refused for good ("Don't ask again", or blocked in the browser). Only
  /// the system settings can change it.
  deniedForever,

  /// No position came within the time limit.
  timeout,

  /// Anything else.
  unavailable,
}

extension LocationProblemText on LocationProblem {
  /// What to tell the person.
  String get message => switch (this) {
        LocationProblem.serviceDisabled => kIsWeb
            ? "Your browser couldn't get your location. Check that location "
                'is turned on, then try again.'
            : 'Location is turned off on this device. Turn it on, then try again.',
        LocationProblem.denied =>
          "Location wasn't allowed. That's okay — you can try again whenever "
              'you like.',
        LocationProblem.deniedForever => kIsWeb
            ? "Location is blocked for this site. Allow it in your browser's "
                'site settings, then try again.'
            : 'Location is turned off for this app. Allow it in Settings, '
                'then try again.',
        LocationProblem.timeout =>
          "Couldn't find your location in time. Try again somewhere with a "
              'better signal.',
        LocationProblem.unavailable =>
          "Couldn't get your location. Please try again.",
      };

  /// The settings page that fixes it, if one can be opened from the app.
  bool get canOpenSettings =>
      !kIsWeb &&
      (this == LocationProblem.serviceDisabled ||
          this == LocationProblem.deniedForever);

  String get settingsLabel => this == LocationProblem.serviceDisabled
      ? 'Turn on location'
      : 'Open Settings';
}

/// Either a position or the reason there isn't one.
class LocationResult {
  const LocationResult.success(LocationFix this.fix) : problem = null;
  const LocationResult.failed(LocationProblem this.problem) : fix = null;

  final LocationFix? fix;
  final LocationProblem? problem;
}

/// The calls that reach the device's location, kept apart so tests can stand
/// in mock coordinates and permission answers.
abstract interface class LocationSource {
  Future<bool> isServiceEnabled();
  Future<LocationPermission> checkPermission();
  Future<LocationPermission> requestPermission();
  Future<LocationFix> currentPosition(Duration timeLimit);
  Future<bool> openAppSettings();
  Future<bool> openLocationSettings();
}

/// The real device, through geolocator. Only single readings are taken here:
/// no position stream, no background location.
class DeviceLocationSource implements LocationSource {
  const DeviceLocationSource();

  @override
  Future<bool> isServiceEnabled() => Geolocator.isLocationServiceEnabled();

  @override
  Future<LocationPermission> checkPermission() => Geolocator.checkPermission();

  @override
  Future<LocationPermission> requestPermission() =>
      Geolocator.requestPermission();

  @override
  Future<LocationFix> currentPosition(Duration timeLimit) async {
    final p = await Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: timeLimit,
      ),
    );
    return LocationFix(
      latitude: p.latitude,
      longitude: p.longitude,
      accuracy: p.accuracy,
      capturedAt: p.timestamp,
    );
  }

  @override
  Future<bool> openAppSettings() => Geolocator.openAppSettings();

  @override
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();
}

/// Takes the current location one time, asking for permission only then.
class LocationService {
  const LocationService([this.source = const DeviceLocationSource()]);

  final LocationSource source;

  /// Only call this after the person has chosen to share. The system asks
  /// for permission only if it hasn't been answered yet, or was refused
  /// without "Don't ask again"; once granted, nothing is asked.
  Future<LocationResult> captureOnce({
    Duration timeLimit = const Duration(seconds: 20),
  }) async {
    try {
      if (!await source.isServiceEnabled()) {
        return const LocationResult.failed(LocationProblem.serviceDisabled);
      }
      var permission = await source.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.unableToDetermine) {
        permission = await source.requestPermission();
      }
      switch (permission) {
        case LocationPermission.denied:
        case LocationPermission.unableToDetermine:
          return const LocationResult.failed(LocationProblem.denied);
        case LocationPermission.deniedForever:
          return const LocationResult.failed(LocationProblem.deniedForever);
        case LocationPermission.whileInUse:
        case LocationPermission.always:
          break;
      }
      final fix = await source.currentPosition(timeLimit);
      if (!fix.isValid) {
        return const LocationResult.failed(LocationProblem.unavailable);
      }
      return LocationResult.success(fix);
    } on TimeoutException {
      return const LocationResult.failed(LocationProblem.timeout);
    } on LocationServiceDisabledException {
      return const LocationResult.failed(LocationProblem.serviceDisabled);
    } on PermissionDeniedException {
      return const LocationResult.failed(LocationProblem.denied);
    } catch (e) {
      debugPrint('Location unavailable: $e');
      return const LocationResult.failed(LocationProblem.unavailable);
    }
  }

  /// Opens the settings page that fixes [problem]: the location switch, or
  /// this app's permissions. Does nothing in the browser.
  Future<void> openSettingsFor(LocationProblem problem) async {
    if (!problem.canOpenSettings) return;
    if (problem == LocationProblem.serviceDisabled) {
      await source.openLocationSettings();
    } else {
      await source.openAppSettings();
    }
  }
}
