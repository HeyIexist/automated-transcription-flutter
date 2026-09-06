import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../models/meeting_extraction.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';

class MeetingScreen extends StatefulWidget {
  final ApiService apiService;

  const MeetingScreen({super.key, required this.apiService});

  @override
  State<MeetingScreen> createState() => _MeetingScreenState();
}

class _MeetingScreenState extends State<MeetingScreen> {
  final TextEditingController _transcriptController = TextEditingController();
  final FirestoreService _firestoreService = FirestoreService();

  bool _isLoading = false;
  bool _isSavingToCloud = false;
  String? _cloudSavedRecordId;
  String? _activeMeetingTitle;
  String? _errorMessage;
  MeetingExtractionResult? _result;
  List<SampleTranscriptModel> _samples = [];
  int _inputMode = 0; // 0 = Text Transcript, 1 = Audio Recording
  String? _selectedAudioFileName;

  @override
  void initState() {
    super.initState();
    _loadSamples();
  }

  Future<void> _loadSamples() async {
    final samples = await widget.apiService.fetchSampleTranscripts();
    if (mounted) {
      setState(() {
        _samples = samples;
      });
    }
  }

  void _loadSampleIntoInput(SampleTranscriptModel sample) {
    setState(() {
      _transcriptController.text = sample.transcript;
      _activeMeetingTitle = sample.title;
      _errorMessage = null;
      _cloudSavedRecordId = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Loaded sample: "${sample.title}"'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _saveToCloud({bool showSnackbar = true}) async {
    if (_result == null) return;
    final auth = context.read<AuthProvider>();
    final user = auth.currentUser;
    if (user == null) return;

    setState(() => _isSavingToCloud = true);

    String title = _activeMeetingTitle ?? _selectedAudioFileName ?? '';
    if (title.isEmpty && _transcriptController.text.isNotEmpty) {
      final lines = _transcriptController.text.split('\n');
      final firstLine = lines.firstWhere((l) => l.trim().isNotEmpty, orElse: () => 'Meeting Transcript').trim();
      title = firstLine.length > 35 ? '${firstLine.substring(0, 35)}...' : firstLine;
    }
    if (title.isEmpty) {
      title = 'Meeting Intelligence (${DateTime.now().month}/${DateTime.now().day})';
    }

    final docId = await _firestoreService.saveMeetingRecord(
      userId: user.uid,
      title: title,
      result: _result!,
      rawTranscript: _transcriptController.text,
    );

    if (mounted) {
      setState(() {
        _isSavingToCloud = false;
        _cloudSavedRecordId = docId;
      });
      if (showSnackbar) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.cloud_done_rounded, color: Colors.white, size: 20),
                SizedBox(width: 10),
                Text('Saved transcription & intelligence to Cloud Firestore!'),
              ],
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _processExtraction() async {
    final transcript = _transcriptController.text.trim();
    if (transcript.isEmpty) {
      setState(() {
        _errorMessage = 'Transcript input cannot be empty. Please paste or select a sample transcript.';
        _result = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _cloudSavedRecordId = null;
    });

    try {
      final res = await widget.apiService.extractMeetingIntelligence(transcript);
      if (mounted) {
        setState(() {
          _result = res;
          _isLoading = false;
        });
        // Auto-save transcription to cloud
        _saveToCloud(showSnackbar: false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _pickAndProcessAudio() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['wav', 'mp3', 'm4a', 'flac', 'ogg', 'aac'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.bytes == null || file.bytes!.isEmpty) {
        setState(() {
          _errorMessage = 'Selected audio file is empty. Please choose a valid recording.';
          _result = null;
        });
        return;
      }

      setState(() {
        _selectedAudioFileName = file.name;
        _activeMeetingTitle = file.name;
        _isLoading = true;
        _errorMessage = null;
        _cloudSavedRecordId = null;
      });

      final res = await widget.apiService.extractMeetingAudio(
        file.bytes!,
        file.name,
      );

      if (mounted) {
        setState(() {
          _result = res;
          if (res.transcribedText != null && res.transcribedText!.isNotEmpty) {
            _transcriptController.text = res.transcribedText!;
          }
          _isLoading = false;
        });
        // Auto-save audio transcription to cloud
        _saveToCloud(showSnackbar: false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  void _addNewActionItem() {
    if (_result == null) return;
    setState(() {
      _result!.actionItems.add(
        ActionItemModel(
          task: 'New custom action item',
          owner: 'Unassigned',
          dueDate: 'Not specified',
          confidence: 1.0,
          isCompleted: false,
        ),
      );
    });
  }

  void _copyResultToClipboard() {
    if (_result == null) return;
    final buffer = StringBuffer();
    buffer.writeln('=== MEETING SUMMARY ===');
    buffer.writeln(_result!.summary);
    buffer.writeln('\n=== KEY DECISIONS ===');
    for (var d in _result!.keyDecisions) {
      buffer.writeln('• $d');
    }
    buffer.writeln('\n=== ACTION ITEMS ===');
    for (var item in _result!.actionItems) {
      final status = item.isCompleted ? '[X]' : '[ ]';
      buffer.writeln('$status Task: ${item.task} | Owner: ${item.owner} | Due: ${item.dueDate}');
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied summary & action items to clipboard!')),
    );
  }

  void _showCloudHistoryModal(BuildContext context, String userId, bool isDark) {
    final cardBg = isDark ? AppTheme.surfaceCardDark : AppTheme.surfaceCardLight;
    final inputBg = isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight;
    final borderColor = isDark ? AppTheme.borderDark : AppTheme.borderLight;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          width: 700,
          height: 600,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryBlue.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.cloud_done_rounded, color: AppTheme.primaryBlue, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'Cloud Transcriptions History',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'Realtime cloud database entries saved in Firebase',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Expanded(
                child: StreamBuilder<List<MeetingRecord>>(
                  stream: _firestoreService.getMeetingRecordsStream(userId),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator(color: AppTheme.primaryBlue));
                    }

                    final records = snapshot.data ?? [];
                    if (records.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.cloud_off_rounded, size: 48, color: Colors.grey.withValues(alpha: 0.5)),
                            const SizedBox(height: 12),
                            const Text(
                              'No Cloud Transcriptions Found',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Transcribe a meeting or upload an audio file to save your first record.',
                              style: TextStyle(fontSize: 13, color: Colors.grey),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.separated(
                      itemCount: records.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final record = records[index];
                        final res = record.result;
                        final dateStr = '${record.createdAt.month}/${record.createdAt.day}/${record.createdAt.year} ${record.createdAt.hour.toString().padLeft(2, '0')}:${record.createdAt.minute.toString().padLeft(2, '0')}';

                        return Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: inputBg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: borderColor),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Row(
                                      children: [
                                        const Icon(Icons.description_outlined, color: AppTheme.primaryBlue, size: 20),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            record.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    dateStr,
                                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                res.summary,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 13, color: isDark ? Colors.grey.shade300 : Colors.black87, height: 1.4),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Wrap(
                                    spacing: 8,
                                    children: [
                                      Chip(
                                        padding: EdgeInsets.zero,
                                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        labelStyle: const TextStyle(fontSize: 11),
                                        label: Text('${res.wordCount} words'),
                                        backgroundColor: cardBg,
                                      ),
                                      Chip(
                                        padding: EdgeInsets.zero,
                                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        labelStyle: const TextStyle(fontSize: 11, color: Colors.green),
                                        label: Text('${res.actionItems.length} action items'),
                                        backgroundColor: Colors.green.withValues(alpha: 0.1),
                                      ),
                                      if (res.keyDecisions.isNotEmpty)
                                        Chip(
                                          padding: EdgeInsets.zero,
                                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          labelStyle: const TextStyle(fontSize: 11, color: Colors.amber),
                                          label: Text('${res.keyDecisions.length} decisions'),
                                          backgroundColor: Colors.amber.withValues(alpha: 0.1),
                                        ),
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Colors.redAccent),
                                        tooltip: 'Delete Cloud Record',
                                        onPressed: () async {
                                          await _firestoreService.deleteMeetingRecord(userId, record.id);
                                        },
                                      ),
                                      ElevatedButton.icon(
                                        onPressed: () {
                                          setState(() {
                                            _result = res;
                                            _activeMeetingTitle = record.title;
                                            _cloudSavedRecordId = record.id;
                                            if (record.rawTranscript != null && record.rawTranscript!.isNotEmpty) {
                                              _transcriptController.text = record.rawTranscript!;
                                            }
                                          });
                                          Navigator.of(ctx).pop();
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('Loaded record: "${record.title}"')),
                                          );
                                        },
                                        icon: const Icon(Icons.download_rounded, size: 16),
                                        label: const Text('Load into View'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppTheme.primaryBlue,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppTheme.darkBg : AppTheme.lightBg;

    return Scaffold(
      backgroundColor: bgColor,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 950;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                _buildHeader(isDark),
                const SizedBox(height: 20),
                if (isNarrow) ...[
                  _buildInputPane(isDark),
                  const SizedBox(height: 24),
                  _buildResultsPane(isDark),
                ] else ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left Pane: Input & Samples
                      Expanded(
                        flex: 4,
                        child: _buildInputPane(isDark),
                      ),
                      const SizedBox(width: 24),
                      // Right Pane: Extracted Intelligence View
                      Expanded(
                        flex: 6,
                        child: _buildResultsPane(isDark),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    final cardBg = isDark ? AppTheme.surfaceCardDark : AppTheme.surfaceCardLight;
    final borderColor = isDark ? AppTheme.borderDark : AppTheme.borderLight;
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 12,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.assignment_turned_in_rounded, color: AppTheme.primaryBlue, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Meeting Intelligence & Action Item Extractor',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Extract executive summary, key decisions, and action items (Task, Owner, Due Date) with zero hallucination guarantee.',
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (user != null)
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _showCloudHistoryModal(context, user.uid, isDark),
                  icon: const Icon(Icons.cloud_done_rounded, color: Colors.white, size: 18),
                  label: const Text('Cloud History', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryBlue,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: borderColor),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: AppTheme.primaryBlue,
                        child: Text(
                          user.name.isNotEmpty ? user.name[0].toUpperCase() : 'U',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            user.name,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            user.email,
                            style: const TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        icon: const Icon(Icons.logout_rounded, size: 18, color: Colors.redAccent),
                        tooltip: 'Sign Out',
                        onPressed: () => auth.logout(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildInputPane(bool isDark) {
    final cardBg = isDark ? AppTheme.surfaceCardDark : AppTheme.surfaceCardLight;
    final borderColor = isDark ? AppTheme.borderDark : AppTheme.borderLight;
    final inputBg = isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Mode Toggle Bar (Text vs Audio)
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: inputBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _inputMode = 0),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _inputMode == 0 ? AppTheme.primaryBlue : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.description_outlined,
                            size: 16,
                            color: _inputMode == 0 ? Colors.white : Colors.grey,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Text Transcript',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: _inputMode == 0 ? Colors.white : Colors.grey,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _inputMode = 1),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _inputMode == 1 ? AppTheme.primaryBlue : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.mic_none_rounded,
                            size: 16,
                            color: _inputMode == 1 ? Colors.white : Colors.grey,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Audio Recording',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: _inputMode == 1 ? Colors.white : Colors.grey,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Content Based on Mode
          if (_inputMode == 0) ...[
            // TEXT INPUT MODE
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Paste Meeting Dialogue',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                if (_transcriptController.text.isNotEmpty)
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _transcriptController.clear();
                        _errorMessage = null;
                        _result = null;
                        _activeMeetingTitle = null;
                        _cloudSavedRecordId = null;
                      });
                    },
                    icon: const Icon(Icons.clear, size: 16),
                    label: const Text('Clear'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            // Sample Presets
            if (_samples.isNotEmpty) ...[
              Text(
                'Demo Sample Presets:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade400),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _samples.map((s) {
                  return ActionChip(
                    avatar: const Icon(Icons.description_outlined, size: 14, color: AppTheme.primaryBlue),
                    label: Text(s.title, style: const TextStyle(fontSize: 12)),
                    backgroundColor: inputBg,
                    onPressed: () => _loadSampleIntoInput(s),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
            ],
            // Input TextField
            SizedBox(
              height: 250,
              child: TextField(
                controller: _transcriptController,
                maxLines: null,
                expands: true,
                style: TextStyle(fontSize: 14, color: isDark ? Colors.white : Colors.black87, height: 1.5),
                decoration: InputDecoration(
                  hintText: 'Paste meeting transcript here...\n\nExample:\n"Arjun: Riya, can you send the updated pricing sheet by Friday?\nRiya: Yes, I\'ll do that by Friday EOD."',
                  hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                  filled: true,
                  fillColor: inputBg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: borderColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: borderColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.primaryBlue, width: 2),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _processExtraction,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome, color: Colors.white),
                label: Text(
                  _isLoading ? 'Processing...' : 'Extract Intelligence from Text',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ),
          ] else ...[
            // AUDIO UPLOAD MODE
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: inputBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.primaryBlue.withValues(alpha: 0.3), width: 2),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryBlue.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.cloud_upload_outlined,
                        size: 48,
                        color: AppTheme.primaryBlue,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Upload Meeting Audio File',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Transcribe speech-to-text and extract action items automatically.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.black26 : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Formats: .wav, .mp3, .m4a, .flac, .ogg',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey),
                      ),
                    ),
                    if (_selectedAudioFileName != null) ...[
                      const SizedBox(height: 16),
                      Chip(
                        avatar: const Icon(Icons.audiotrack, size: 16, color: AppTheme.primaryBlue),
                        label: Text(_selectedAudioFileName!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        backgroundColor: cardBg,
                      ),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _pickAndProcessAudio,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryBlue,
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : const Icon(Icons.folder_open_rounded, color: Colors.white),
                        label: Text(
                          _isLoading ? 'Transcribing & Extracting...' : 'Browse & Upload Audio File',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          // Error Display
          if (_errorMessage != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResultsPane(bool isDark) {
    final cardBg = isDark ? AppTheme.surfaceCardDark : AppTheme.surfaceCardLight;
    final borderColor = isDark ? AppTheme.borderDark : AppTheme.borderLight;
    final inputBg = isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight;

    if (_isLoading) {
      return Container(
        constraints: const BoxConstraints(minHeight: 520, minWidth: double.infinity),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              CircularProgressIndicator(color: AppTheme.primaryBlue),
              SizedBox(height: 20),
              Text(
                'Analyzing meeting transcript with Local LLM engine...',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 8),
              Text(
                'Connecting speaker dialogue, mapping tasks, owners, and due dates.',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    if (_result == null) {
      return Container(
        constraints: const BoxConstraints(minHeight: 520, minWidth: double.infinity),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.analytics_outlined, size: 72, color: Colors.grey.withValues(alpha: 0.4)),
              const SizedBox(height: 18),
              Text(
                'No Transcript Analyzed Yet',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Select a quick demo sample on the left or paste a transcript to begin.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    final res = _result!;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Toolbar
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryBlue.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Analyzed ${res.wordCount} words',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primaryBlue),
                    ),
                  ),
                  if (_cloudSavedRecordId != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.cloud_done_rounded, color: Colors.green, size: 14),
                          SizedBox(width: 6),
                          Text(
                            'Synced to Cloud',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  ElevatedButton.icon(
                    onPressed: _isSavingToCloud ? null : () => _saveToCloud(showSnackbar: true),
                    icon: _isSavingToCloud
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.cloud_upload_rounded, size: 16),
                    label: Text(_isSavingToCloud ? 'Saving...' : 'Save to Cloud'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryBlue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _copyResultToClipboard,
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Export Summary'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: inputBg,
                      foregroundColor: isDark ? Colors.white : Colors.black87,
                      elevation: 0,
                      side: BorderSide(color: borderColor),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Executive Summary Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.summarize_outlined, color: AppTheme.primaryBlue, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Executive Summary',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  res.summary,
                  style: TextStyle(fontSize: 14, color: isDark ? Colors.white : Colors.black87, height: 1.6),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Key Decisions Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.gavel_rounded, color: Colors.amber, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Key Decisions',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (res.keyDecisions.isEmpty)
                  const Text(
                    'No explicit key decisions recorded in this discussion.',
                    style: TextStyle(fontSize: 13, color: Colors.grey, fontStyle: FontStyle.italic),
                  )
                else
                  ...res.keyDecisions.map((decision) => Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.check_circle_outline, color: Colors.green, size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                decision,
                                style: TextStyle(fontSize: 14, color: isDark ? Colors.white : Colors.black87, height: 1.4),
                              ),
                            ),
                          ],
                        ),
                      )),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Low-Confidence Notes Banner
          if (res.lowConfidenceNotes.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Low-Confidence Dialogue / Inaudible Segments Flagged',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.orange),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...res.lowConfidenceNotes.map((note) => Text(
                        '• $note',
                        style: TextStyle(fontSize: 13, color: isDark ? Colors.white : Colors.black87),
                      )),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          // Action Items Table
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.task_alt, color: Colors.green, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Action Items (${res.actionItems.length})',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    TextButton.icon(
                      onPressed: _addNewActionItem,
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Add Row'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (res.actionItems.isEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: inputBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: const [
                        Icon(Icons.playlist_remove_rounded, size: 40, color: Colors.grey),
                        SizedBox(height: 12),
                        Text(
                          'No Action Items Detected',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'The meeting transcript was purely informational with zero assigned commitments (Zero Hallucination Verified).',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      decoration: BoxDecoration(
                        color: inputBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: borderColor),
                      ),
                      child: Table(
                        defaultVerticalAlignment: TableCellVerticalAlignment.top,
                        columnWidths: const {
                          0: FixedColumnWidth(48),
                          1: FlexColumnWidth(5),
                          2: FlexColumnWidth(2),
                          3: FlexColumnWidth(2),
                          4: FixedColumnWidth(48),
                        },
                        border: TableBorder(
                          horizontalInside: BorderSide(color: borderColor.withValues(alpha: 0.5)),
                        ),
                        children: [
                          // Table Header
                          TableRow(
                            decoration: BoxDecoration(color: cardBg),
                            children: const [
                              Padding(
                                padding: EdgeInsets.all(12),
                                child: Center(child: Text('Done', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey))),
                              ),
                              Padding(
                                padding: EdgeInsets.all(12),
                                child: Text('Task Description', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
                              ),
                              Padding(
                                padding: EdgeInsets.all(12),
                                child: Text('Owner', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
                              ),
                              Padding(
                                padding: EdgeInsets.all(12),
                                child: Text('Due Date', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
                              ),
                              Padding(
                                padding: EdgeInsets.all(12),
                                child: Text('', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                              ),
                            ],
                          ),
                          // Table Rows
                          ...res.actionItems.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final item = entry.value;
                            return TableRow(
                              children: [
                                // Checkbox
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  child: Center(
                                    child: Checkbox(
                                      value: item.isCompleted,
                                      activeColor: Colors.green,
                                      onChanged: (val) {
                                        setState(() {
                                          item.isCompleted = val ?? false;
                                        });
                                      },
                                    ),
                                  ),
                                ),
                                // Task Description
                                Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: TextFormField(
                                    initialValue: item.task,
                                    maxLines: null,
                                    keyboardType: TextInputType.multiline,
                                    style: TextStyle(
                                      fontSize: 13,
                                      height: 1.4,
                                      color: item.isCompleted
                                          ? Colors.grey
                                          : (isDark ? Colors.white : Colors.black87),
                                      decoration: item.isCompleted ? TextDecoration.lineThrough : null,
                                    ),
                                    decoration: const InputDecoration(
                                      border: InputBorder.none,
                                      isDense: true,
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                    onChanged: (val) => item.task = val,
                                  ),
                                ),
                                // Owner Badge
                                Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AppTheme.primaryBlue.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        item.owner,
                                        softWrap: true,
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primaryBlue),
                                      ),
                                    ),
                                  ),
                                ),
                                // Due Date Badge
                                Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.purple.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        item.dueDate,
                                        softWrap: true,
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.purple),
                                      ),
                                    ),
                                  ),
                                ),
                                // Delete Row Button
                                Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: IconButton(
                                    icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                                    onPressed: () {
                                      setState(() {
                                        res.actionItems.removeAt(idx);
                                      });
                                    },
                                  ),
                                ),
                              ],
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
