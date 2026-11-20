import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

void main() => runApp(const HelloScanApp());

class ScanCard {
  ScanCard({required this.id, this.front, this.back, this.name = '', this.title = '', this.company = '', this.email = '', this.phone = '', this.website = '', this.address = '', this.notes = ''});
  final String id;
  XFile? front;
  XFile? back;
  String name, title, company, email, phone, website, address, notes;
  bool reviewed = false;

  Map<String, dynamic> toJson() => {
    'person': {'name': name.isEmpty ? null : name, 'designation': title.isEmpty ? null : title},
    'organization': {'name': company.isEmpty ? null : company, 'website': website.isEmpty ? null : website},
    'contact': {'emails': email.isEmpty ? [] : [email], 'phones': phone.isEmpty ? [] : [phone]},
    'location': {'full_address': address.isEmpty ? null : address},
    'notes': notes.isEmpty ? null : notes,
    'source': {'sides': [if (front != null) 'front', if (back != null) 'back'], 'review_status': reviewed ? 'reviewed' : 'pending'},
  };
}

class HelloScanApp extends StatelessWidget {
  const HelloScanApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'HelloScan',
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark().copyWith(
      scaffoldBackgroundColor: const Color(0xff111216),
      colorScheme: const ColorScheme.dark(primary: Color(0xffa4f16b), secondary: Color(0xffa4f16b), surface: Color(0xff191a1e)),
      appBarTheme: const AppBarTheme(backgroundColor: Color(0xff111216), elevation: 0),
      inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: const Color(0xff1c1d20), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xff303137))), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xff303137)))),
    ),
    home: const BatchHome(),
  );
}

class BatchHome extends StatefulWidget {
  const BatchHome({super.key});
  @override
  State<BatchHome> createState() => _BatchHomeState();
}

class _BatchHomeState extends State<BatchHome> {
  final picker = ImagePicker();
  final cards = <ScanCard>[];
  ScanCard? selected;
  int counter = 0;

