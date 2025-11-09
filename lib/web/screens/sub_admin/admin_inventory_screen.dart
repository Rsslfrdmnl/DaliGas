// admin_inventory_screen.dart
import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:daligas/web/screens/super_admin/admin_welcome_screen.dart';
import 'admin_dashboard_screen.dart';
import 'admin_orders_screen.dart';
import 'admin_delivery_screen.dart';
import 'admin_feedbacks_screen.dart';
import 'admin_reports_screen.dart';
import 'admin_settings_screen.dart';
import 'package:uuid/uuid.dart';

// === SAFE FIELD ACCESS EXTENSION ===
extension SafeDoc on DocumentSnapshot {
  T? safeGet<T>(String field) {
    if (!exists) return null;
    final data = this.data() as Map<String, dynamic>?;
    if (data == null || !data.containsKey(field)) return null;

    final value = data[field];

    if (T == num || T == double || T == int) {
      if (value is num) return value as T;
      if (value is String) {
        final parsed = num.tryParse(value);
        if (parsed != null) return parsed as T;
      }
      return null;
    }

    if (value is T) return value;
    return null;
  }
}

// === SAFE TIMESTAMP PARSER ===
DateTime? _safeTimestamp(dynamic value) {
  if (value == null) return null;
  if (value is Timestamp) return value.toDate();
  if (value is String) {
    try {
      return DateTime.parse(value);
    } catch (_) {
      return null;
    }
  }
  return null;
}

class AdminInventoryScreen extends StatefulWidget {
  const AdminInventoryScreen({super.key});

  @override
  State<AdminInventoryScreen> createState() => _AdminInventoryScreenState();
}

class _AdminInventoryScreenState extends State<AdminInventoryScreen> {
  final _productsRef = FirebaseFirestore.instance.collection('products');
  final ImagePicker _picker = ImagePicker();
  bool _saving = false;
  String _searchQuery = '';
  int _currentPage = 0;
  final int _pageSize = 5;

