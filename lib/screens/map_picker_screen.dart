import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

class MapPickerScreen extends StatefulWidget {
  const MapPickerScreen({super.key});

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  GoogleMapController? _mapController;
  LatLng? _selectedPosition;
  String _selectedAddress = 'Tap on the map to select a location';
  bool _isLoading = false;
  bool _isLocating = false; // ← NEW: Spinner for My Location

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _onMapTap(LatLng position) async {
    if (!mounted) return;

    setState(() {
      _selectedPosition = position;
      _isLoading = true;
      _selectedAddress = 'Getting address...';
    });

    try {
      final placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
      if (!mounted) return;

      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final parts = [
          p.street,
          p.subLocality,
          p.locality,
          p.administrativeArea,
        ].where((e) => e != null && e.isNotEmpty).join(', ');

        setState(() {
          _selectedAddress = parts.isNotEmpty ? parts : 'No address found';
        });
      } else {
        setState(() => _selectedAddress = 'No address found');
      }
    } catch (e) {
      if (mounted) setState(() => _selectedAddress = 'Failed to get address');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _goToCurrentLocation() async {
    if (!mounted) return;
    setState(() => _isLocating = true);

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        await _showLocationDialog(
          'Location Services Disabled',
          'Please enable your device’s location services to use this feature.',
          openSettings: Geolocator.openLocationSettings,
        );
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          await _showLocationDialog(
            'Permission Denied',
            'This feature requires location access. Please enable it in settings.',
            openSettings: Geolocator.openAppSettings,
          );
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        await _showLocationDialog(
          'Location Permanently Denied',
          'Location permissions are permanently denied. Please enable them from app settings.',
          openSettings: Geolocator.openAppSettings,
        );
        return;
      }

      final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      final latLng = LatLng(position.latitude, position.longitude);

      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(latLng, 16));
      await _onMapTap(latLng);
    } catch (e) {
      if (mounted) {
        await _showLocationDialog(
          'Location Error',
          'Failed to get your location. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  Future<void> _showLocationDialog(String title, String content, {Future<void> Function()? openSettings}) async {
    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          if (openSettings != null)
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await openSettings();
              },
              child: const Text('Open Settings', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
    );
  }

  void _confirmSelection() {
    if (_selectedPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a location first')),
      );
      return;
    }

    Navigator.pop(context, _selectedPosition);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF052238),
      appBar: AppBar(
        backgroundColor: const Color(0xFF052238),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Select Delivery Location',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: LatLng(14.5995, 120.9842),
              zoom: 12,
            ),
            onMapCreated: (controller) => _mapController = controller,
            onTap: _onMapTap,
            markers: _selectedPosition != null
                ? {
                    Marker(
                      markerId: const MarkerId('selected'),
                      position: _selectedPosition!,
                      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                    ),
                  }
                : {},
            padding: const EdgeInsets.only(bottom: 140),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
          ),

          // Address Preview Card
          if (_selectedPosition != null)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Card(
                color: Colors.white,
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.location_on, color: Colors.red, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _isLoading ? 'Getting address...' : _selectedAddress,
                          style: const TextStyle(fontSize: 13, color: Colors.black87),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Bottom Action Bar
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              color: const Color(0xFF052238),
              padding: const EdgeInsets.all(16),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isLocating ? () {} : _goToCurrentLocation, // ← Always enabled
                            icon: _isLocating
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF052238)),
                                    ),
                                  )
                                : const Icon(Icons.my_location, size: 18),
                            label: Text(
                              _isLocating ? 'Locating...' : 'My Location',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFF052238),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: _isLocating ? 2 : 3,
                              shadowColor: _isLocating ? Colors.transparent : Colors.black26,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _confirmSelection,
                            icon: const Icon(Icons.check_circle, size: 18),
                            label: const Text('Confirm'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green.shade600,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}