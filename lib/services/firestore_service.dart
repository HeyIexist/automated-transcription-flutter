import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/meeting_extraction.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Local fallback storage in case Firestore is unreachable / unconfigured
  final List<MeetingRecord> _localFallbackStore = [];

  /// Save meeting record under `users/{userId}/meetings/{meetingId}`
  Future<String?> saveMeetingRecord({
    required String userId,
    required String title,
    required MeetingExtractionResult result,
    String? rawTranscript,
  }) async {
    final now = DateTime.now();
    final cleanUserId = userId.trim();
    final cleanTitle = title.trim().isEmpty ? 'Meeting on ${now.month}/${now.day}/${now.year}' : title.trim();

    final recordMap = {
      'user_id': cleanUserId,
      'title': cleanTitle,
      'result': result.toJson(),
      'raw_transcript': rawTranscript ?? result.transcribedText ?? '',
      'created_at': FieldValue.serverTimestamp(),
      'created_at_iso': now.toIso8601String(),
    };

    try {
      final docRef = _db
          .collection('users')
          .doc(cleanUserId)
          .collection('meetings')
          .doc();

      await docRef.set(recordMap);
      return docRef.id;
    } catch (e) {
      // Fallback: save to local list so user never loses data in session
      final fallbackId = 'local-${now.millisecondsSinceEpoch}';
      final localRecord = MeetingRecord(
        id: fallbackId,
        userId: cleanUserId,
        title: cleanTitle,
        result: result,
        rawTranscript: rawTranscript ?? result.transcribedText,
        createdAt: now,
      );
      _localFallbackStore.removeWhere((r) => r.id == fallbackId);
      _localFallbackStore.insert(0, localRecord);
      return fallbackId;
    }
  }

  /// Stream meeting records in real-time for a user
  Stream<List<MeetingRecord>> getMeetingRecordsStream(String userId) {
    final cleanUserId = userId.trim();
    if (cleanUserId.isEmpty) {
      return Stream.value(_localFallbackStore);
    }

    try {
      return _db
          .collection('users')
          .doc(cleanUserId)
          .collection('meetings')
          .orderBy('created_at', descending: true)
          .snapshots()
          .map((snapshot) {
        final records = snapshot.docs.map((doc) {
          final data = doc.data();
          return MeetingRecord.fromFirestoreMap(doc.id, data);
        }).toList();

        // Merge with local fallback store if any items exist
        for (var fallback in _localFallbackStore) {
          if (!records.any((r) => r.id == fallback.id)) {
            records.add(fallback);
          }
        }
        return records;
      }).handleError((error) {
        return _localFallbackStore;
      });
    } catch (_) {
      return Stream.value(_localFallbackStore);
    }
  }

  /// Delete a meeting record
  Future<bool> deleteMeetingRecord(String userId, String meetingId) async {
    final cleanUserId = userId.trim();
    _localFallbackStore.removeWhere((r) => r.id == meetingId);

    if (cleanUserId.isEmpty || meetingId.startsWith('local-')) {
      return true;
    }

    try {
      await _db
          .collection('users')
          .doc(cleanUserId)
          .collection('meetings')
          .doc(meetingId)
          .delete();
      return true;
    } catch (_) {
      return false;
    }
  }
}
