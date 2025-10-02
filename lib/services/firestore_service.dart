import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  final CollectionReference reports =
      FirebaseFirestore.instance.collection('pollution_reports');

  Future<void> addReport(double lat, double lng, int intensity) async {
    await reports.add({
      'lat': lat,
      'lng': lng,
      'intensity': intensity,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Stream<QuerySnapshot> getReports() {
    return reports.snapshots();
  }
}