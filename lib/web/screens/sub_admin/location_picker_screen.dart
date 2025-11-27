import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_places_flutter/model/prediction.dart';

class LocationPickerScreen extends StatefulWidget {
  final LatLng? initialPosition;
  final String? initialAddress;

  const LocationPickerScreen({
    super.key,
    this.initialPosition,
    this.initialAddress,
  });

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  GoogleMapController? _mapController;
  Marker? _shopMarker;
  LatLng? _selectedLatLng;
  String _address = '';
  bool _loadingLocation = false;
  bool _loadingAddress = false;
  bool _searching = false;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final GlobalKey _searchBarKey = GlobalKey(); // ← For dynamic overlay position

  // Firebase Proxies
  static const String _autocompleteProxy =
      'https://asia-southeast1-daligas-bfd9b.cloudfunctions.net/placesAutocomplete';
  static const String _detailsProxy =
      'https://asia-southeast1-daligas-bfd9b.cloudfunctions.net/placeDetails';

  // Search state
  List<Prediction> _predictions = [];
  OverlayEntry? _overlayEntry;
  Timer? _debounceTimer;

  // --------------------------------------------------------------
  // Round to 5 decimal places (~1m accuracy)
  // --------------------------------------------------------------
  LatLng _round(LatLng l) => LatLng(
        double.parse(l.latitude.toStringAsFixed(5)),
        double.parse(l.longitude.toStringAsFixed(5)),
      );

