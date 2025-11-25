// lib/services/firebase_functions.dart
import 'package:cloud_functions/cloud_functions.dart';

/// Global Firebase Functions instance locked to Singapore (asia-southeast1)
final FirebaseFunctions functions = FirebaseFunctions.instanceFor(
  region: 'asia-southeast1',
);