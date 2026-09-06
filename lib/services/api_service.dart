import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/meeting_extraction.dart';

class ApiService {
  String baseUrl;
  final http.Client _client = http.Client();

  ApiService({this.baseUrl = 'http://127.0.0.1:8000'});

  void updateBaseUrl(String newUrl) {
    baseUrl = newUrl.replaceAll(RegExp(r'/+$'), '');
  }

  Future<MeetingExtractionResult> extractMeetingIntelligence(String transcript, {String? model}) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/meeting/extract'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'transcript': transcript,
        'model': model,
      }),
    ).timeout(const Duration(seconds: 120));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return MeetingExtractionResult.fromJson(data);
    } else {
      final errorObj = jsonDecode(response.body);
      final detail = errorObj['detail'] ?? 'Failed to extract meeting intelligence.';
      throw Exception(detail);
    }
  }

  Future<MeetingExtractionResult> extractMeetingAudio(List<int> bytes, String filename, {String? model}) async {
    final uri = Uri.parse('$baseUrl/api/meeting/extract-audio');
    final request = http.MultipartRequest('POST', uri);

    if (model != null) {
      request.fields['model'] = model;
    }

    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: filename,
      ),
    );

    final streamedResponse = await request.send().timeout(const Duration(seconds: 120));
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return MeetingExtractionResult.fromJson(data);
    } else {
      final errorObj = jsonDecode(response.body);
      final detail = errorObj['detail'] ?? 'Failed to extract meeting audio.';
      throw Exception(detail);
    }
  }

  Future<List<SampleTranscriptModel>> fetchSampleTranscripts() async {
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl/api/meeting/samples'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final List<dynamic> list = jsonDecode(response.body);
        return list.map((m) => SampleTranscriptModel.fromJson(m)).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }
}
