import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:csv/csv.dart';

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? _extractedText;
  XFile? _imageFile;

  Future<void> _pickAndExtractText() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera);
    if (pickedFile == null) return;
    final inputImage = InputImage.fromFilePath(pickedFile.path);
    final textRecognizer = TextRecognizer();
    final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
    setState(() {
      _imageFile = pickedFile;
      _extractedText = recognizedText.text;
    });
  }

  Future<void> _saveToFirebase() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
    final ref = FirebaseStorage.instance
        .ref('reports/$uid/${DateTime.now().millisecondsSinceEpoch}.jpg');
    await ref.putFile(File(_imageFile!.path));
    final imageUrl = await ref.getDownloadURL();
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('reports')
        .add({
      'text': _extractedText,
      'imageUrl': imageUrl,
      'timestamp': FieldValue.serverTimestamp(),
      'tags': _generateTags(_extractedText!),
    });
  }

  List<String> _generateTags(String text) {
    final lower = text.toLowerCase();
    final tags = <String>[];
    if (lower.contains("hemoglobin")) tags.add("Hemoglobin");
    if (lower.contains("glucose")) tags.add("Glucose");
    if (lower.contains("cholesterol")) tags.add("Cholesterol");
    if (lower.contains("cbc")) tags.add("CBC");
    if (lower.contains("thyroid")) tags.add("Thyroid");
    return tags;
  }

  Future<void> _exportCSV() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
    final query = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('reports')
        .orderBy('timestamp', descending: true)
        .get();
    final rows = [
      ['Text', 'ImageURL', 'Timestamp', 'Tags']
    ];
    for (var doc in query.docs) {
      final data = doc.data();
      rows.add([
        data['text'] ?? '',
        data['imageUrl'] ?? '',
        data['timestamp']?.toDate().toString() ?? '',
        (data['tags'] as List<dynamic>?)?.join(', ') ?? '',
      ]);
    }
    String csv = const ListToCsvConverter().convert(rows);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/reports.csv');
    await file.writeAsString(csv);
    await Share.shareFiles([file.path], text: 'Medical Reports CSV');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Scan Medical Report")),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            ElevatedButton(onPressed: _pickAndExtractText, child: Text("Scan Report")),
            if (_extractedText != null) ...[
              Expanded(child: SingleChildScrollView(child: Text(_extractedText!))),
              SizedBox(height: 8),
              ElevatedButton(onPressed: _saveToFirebase, child: Text("Save to Firebase")),
              ElevatedButton(onPressed: _exportCSV, child: Text("Export CSV")),
            ],
          ],
        ),
      ),
    );
  }
}
