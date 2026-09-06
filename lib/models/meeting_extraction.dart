class ActionItemModel {
  String task;
  String owner;
  String dueDate;
  double confidence;
  bool isCompleted;

  ActionItemModel({
    required this.task,
    required this.owner,
    required this.dueDate,
    this.confidence = 1.0,
    this.isCompleted = false,
  });

  factory ActionItemModel.fromJson(Map<String, dynamic> json) {
    return ActionItemModel(
      task: json['task'] ?? '',
      owner: json['owner'] ?? 'Unassigned',
      dueDate: json['due_date'] ?? 'Not specified',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
      isCompleted: json['is_completed'] ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'task': task,
        'owner': owner,
        'due_date': dueDate,
        'confidence': confidence,
        'is_completed': isCompleted,
      };
}

class MeetingExtractionResult {
  final String summary;
  final List<String> keyDecisions;
  final List<ActionItemModel> actionItems;
  final List<String> lowConfidenceNotes;
  final String? transcribedText;
  final int wordCount;
  final DateTime processedAt;

  MeetingExtractionResult({
    required this.summary,
    required this.keyDecisions,
    required this.actionItems,
    required this.lowConfidenceNotes,
    this.transcribedText,
    required this.wordCount,
    required this.processedAt,
  });

  factory MeetingExtractionResult.fromJson(Map<String, dynamic> json) {
    return MeetingExtractionResult(
      summary: json['summary'] ?? '',
      keyDecisions: (json['key_decisions'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      actionItems: (json['action_items'] as List<dynamic>?)
              ?.map((e) => ActionItemModel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      lowConfidenceNotes: (json['low_confidence_notes'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      transcribedText: json['transcribed_text'],
      wordCount: json['word_count'] ?? 0,
      processedAt: json['processed_at'] != null
          ? DateTime.tryParse(json['processed_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'summary': summary,
        'key_decisions': keyDecisions,
        'action_items': actionItems.map((item) => item.toJson()).toList(),
        'low_confidence_notes': lowConfidenceNotes,
        'transcribed_text': transcribedText,
        'word_count': wordCount,
        'processed_at': processedAt.toIso8601String(),
      };
}

class MeetingRecord {
  final String id;
  final String userId;
  final String title;
  final MeetingExtractionResult result;
  final String? rawTranscript;
  final DateTime createdAt;

  MeetingRecord({
    required this.id,
    required this.userId,
    required this.title,
    required this.result,
    this.rawTranscript,
    required this.createdAt,
  });

  factory MeetingRecord.fromFirestoreMap(String docId, Map<String, dynamic> map) {
    DateTime parsedDate = DateTime.now();
    if (map['created_at'] != null) {
      if (map['created_at'] is String) {
        parsedDate = DateTime.tryParse(map['created_at']) ?? DateTime.now();
      } else {
        // Dynamic check for Firestore Timestamp without hard coupling
        try {
          final dynamic ts = map['created_at'];
          parsedDate = ts.toDate();
        } catch (_) {}
      }
    }

    final resultData = map['result'] != null
        ? Map<String, dynamic>.from(map['result'] as Map)
        : <String, dynamic>{};

    return MeetingRecord(
      id: docId,
      userId: map['user_id'] ?? '',
      title: map['title'] ?? 'Untitled Meeting',
      result: MeetingExtractionResult.fromJson(resultData),
      rawTranscript: map['raw_transcript'] ?? map['result']?['transcribed_text'],
      createdAt: parsedDate,
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'user_id': userId,
      'title': title,
      'result': result.toJson(),
      'raw_transcript': rawTranscript ?? result.transcribedText,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class SampleTranscriptModel {
  final String id;
  final String title;
  final String description;
  final String category;
  final String transcript;

  SampleTranscriptModel({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.transcript,
  });

  factory SampleTranscriptModel.fromJson(Map<String, dynamic> json) {
    return SampleTranscriptModel(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      category: json['category'] ?? '',
      transcript: json['transcript'] ?? '',
    );
  }
}
