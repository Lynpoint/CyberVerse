import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

Future<String> saveVoice(String id, String extension, Uint8List bytes) async {
  final root = await getApplicationDocumentsDirectory();
  final dir = Directory('${root.path}/voices');
  await dir.create(recursive: true);
  final file = File('${dir.path}/$id.$extension');
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

Future<void> removeVoice(String? path) async {
  if (path == null) return;
  final file = File(path);
  if (await file.exists()) await file.delete();
}