  Future<void> _logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    if (context.mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => AdminWelcomeScreen()),
      );
    }
  }

  Widget _buildSidebar(BuildContext context) {
    return Container(
      width: 220,
      color: const Color(0xFF0D2236),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 40),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Transform.translate(
                offset: const Offset(-10, 0),
                child: Image.asset("assets/images/daligas_logo.png", height: 80),
              ),
              Transform.translate(
                offset: const Offset(-22, 0),
                child: const Text("DALI GAS", style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ],
          ),
          const SizedBox(height: 30),
          _SidebarItem(Icons.dashboard, "Dashboard", false, () {
            Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const AdminDashboardScreen(), transitionDuration: Duration.zero));
          }),
          _SidebarItem(Icons.shopping_cart, "Orders", false, () {
            Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const AdminOrdersScreen(), transitionDuration: Duration.zero));
          }),
          _SidebarItem(Icons.inventory, "Inventory", true, () {}),
          _SidebarItem(Icons.local_shipping, "Delivery Management", false, () {
            Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const AdminDeliveryScreen(), transitionDuration: Duration.zero));
          }),
          _SidebarItem(Icons.feedback, "Feedback", false, () {
            Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const AdminFeedbackScreen(), transitionDuration: Duration.zero));
          }),
          _SidebarItem(Icons.assignment, "Reports", false, () {
            Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const AdminReportsScreen(), transitionDuration: Duration.zero));
          }),
          _SidebarItem(Icons.settings, "Settings", false, () {
            Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const AdminSettingsScreen(), transitionDuration: Duration.zero));
          }),
          const Spacer(),
          _SidebarItem(Icons.logout, "Logout", false, () => _logout(context)),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildStatCard(String value, String title) {
    return Expanded(
      child: Card(
        elevation: 2,
        color: const Color(0xFFF9F6FB),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black)),
              const SizedBox(height: 6),
              Text(title, style: TextStyle(fontSize: 14, color: Colors.grey.shade700)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDoeChip(String min, String max, String lastChecked) {
    return _chipColumn(
      'LPG Prices via DOE',
      '₱$min – ₱$max/kg',
      lastChecked,
      color: Colors.deepPurple,
    );
  }

  Widget _chipColumn(String title, String value, String subtitle, {Color? color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: color)),
        Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: color)),
        Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }

  Future<Map<String, dynamic>?> _pickImageAndPreview() async {
    try {
      final XFile? picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (picked == null) return null;
      final bytes = await picked.readAsBytes();
      return {'file': picked, 'bytes': bytes};
    } catch (e) {
      debugPrint('Image pick error: $e');
      return null;
    }
  }

  Future<Map<String, String>?> _uploadImageToStorage({required XFile picked, required String productId}) async {
    try {
      final bytes = await picked.readAsBytes();
      final id = const Uuid().v4();
      final storageRef = FirebaseStorage.instance.ref().child('products/$productId/$id.jpg');
      final metadata = SettableMetadata(contentType: 'image/jpeg');
      final uploadTask = storageRef.putData(bytes, metadata);
      final snapshot = await uploadTask;
      final url = await snapshot.ref.getDownloadURL();
      return {'url': url, 'path': snapshot.ref.fullPath};
    } catch (e) {
      debugPrint('Upload error: $e');
      return null;
    }
  }

  Future<void> _showProductDialog({DocumentSnapshot? doc}) async {
    final isEdit = doc != null;
    String name = doc?.safeGet<String>('name') ?? '';
    String brand = doc?.safeGet<String>('brand') ?? '';
    String category = doc?.safeGet<String>('category') ?? '';
    String description = doc?.safeGet<String>('description') ?? '';
    String unit = doc?.safeGet<String>('unit') ?? '';
    double price = doc?.safeGet<num>('price')?.toDouble() ?? 0.0;
    int stock = doc?.safeGet<num>('stock')?.toInt() ?? 0;
    bool isAvailable = doc?.safeGet<bool>('isAvailable') ?? true;
    bool featured = doc?.safeGet<bool>('featured') ?? false;
    String imageUrl = doc?.safeGet<String>('imageUrl') ?? '';
    String imagePath = doc?.safeGet<String>('imagePath') ?? '';

    XFile? pickedImage;
    Uint8List? pickedBytes;
    final _formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(builder: (context, setStateDialog) {
          Future<void> pickImage() async {
            final result = await _pickImageAndPreview();
            if (result != null) {
              setStateDialog(() {
                pickedImage = result['file'] as XFile;
                pickedBytes = result['bytes'] as Uint8List;
              });
            }
          }

          return AlertDialog(
            title: Text(isEdit ? 'Edit Product' : 'Add Product'),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: pickImage,
                        child: Container(
                          height: 140,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: Colors.grey.shade200,
                            image: (pickedBytes != null)
                                ? DecorationImage(image: MemoryImage(pickedBytes!), fit: BoxFit.contain)
                                : (imageUrl.isNotEmpty ? DecorationImage(image: NetworkImage(imageUrl), fit: BoxFit.contain) : null),
                          ),
                          child: (pickedBytes == null && imageUrl.isEmpty)
                              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: const [Icon(Icons.image, size: 36), SizedBox(height: 6), Text('Tap to pick image')]))
                              : null,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(initialValue: name, decoration: const InputDecoration(labelText: 'Name'), validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null, onSaved: (v) => name = v!.trim()),
                      TextFormField(initialValue: brand, decoration: const InputDecoration(labelText: 'Brand'), onSaved: (v) => brand = v?.trim() ?? ''),
                      TextFormField(initialValue: category, decoration: const InputDecoration(labelText: 'Category'), onSaved: (v) => category = v?.trim() ?? ''),
                      TextFormField(initialValue: description, decoration: const InputDecoration(labelText: 'Description'), maxLines: 2, onSaved: (v) => description = v?.trim() ?? ''),
                      TextFormField(
                        initialValue: price != 0.0 ? price.toString() : '',
                        decoration: const InputDecoration(labelText: 'Price'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : (double.tryParse(v) == null ? 'Invalid' : null),
                        onSaved: (v) => price = double.parse(v!.trim()),
                      ),
                      TextFormField(
                        initialValue: stock != 0 ? stock.toString() : '',
                        decoration: const InputDecoration(labelText: 'Stock (qty)'),
                        keyboardType: TextInputType.number,
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : (int.tryParse(v) == null ? 'Invalid' : null),
                        onSaved: (v) => stock = int.parse(v!.trim()),
                      ),
                      TextFormField(initialValue: unit, decoration: const InputDecoration(labelText: 'Unit'), onSaved: (v) => unit = v?.trim() ?? ''),
                      const SizedBox(height: 8),
                      Row(children: [Checkbox(value: isAvailable, onChanged: (val) => setStateDialog(() => isAvailable = val ?? true)), const Text('Available'), const SizedBox(width: 16)]),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: _saving ? null : () async {
                  if (!_formKey.currentState!.validate()) return;
                  _formKey.currentState!.save();
                  setState(() => _saving = true);

                  try {
                    final oldStock = isEdit ? doc!.safeGet<num>('stock')?.toInt() ?? 0 : 0;
                    final stockChanged = isEdit && oldStock != stock;

                    if (isEdit) {
                      final id = doc!.id;
                      if (pickedImage != null) {
                        if (imagePath.isNotEmpty) {
                          try { await FirebaseStorage.instance.ref(imagePath).delete(); } catch (_) {}
                        }
                        final res = await _uploadImageToStorage(picked: pickedImage!, productId: id);
                        if (res != null) { imageUrl = res['url']!; imagePath = res['path']!; }
                      }

                      final updateData = {
                        'name': name,
                        'brand': brand,
                        'category': category,
                        'description': description,
                        'price': price,
                        'stock': stock,
                        'unit': unit,
                        'isAvailable': isAvailable,
                        'featured': featured,
                        'imageUrl': imageUrl,
                        'imagePath': imagePath,
                        'updatedAt': FieldValue.serverTimestamp(),
                      };

                      if (stockChanged) {
                        updateData['lastRestocked'] = FieldValue.serverTimestamp();
                      }

                      await _productsRef.doc(id).update(updateData);
                    } else {
                      final newDocRef = _productsRef.doc();
                      final id = newDocRef.id;
                      if (pickedImage != null) {
                        final res = await _uploadImageToStorage(picked: pickedImage!, productId: id);
                        if (res != null) { imageUrl = res['url']!; imagePath = res['path']!; }
                      }

                      await newDocRef.set({
                        'name': name,
                        'brand': brand,
                        'category': category,
                        'description': description,
                        'price': price,
                        'stock': stock,
                        'unit': unit,
                        'isAvailable': isAvailable,
                        'featured': featured,
                        'imageUrl': imageUrl,
                        'imagePath': imagePath,
                        'lastRestocked': stock > 0 ? FieldValue.serverTimestamp() : null,
                        'rating': 0.0,
                        'tags': [],
                        'createdAt': FieldValue.serverTimestamp(),
                        'updatedAt': FieldValue.serverTimestamp(),
                      });
                    }
                    if (context.mounted) Navigator.of(context).pop();
                  } catch (e) {
                    debugPrint('Save error: $e');
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error saving product')));
                  } finally {
                    setState(() => _saving = false);
                  }
                },
                child: Text(isEdit ? 'Save' : 'Add'),
              ),
            ],
          );
        });
      },
    );
  }

  Future<void> _deleteProduct(DocumentSnapshot doc) async {
    final confirm = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Delete product'), content: const Text('Are you sure you want to delete this product?'),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        ElevatedButton(onPressed: () => Navigator.of(context).pop(true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text('Delete')),
      ],
    ));

    if (confirm == true) {
      try {
        final imagePath = doc.safeGet<String>('imagePath') ?? '';
        if (imagePath.isNotEmpty) {
          try { await FirebaseStorage.instance.ref(imagePath).delete(); } catch (_) {}
        }
        await _productsRef.doc(doc.id).delete();
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Product deleted')));
      } catch (e) {
        debugPrint('Delete error: $e');
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to delete product')));
      }
    }
  }

  // === PAGINATED TABLE BUILDER ===
  Widget _buildPaginatedTable(List<QueryDocumentSnapshot> allDocs) {
    final filteredDocs = allDocs.where((d) {
      final name = (d.safeGet<String>('name') ?? '').toLowerCase();
      return _searchQuery.isEmpty || name.contains(_searchQuery);
    }).toList();

    if (filteredDocs.isEmpty) {
      return const Center(
        child: Text('No products found', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
      );
    }

    final totalItems = filteredDocs.length;
    final totalPages = (totalItems / _pageSize).ceil();

    if (_currentPage >= totalPages) _currentPage = totalPages - 1;
    if (_currentPage < 0) _currentPage = 0;

    final start = _currentPage * _pageSize;
    final end = (start + _pageSize).clamp(0, totalItems);
    final pageDocs = filteredDocs.sublist(start, end);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(6)),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width - 280),
              child: DataTable(
                headingRowColor: MaterialStateProperty.all(Colors.grey.shade100),
                dataRowHeight: 55,
                headingRowHeight: 50,
                horizontalMargin: 16,
                columnSpacing: 24,
                border: TableBorder(horizontalInside: BorderSide(color: Colors.grey.shade300, width: 1)),
                columns: const [
                  DataColumn(label: Text("Product Name/Type", style: TextStyle(fontWeight: FontWeight.w600))),
                  DataColumn(label: Text("Category", style: TextStyle(fontWeight: FontWeight.w600))),
                  DataColumn(label: Text("Quantity Available", style: TextStyle(fontWeight: FontWeight.w600))),
                  DataColumn(label: Text("Reorder Level", style: TextStyle(fontWeight: FontWeight.w600))),
                  DataColumn(label: Text("Unit Price", style: TextStyle(fontWeight: FontWeight.w600))),
                  DataColumn(label: Text("Status", style: TextStyle(fontWeight: FontWeight.w600))),
                  DataColumn(label: Text("Last Restocked", style: TextStyle(fontWeight: FontWeight.w600))),
                  DataColumn(label: Text("Action")),
                ],
                rows: pageDocs.map((doc) {
                  final productName = doc.safeGet<String>('name') ?? '';
                  final category = doc.safeGet<String>('category') ?? '';
                  final stock = doc.safeGet<num>('stock')?.toInt() ?? 0;
                  final imageUrl = doc.safeGet<String>('imageUrl') ?? '';
                  final lastRestocked = _safeTimestamp(doc.safeGet<dynamic>('lastRestocked'));
                  final lastRestockedText = lastRestocked != null
                      ? '${lastRestocked.year}-${lastRestocked.month.toString().padLeft(2, '0')}-${lastRestocked.day.toString().padLeft(2, '0')}'
                      : '-';
                  final isAvailable = doc.safeGet<bool>('isAvailable') ?? true;
                  final currentPrice = doc.safeGet<num>('price')?.toDouble() ?? 0.0;

                  return DataRow(
                    cells: [
                      DataCell(Row(children: [
                        if (imageUrl.isNotEmpty)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.network(imageUrl, width: 56, height: 40, fit: BoxFit.contain, errorBuilder: (c, e, s) => const Icon(Icons.image_not_supported)),
                          ),
                        const SizedBox(width: 8),
                        Flexible(child: Text(productName)),
                      ])),
                      DataCell(Text(category)),
                      DataCell(Text(stock.toString())),
                      const DataCell(Text("10")),
                      DataCell(Text('₱${currentPrice.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold))), // ONLY MANUAL PRICE
                      DataCell(Text(isAvailable ? "In Stock" : "Unavailable", style: TextStyle(color: isAvailable ? Colors.green : Colors.red, fontWeight: FontWeight.w600))),
                      DataCell(Text(lastRestockedText)),
                      DataCell(Row(children: [
                        IconButton(icon: const Icon(Icons.edit, color: Colors.blue), onPressed: () => _showProductDialog(doc: doc)),
                        IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _deleteProduct(doc)),
                      ])),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ),

        // === PAGINATION CONTROLS ===
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: _currentPage > 0 ? () => setState(() => _currentPage--) : null,
                icon: const Icon(Icons.chevron_left),
                tooltip: 'Previous',
              ),
              Text('Page ${_currentPage + 1} of $totalPages', style: const TextStyle(fontWeight: FontWeight.w500)),
              IconButton(
                onPressed: _currentPage < totalPages - 1 ? () => setState(() => _currentPage++) : null,
                icon: const Icon(Icons.chevron_right),
                tooltip: 'Next',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _updateStockDialogBulk(List<QueryDocumentSnapshot> docsToEdit) async {
    if (docsToEdit.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No products to update.')));
      return;
    }
    final controllers = <String, TextEditingController>{};
    for (var doc in docsToEdit) {
      controllers[doc.id] = TextEditingController(text: (doc.safeGet<num>('stock')?.toInt() ?? 0).toString());
    }
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Update Stocks'),
        content: SizedBox(
          width: 500,
          height: 400,
          child: SingleChildScrollView(
            child: Column(
              children: docsToEdit.map((doc) {
                final name = doc.safeGet<String>('name') ?? '';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(child: Text(name, style: const TextStyle(fontSize: 14), overflow: TextOverflow.ellipsis)),
                      const SizedBox(width: 20),
                      SizedBox(width: 70, child: TextField(controller: controllers[doc.id], keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Stock', isDense: true))),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final batch = FirebaseFirestore.instance.batch();
              for (var doc in docsToEdit) {
                final newStock = int.tryParse(controllers[doc.id]?.text ?? '') ?? 0;
                final oldStock = doc.safeGet<num>('stock')?.toInt() ?? 0;
                final updateData = {
                  'stock': newStock,
                  'updatedAt': FieldValue.serverTimestamp(),
                };
                if (newStock != oldStock) {
                  updateData['lastRestocked'] = FieldValue.serverTimestamp();
                }
                batch.update(_productsRef.doc(doc.id), updateData);
              }
              try {
                await batch.commit();
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Stocks updated')));
              } catch (e) {
                debugPrint('Bulk update error: $e');
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to update stocks')));
              }
            },
            child: const Text('Save Changes'),
          ),
        ],
      ),
    );
  }

  void _exportVisibleToCsv(List<QueryDocumentSnapshot> visibleDocs) {
    if (!kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Export to CSV is available on web only.')));
      return;
    }
    if (visibleDocs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No products to export')));
      return;
    }

    final rows = <List<String>>[];
    rows.add(['Name', 'Category', 'Stock', 'Price', 'Availability', 'Last Restocked']);
    for (var doc in visibleDocs) {
      final lastRestocked = _safeTimestamp(doc.safeGet<dynamic>('lastRestocked'));
      final lastRestockedText = lastRestocked != null ? '${lastRestocked.year}-${lastRestocked.month.toString().padLeft(2, '0')}-${lastRestocked.day.toString().padLeft(2, '0')}' : '';
      rows.add([
        doc.safeGet<String>('name') ?? '',
        doc.safeGet<String>('category') ?? '',
        (doc.safeGet<num>('stock')?.toInt() ?? 0).toString(),
        (doc.safeGet<num>('price')?.toDouble() ?? 0.0).toStringAsFixed(2),
        doc.safeGet<bool>('isAvailable') == true ? 'Available' : 'Unavailable',
        lastRestockedText,
      ]);
    }

    final csv = const _SimpleCsvConverter().convert(rows);
    final bytes = utf8.encode(csv);
    final blob = html.Blob([bytes]);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)..setAttribute('download', 'inventory_report.csv')..click();
    html.Url.revokeObjectUrl(url);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          _buildSidebar(context),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 50, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Inventory", style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                      ElevatedButton(
                        onPressed: () => _showProductDialog(),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
                        child: const Text("Add New Stock", style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: Card(
                      elevation: 3,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // === STATS (NO DOE) ===
                              StreamBuilder<QuerySnapshot>(
                                stream: _productsRef.snapshots(),
                                builder: (context, snapshot) {
                                  String total = '0', low = '0 items', updated = '-';
                                  if (snapshot.hasData) {
                                    final docs = snapshot.data!.docs;
                                    total = docs.fold(0, (p, d) => p + (d.safeGet<num>('stock')?.toInt() ?? 0)).toString();
                                    low = '${docs.where((d) => (d.safeGet<num>('stock')?.toInt() ?? 0) <= 5).length} items';
                                    final updatedDocs = docs.where((d) => _safeTimestamp(d.safeGet<dynamic>('updatedAt')) != null).toList();
                                    if (updatedDocs.isNotEmpty) {
                                      updatedDocs.sort((a, b) {
                                        final ta = _safeTimestamp(a.safeGet<dynamic>('updatedAt')) ?? DateTime(1970);
                                        final tb = _safeTimestamp(b.safeGet<dynamic>('updatedAt')) ?? DateTime(1970);
                                        return tb.compareTo(ta);
                                      });
                                      final t = _safeTimestamp(updatedDocs.first.safeGet<dynamic>('updatedAt'));
                                      updated = t != null ? '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}' : '-';
                                    }
                                  }

                                  return Row(children: [
                                    _buildStatCard(total, "Total Stock Available"),
                                    const SizedBox(width: 16),
                                    _buildStatCard(low, "Low Stock Alerts"),
                                    const SizedBox(width: 16),
                                    _buildStatCard(updated, "Last Updated"),
                                  ]);
                                },
                              ),
                              const SizedBox(height: 20),

                              // === ACTION BUTTONS + SEARCH ===
                              Row(
                                children: [
                                  ElevatedButton(
                                    onPressed: () async {
                                      final snapshot = await _productsRef.orderBy('name').get();
                                      final visible = snapshot.docs.where((d) {
                                        final name = (d.safeGet<String>('name') ?? '').toLowerCase();
                                        final brand = (d.safeGet<String>('brand') ?? '').toLowerCase();
                                        final category = (d.safeGet<String>('category') ?? '').toLowerCase();
                                        final q = _searchQuery.trim().toLowerCase();
                                        return q.isEmpty || name.contains(q) || brand.contains(q) || category.contains(q);
                                      }).toList();
                                      await _updateStockDialogBulk(visible);
                                    },
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
                                    child: const Text("Update Stock", style: TextStyle(color: Colors.white)),
                                  ),
                                  const SizedBox(width: 12),
                                  OutlinedButton(
                                    onPressed: () async {
                                      final snapshot = await _productsRef.orderBy('name').get();
                                      final visible = snapshot.docs.where((d) {
                                        final name = (d.safeGet<String>('name') ?? '').toLowerCase();
                                        final brand = (d.safeGet<String>('brand') ?? '').toLowerCase();
                                        final category = (d.safeGet<String>('category') ?? '').toLowerCase();
                                        final q = _searchQuery.trim().toLowerCase();
                                        return q.isEmpty || name.contains(q) || brand.contains(q) || category.contains(q);
                                      }).toList();
                                      _exportVisibleToCsv(visible);
                                    },
                                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
                                    child: const Text("Export Inventory Report"),
                                  ),
                                  const Spacer(),
                                  SizedBox(
                                    width: 220,
                                    child: TextField(
                                      decoration: InputDecoration(
                                        hintText: "Search",
                                        prefixIcon: const Icon(Icons.search),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                      ),
                                      onChanged: (q) {
                                        setState(() {
                                          _searchQuery = q.toLowerCase();
                                          _currentPage = 0;
                                        });
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),

                              // === DOE CHIP (WITH lastChecked) ===
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.blue.shade200),
                                  ),
                                  child: StreamBuilder<DocumentSnapshot>(
                                    stream: FirebaseFirestore.instance.doc('doe_latest/lpg').snapshots(),
                                    builder: (context, snapshot) {
                                      if (!snapshot.hasData || !snapshot.data!.exists) {
                                        return _buildDoeChip('?', '?', 'Unknown');
                                      }
                                      final d = snapshot.data!.data() as Map<String, dynamic>;
                                      final min = d['pricePerKgMin']?.toString() ?? '0';
                                      final max = d['pricePerKgMax']?.toString() ?? '0';
                                      final lastChecked = _safeTimestamp(d['lastChecked']);
                                      final lastCheckedText = lastChecked != null
                                          ? '${lastChecked.year}-${lastChecked.month.toString().padLeft(2, '0')}-${lastChecked.day.toString().padLeft(2, '0')}'
                                          : 'Unknown';
                                      return _buildDoeChip(min, max, lastCheckedText);
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),

                              // === PAGINATED TABLE ===
                              StreamBuilder<QuerySnapshot>(
                                stream: _productsRef.orderBy('name').snapshots(),
                                builder: (context, snapshot) {
                                  if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text('No products found'));
                                  return _buildPaginatedTable(snapshot.data!.docs);
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatefulWidget {
  final IconData icon; final String title; final bool active; final VoidCallback onTap;
  const _SidebarItem(this.icon, this.title, this.active, this.onTap, {Key? key}) : super(key: key);
  @override State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hovering = false;
  @override Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: widget.active ? Colors.white.withOpacity(0.1) : (_hovering ? Colors.white.withOpacity(0.15) : Colors.transparent),
          borderRadius: BorderRadius.circular(6),
        ),
        child: ListTile(leading: Icon(widget.icon, color: Colors.white), title: Text(widget.title, style: const TextStyle(color: Colors.white)), onTap: widget.onTap),
      ),
    );
  }
}

class _SimpleCsvConverter {
  const _SimpleCsvConverter();
  String convert(List<List<String>> rows) {
    String escapeCell(String cell) {
      if (cell.contains('"')) cell = cell.replaceAll('"', '""');
      if (cell.contains(',') || cell.contains('"') || cell.contains('\n')) return '"$cell"';
      return cell;
    }
    return rows.map((r) => r.map(escapeCell).join(',')).join('\r\n');
  }
}