  Future<void> captureFront() async {
    final image = await picker.pickImage(source: ImageSource.camera, imageQuality: 92);
    if (image == null) return;
    final card = ScanCard(id: 'card-${++counter}', front: image);
    setState(() { cards.insert(0, card); selected = card; });
  }
  Future<void> captureBack() async {
    if (selected == null) { _snack('Select a card first, then capture its back.'); return; }
    final image = await picker.pickImage(source: ImageSource.camera, imageQuality: 92);
    if (image != null) setState(() => selected!.back = image);
  }
  Future<void> importGallery() async {
    final images = await picker.pickMultiImage(imageQuality: 92);
    if (images.isEmpty) return;
    setState(() {
      for (final image in images) {
        cards.insert(0, ScanCard(id: 'card-${++counter}', front: image));
      }
      selected = cards.first;
    });
  }
  void addEmpty() {
    final card = ScanCard(id: 'card-${++counter}');
    setState(() { cards.insert(0, card); selected = card; });
  }
  Future<void> exportBatch() async {
    final payload = {'schema': 'helloscan.contact-batch.v1', 'exported_at': DateTime.now().toUtc().toIso8601String(), 'total': cards.length, 'contacts': cards.map((c) => c.toJson()).toList()};
    final file = await FilePicker.platform.saveFile(fileName: 'helloscan-batch.json', bytes: utf8.encode(const JsonEncoder.withIndent('  ').convert(payload)), type: FileType.custom, allowedExtensions: ['json']);
    if (file != null) _snack('JSON exported successfully');
  }
  void _snack(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('HelloScan', style: TextStyle(fontWeight: FontWeight.bold)), actions: [IconButton(onPressed: cards.isEmpty ? null : exportBatch, icon: const Icon(Icons.file_download_outlined), tooltip: 'Export JSON')]),
      body: SafeArea(child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 18, 16, 12), child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('CARD CAPTURE WORKSPACE', style: TextStyle(color: Color(0xffa4f16b), letterSpacing: 1.3, fontSize: 11, fontWeight: FontWeight.w700)), const SizedBox(height: 8), const Text('From card to CRM-ready data.', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)), const SizedBox(height: 5), Text('${cards.length} cards in this batch', style: const TextStyle(color: Colors.white60))])),
        ])),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(onPressed: captureFront, icon: const Icon(Icons.camera_alt_outlined), label: const Text('Scan card')),
          OutlinedButton.icon(onPressed: captureBack, icon: const Icon(Icons.flip_outlined), label: const Text('Scan back')),
          OutlinedButton.icon(onPressed: importGallery, icon: const Icon(Icons.photo_library_outlined), label: const Text('Gallery')),
          OutlinedButton.icon(onPressed: addEmpty, icon: const Icon(Icons.add), label: const Text('Manual')),
        ])),
        const SizedBox(height: 10),
        Expanded(child: cards.isEmpty ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.contact_page_outlined, size: 44, color: Colors.white30), const SizedBox(height: 12), const Text('Your batch is empty', style: TextStyle(fontSize: 17)), const SizedBox(height: 5), const Text('Scan or import visiting cards to start.', style: TextStyle(color: Colors.white54))])) : Row(children: [
          SizedBox(width: 130, child: ListView.builder(itemCount: cards.length, itemBuilder: (_, i) { final card=cards[i]; return ListTile(dense: true, selected: card==selected, selectedTileColor: const Color(0xff27292d), leading: CircleAvatar(backgroundColor: const Color(0xff303137), child: Text((card.name.isEmpty?'?':card.name[0]).toUpperCase())), title: Text(card.name.isEmpty?'Untitled':card.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)), subtitle: Text(card.company.isEmpty?'No company':card.company, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10)), onTap: () => setState(() => selected=card)); })),
          const VerticalDivider(width: 1),
          Expanded(child: selected == null ? const SizedBox.shrink() : _editor(selected!)),
        ]))),
        if (cards.isNotEmpty) Container(padding: const EdgeInsets.all(12), decoration: const BoxDecoration(border: Border(top: BorderSide(color: Colors.white12))), child: Row(children: [Text('${cards.length} staged', style: const TextStyle(color: Colors.white54)), const Spacer(), TextButton.icon(onPressed: exportBatch, icon: const Icon(Icons.file_download_outlined), label: const Text('Export batch JSON'))])),
      ])),
    );
  }

  Widget _editor(ScanCard card) {
    Widget field(String label, String value, ValueChanged<String> onChanged) => Padding(padding: const EdgeInsets.only(bottom: 10), child: TextFormField(initialValue: value, decoration: InputDecoration(labelText: label), onChanged: onChanged));
    Widget imageTile(XFile? image, String side, VoidCallback onTap) => Expanded(child: InkWell(onTap: onTap, child: Container(height: 110, margin: const EdgeInsets.only(right: 6), decoration: BoxDecoration(border: Border.all(color: Colors.white12), borderRadius: BorderRadius.circular(10)), child: image == null ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.add_photo_alternate_outlined, color: Colors.white38), Text(side, style: const TextStyle(color: Colors.white38, fontSize: 11))])) : ClipRRect(borderRadius: BorderRadius.circular(9), child: Image.file(File(image.path), fit: BoxFit.cover)))) ;
    return ListView(padding: const EdgeInsets.all(12), children: [
      Row(children: [imageTile(card.front, 'Front', () async { final x=await picker.pickImage(source: ImageSource.camera); if(x!=null) setState(()=>card.front=x); }), imageTile(card.back, 'Back', () async { final x=await picker.pickImage(source: ImageSource.camera); if(x!=null) setState(()=>card.back=x); })]),
      const SizedBox(height: 14),
      field('Full name', card.name, (v)=>setState(()=>card.name=v)),
      field('Designation', card.title, (v)=>setState(()=>card.title=v)),
      field('Company', card.company, (v)=>setState(()=>card.company=v)),
      field('Email', card.email, (v)=>setState(()=>card.email=v)),
      field('Phone', card.phone, (v)=>setState(()=>card.phone=v)),
      field('Website', card.website, (v)=>setState(()=>card.website=v)),
      field('Address', card.address, (v)=>setState(()=>card.address=v)),
      field('Notes', card.notes, (v)=>setState(()=>card.notes=v)),
      FilledButton.tonal(onPressed: ()=>setState(()=>card.reviewed=true), child: Text(card.reviewed?'Reviewed ✓':'Mark reviewed')),
      TextButton.icon(onPressed: ()=>setState(()=>{ cards.remove(card); selected = cards.isEmpty ? null : cards.first; }), icon: const Icon(Icons.delete_outline, color: Colors.redAccent), label: const Text('Remove card', style: TextStyle(color: Colors.redAccent))),
    ]);
  }
}