  // --------------------------------------------------------------
  // Debounced Search
  // --------------------------------------------------------------
  void _debouncedSearch(String query) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      _searchPlaces(query);
    });
  }

  // --------------------------------------------------------------
  // Custom Autocomplete Search
  // --------------------------------------------------------------
  Future<void> _searchPlaces(String query) async {
    if (query.trim().length < 2) {
      setState(() => _predictions = []);
      _hideOverlay();
      return;
    }

    setState(() => _searching = true);
    try {
      final url = Uri.parse(_autocompleteProxy).replace(queryParameters: {
        'input': query.trim(),
      });

      final response = await http.get(url);
      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' || data['status'] == 'ZERO_RESULTS') {
          final List<dynamic> raw = data['predictions'] ?? [];
          setState(() {
            _predictions = raw
                .map<Prediction>((p) => Prediction.fromJson(p))
                .toList();
          });
          _showOverlay();
        }
      }
    } catch (e) {
      debugPrint('Search error: $e');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  // --------------------------------------------------------------
  // Fetch Place Details
  // --------------------------------------------------------------
  Future<void> _fetchPlaceDetails(String placeId) async {
    if (placeId.isEmpty) return;

    setState(() => _loadingAddress = true);
    try {
      final url = Uri.parse(_detailsProxy).replace(queryParameters: {
        'placeid': placeId,
      });

      final response = await http.get(url);
      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
          final location = data['result']['geometry']['location'];
          final lat = location['lat'] as double;
          final lng = location['lng'] as double;
          final address = data['result']['formatted_address'] ?? 'Unknown Address';

          final newLatLng = LatLng(lat, lng);
          _updateMarker(newLatLng);
          _searchController.text = address;
          _address = address;

          FocusScope.of(context).unfocus();
          _hideOverlay();
        }
      }
    } catch (e) {
      debugPrint('Place details error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to load place details')),
      );
    } finally {
      if (mounted) setState(() => _loadingAddress = false);
    }
  }

  // --------------------------------------------------------------
  // Show Dropdown Overlay — DYNAMIC BELOW SEARCH BAR
  // --------------------------------------------------------------
  void _showOverlay() {
    _hideOverlay();

    final renderBox = _searchBarKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final searchBarSize = renderBox.size;
    final searchBarPosition = renderBox.localToGlobal(Offset.zero);
    final overlayTop = searchBarPosition.dy + searchBarSize.height + 4; // 4px gap

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: overlayTop,
        left: 12,
        right: 12,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            constraints: const BoxConstraints(maxHeight: 300),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: _predictions.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'No results found',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  )
                : ListView.separated(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: _predictions.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final pred = _predictions[index];
                      return ListTile(
                        leading: const Icon(Icons.place, color: Colors.redAccent, size: 20),
                        title: Text(
                          pred.structuredFormatting?.mainText ?? pred.description ?? '',
                          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                        ),
                        subtitle: pred.structuredFormatting?.secondaryText != null
                            ? Text(
                                pred.structuredFormatting!.secondaryText!,
                                style: const TextStyle(fontSize: 12, color: Colors.white),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              )
                            : null,
                        onTap: () {
                          _searchController.text = pred.description ?? '';
                          if (pred.placeId != null && pred.placeId!.isNotEmpty) {
                            _fetchPlaceDetails(pred.placeId!);
                          }
                        },
                      );
                    },
                  ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  // --------------------------------------------------------------
  // Hide Overlay
  // --------------------------------------------------------------
  void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  // --------------------------------------------------------------
  // Get Device Location
  // --------------------------------------------------------------
  Future<LatLng?> _getDeviceLocation() async {
    setState(() => _loadingLocation = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception('Location service disabled');

      LocationPermission p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) {
        p = await Geolocator.requestPermission();
        if (p == LocationPermission.denied) throw Exception('Permission denied');
      }
      if (p == LocationPermission.deniedForever) {
        throw Exception('Permission permanently denied');
      }

      Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 12),
      );
      return LatLng(pos.latitude, pos.longitude);
    } catch (e) {
      final last = await Geolocator.getLastKnownPosition();
      return last != null ? LatLng(last.latitude, last.longitude) : null;
    } finally {
      if (mounted) setState(() => _loadingLocation = false);
    }
  }

  // --------------------------------------------------------------
  // Reverse Geocode
  // --------------------------------------------------------------
  Future<void> _reverseGeocode(LatLng latLng) async {
    setState(() => _loadingAddress = true);
    try {
      final placemarks = await placemarkFromCoordinates(latLng.latitude, latLng.longitude);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        _address = [
          p.street,
          p.subLocality,
          p.locality,
          p.administrativeArea,
          p.country,
        ].where((e) => e != null && e.isNotEmpty).join(', ');
      } else {
        _address = 'Address not found';
      }
    } catch (_) {
      _address = 'Unable to fetch address';
    } finally {
      if (mounted) setState(() => _loadingAddress = false);
    }
  }

  // --------------------------------------------------------------
  // Update Marker + Camera + Address
  // --------------------------------------------------------------
  void _updateMarker(LatLng latLng) {
    final rounded = _round(latLng);
    setState(() {
      _selectedLatLng = rounded;
      _shopMarker = Marker(
        markerId: const MarkerId('shop'),
        position: rounded,
        draggable: true,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        onDragEnd: (newPos) => _updateMarker(newPos),
      );
    });
    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(rounded, 16.5));
    _reverseGeocode(rounded);
  }

  // --------------------------------------------------------------
  // Init
  // --------------------------------------------------------------
  @override
  void initState() {
    super.initState();

    if (widget.initialPosition != null) {
      final pos = _round(widget.initialPosition!);
      _selectedLatLng = pos;
      _address = widget.initialAddress ?? '';
      _shopMarker = Marker(
        markerId: const MarkerId('shop'),
        position: pos,
        draggable: true,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        onDragEnd: (newPos) => _updateMarker(newPos),
      );
    } else {
      _getDeviceLocation().then((pos) {
        if (pos != null && mounted) _updateMarker(pos);
      });
    }

    _searchController.addListener(() {
      _debouncedSearch(_searchController.text);
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _hideOverlay();
    _mapController?.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------
  // UI
  // --------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final bool canConfirm = _selectedLatLng != null && !_loadingAddress;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: const Color(0xFF052238),
        foregroundColor: null,
        title: const Text('Select Shop Location'),
        actions: [
          if (_loadingLocation)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
      body: GestureDetector(
        onTap: () {
          FocusScope.of(context).unfocus();
          _hideOverlay();
        },
        child: Stack(
          children: [
            // MAP — BLOCK TAPS UNDER SEARCH BAR
            IgnorePointer(
              ignoring: false,
              child: GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: _selectedLatLng ?? const LatLng(14.5995, 120.9842),
                  zoom: 16,
                ),
                onMapCreated: (c) => _mapController = c,
                onTap: (latLng) {
                  final renderBox = context.findRenderObject() as RenderBox?;
                  if (renderBox != null) {
                    final tapPosition = renderBox.globalToLocal(Offset.zero);
                    if (tapPosition.dy > 100) {
                      _updateMarker(latLng);
                      _hideOverlay();
                      FocusScope.of(context).unfocus();
                    }
                  }
                },
                markers: _shopMarker != null ? {_shopMarker!} : {},
                myLocationEnabled: true,
                myLocationButtonEnabled: true,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
              ),
            ),

            // SEARCH BAR — ABSORBS ALL TAPS
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Card(
                key: _searchBarKey, // ← KEY FOR DYNAMIC POSITION
                elevation: 6,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  cursorColor: Colors.blue,
                  style: const TextStyle(fontSize: 16),
                  decoration: InputDecoration(
                    hintText: 'Search places in Philippines...',
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    prefixIcon: const Icon(Icons.search, color: Colors.white),
                    suffixIcon: _searching
                        ? const Padding(
                            padding: EdgeInsets.all(12.0),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _predictions = []);
                                  _hideOverlay();
                                },
                              )
                            : null,
                  ),
                  onTap: () {
                    _searchFocusNode.requestFocus();
                  },
                ),
              ),
            ),

            // ADDRESS CARD
            if (_selectedLatLng != null)
              Positioned(
                bottom: 100,
                left: 16,
                right: 16,
                child: Card(
                  elevation: 6,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Icon(Icons.location_on, color: Colors.red),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _address.isEmpty ? 'Fetching address...' : _address,
                                style: const TextStyle(fontWeight: FontWeight.w500),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${_selectedLatLng!.latitude.toStringAsFixed(5)}, ${_selectedLatLng!.longitude.toStringAsFixed(5)}',
                                style: const TextStyle(fontSize: 11, color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                        if (_loadingAddress)
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),

      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: canConfirm ? Colors.green.shade600 : Colors.grey,
        onPressed: canConfirm
            ? () {
                final rounded = _round(_selectedLatLng!);
                Navigator.pop(context, {
                  'lat': rounded.latitude,
                  'lng': rounded.longitude,
                  'name': _address.isEmpty ? 'Shop Location' : _address,
                });
              }
            : null,
        label: const Text('Confirm Location', style: TextStyle(fontWeight: FontWeight.bold)),
        icon: const Icon(Icons.check),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}