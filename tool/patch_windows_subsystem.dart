import 'dart:io';
import 'dart:typed_data';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run tool/patch_windows_subsystem.dart <exe>');
    exit(1);
  }

  final file = File(args.first);
  if (!file.existsSync()) {
    stderr.writeln('File not found: ${file.path}');
    exit(1);
  }

  final bytes = file.readAsBytesSync();
  final bd = ByteData.sublistView(bytes);

  if (bytes.length < 0x40 || bytes[0] != 0x4D || bytes[1] != 0x5A) {
    stderr.writeln('Not a valid MZ executable: ${file.path}');
    exit(1);
  }

  final peOffset = bd.getUint32(0x3C, Endian.little);
  if (peOffset + 0x60 > bytes.length ||
      bytes[peOffset] != 0x50 ||
      bytes[peOffset + 1] != 0x45 ||
      bytes[peOffset + 2] != 0x00 ||
      bytes[peOffset + 3] != 0x00) {
    stderr.writeln('Not a valid PE header: ${file.path}');
    exit(1);
  }

  final optHeaderOffset = peOffset + 24;
  final magic = bd.getUint16(optHeaderOffset, Endian.little);
  if (magic != 0x10B && magic != 0x20B) {
    stderr.writeln('Unsupported PE OptionalHeader magic: 0x${magic.toRadixString(16)}');
    exit(1);
  }

  final subsystemOffset = optHeaderOffset + 68;
  final current = bd.getUint16(subsystemOffset, Endian.little);
  if (current == 2) {
    stdout.writeln('${file.path} already uses WINDOWS_GUI subsystem.');
    return;
  }

  bd.setUint16(subsystemOffset, 2, Endian.little);
  file.writeAsBytesSync(bytes, flush: true);
  stdout.writeln(
    'Patched ${file.path} PE subsystem from $current -> 2 (WINDOWS_GUI).',
  );
}
