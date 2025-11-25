import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:daligas/main_mobile.dart';
import 'map_picker_screen.dart';

class AddAddressScreen extends StatefulWidget {
  const AddAddressScreen({
    super.key,
    this.editMode = false,
    this.address,
  });

  final bool editMode;
  final Map<String, dynamic>? address;

  @override
  State<AddAddressScreen> createState() => _AddAddressScreenState();
}

class _AddAddressScreenState extends State<AddAddressScreen> {
  final _formKey = GlobalKey<FormState>();
  final _street = TextEditingController();
  final _barangay = TextEditingController();
  final _city = TextEditingController();
  final _province = TextEditingController();
  final _postal = TextEditingController();

  bool _isFetchingLocation = false;
  bool _isSaving = false;
  LatLng? _selectedLocation;

  final String _uid = FirebaseAuth.instance.currentUser!.uid;

  LatLng _roundLatLng(LatLng latLng) {
    return LatLng(
      double.parse(latLng.latitude.toStringAsFixed(5)),
      double.parse(latLng.longitude.toStringAsFixed(5)),
    );
  }

  @override
  void initState() {
    super.initState();
    if (widget.editMode && widget.address != null) {
      final a = widget.address!;
      _street.text = a['street'] ?? '';
      _barangay.text = a['barangay'] ?? '';
      _city.text = a['city'] ?? '';
      _province.text = a['province'] ?? '';
      _postal.text = a['postal'] ?? '';
      final lat = a['lat'];
      final lng = a['lng'];
      if (lat != null && lng != null) {
        _selectedLocation = LatLng(lat as double, lng as double);
      }
    }
  }

  @override
  void dispose() {
    _street.dispose();
    _barangay.dispose();
    _city.dispose();
    _province.dispose();
    _postal.dispose();
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _isFetchingLocation = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        await _showLocationDialog('Location Services Disabled', 'Please enable location services.');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          await _showLocationDialog('Permission Denied', 'Location access is required.');
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        await _showLocationDialog('Location Permanently Denied', 'Enable in app settings.');
        return;
      }

      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      final rawLatLng = LatLng(pos.latitude, pos.longitude);
      final roundedLatLng = _roundLatLng(rawLatLng);

      _selectedLocation = roundedLatLng;

      final placemarks = await placemarkFromCoordinates(roundedLatLng.latitude, roundedLatLng.longitude);
      if (placemarks.isNotEmpty && mounted) {
        final p = placemarks.first;
        setState(() {
          _street.text = p.street ?? '';
          _barangay.text = p.subLocality ?? '';
          _city.text = p.locality ?? '';
          _province.text = p.administrativeArea ?? '';
          _postal.text = p.postalCode ?? '';
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to get location: $e')));
      }
    } finally {
      if (mounted) setState(() => _isFetchingLocation = false);
    }
  }

  Future<void> _showLocationDialog(String title, String content) async {
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(content),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              if (title.contains('Services')) {
                await Geolocator.openLocationSettings();
              } else {
                await Geolocator.openAppSettings();
              }
            },
            child: const Text('Open Settings', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _pickOnMap() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MapPickerScreen()),
    );

    if (result is LatLng && mounted) {
      final roundedLatLng = _roundLatLng(result);
      _selectedLocation = roundedLatLng;
      setState(() => _isFetchingLocation = true);

      try {
        final placemarks = await placemarkFromCoordinates(roundedLatLng.latitude, roundedLatLng.longitude);
        if (placemarks.isNotEmpty && mounted) {
          final p = placemarks.first;
          setState(() {
            _street.text = p.street ?? '';
            _barangay.text = p.subLocality ?? '';
            _city.text = p.locality ?? '';
            _province.text = p.administrativeArea ?? '';
            _postal.text = p.postalCode ?? '';
          });
        }
      } catch (e) {
        debugPrint('Reverse geocoding failed: $e');
      } finally {
        if (mounted) setState(() => _isFetchingLocation = false);
      }
    }
  }

  Future<void> _saveAddress() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a location')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final userRef = firestore.collection('users').doc(_uid);
      final snapshot = await userRef.get();
      List<dynamic> currentAddresses = List.from(snapshot.data()?['addresses'] ?? []);

      final roundedLatLng = _roundLatLng(_selectedLocation!);

      // Preserve isActive from the original address being edited
      final bool isActive = widget.editMode ? (widget.address?['isActive'] ?? false) : false;

      final Map<String, dynamic> updatedAddress = {
        'street': _street.text.trim(),
        'barangay': _barangay.text.trim(),
        'city': _city.text.trim(),
        'province': _province.text.trim(),
        'postal': _postal.text.trim(),
        'isActive': isActive,
        'lat': roundedLatLng.latitude,
        'lng': roundedLatLng.longitude,
      };

      if (widget.editMode && widget.address != null) {
        // Find and REPLACE the old address using lat/lng match
        final int index = currentAddresses.indexWhere((a) {
          final map = a as Map<String, dynamic>;
          return map['lat'] == widget.address!['lat'] && map['lng'] == widget.address!['lng'];
        });

        if (index != -1) {
          currentAddresses[index] = updatedAddress;
        } else {
          // Fallback: add as new (shouldn't happen)
          currentAddresses.add(updatedAddress);
        }
      } else {
        // Add new address
        currentAddresses.add(updatedAddress);
      }

      await userRef.update({'addresses': currentAddresses});

      // RETURN THE FULL MAP SO MANAGE SCREEN CAN UPDATE IN PLACE
      if (mounted) {
        Navigator.pop(context, updatedAddress);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _buildCardField(TextEditingController controller, String label, {String? hint}) {
    return Card(
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: TextFormField(
          controller: controller,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
          validator: (v) => v == null || v.trim().isEmpty ? 'Enter $label' : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showLocationButtons = !widget.editMode || _selectedLocation == null;

    return Scaffold(
      backgroundColor: const Color(0xFF052238),
      appBar: AppBar(
        backgroundColor: const Color(0xFF052238),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.editMode ? 'Edit Address' : 'Add New Address',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              _buildCardField(_street, 'Street / Unit', hint: 'e.g. 123 Main St, Apt 4B'),
              _buildCardField(_barangay, 'Barangay', hint: 'e.g. Barangay 1'),
              _buildCardField(_city, 'City / Municipality', hint: 'e.g. Quezon City'),
              _buildCardField(_province, 'Province', hint: 'e.g. Metro Manila'),
              _buildCardField(_postal, 'Postal Code', hint: 'e.g. 1100'),

              const SizedBox(height: 16),

              if (showLocationButtons) ...[
                OutlinedButton.icon(
                  onPressed: _isFetchingLocation ? null : _useCurrentLocation,
                  icon: _isFetchingLocation
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.my_location, color: Colors.white),
                  label: Text(
                    _isFetchingLocation ? 'Detecting...' : 'Use My Location',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white, width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _isFetchingLocation ? null : _pickOnMap,
                  icon: const Icon(Icons.map, color: Colors.white),
                  label: const Text('Pick on Map', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white, width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ] else if (_selectedLocation != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.location_on, color: Colors.green, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Location pinned: ${_selectedLocation!.latitude.toStringAsFixed(5)}, ${_selectedLocation!.longitude.toStringAsFixed(5)}',
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ),
                      TextButton(
                        onPressed: _pickOnMap,
                        child: const Text('Change', style: TextStyle(color: Colors.blue)),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveAddress,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF052238),
                    elevation: 3,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isSaving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Color(0xFF052238), strokeWidth: 2))
                      : Text(
                          widget.editMode ? 'Update Address' : 'Save Address',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}