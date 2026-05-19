import 'dart:io';
import 'package:path/path.dart' as p;

void main(List<String> args) async {
  try {
    await _buildAppAndScript();
    final issFile = _locateScript();
    await _patchScript(issFile);
    final compiler = _locateCompiler();
    await _compileInstaller(compiler, issFile);
    print('Installer successfully generated!');
  } catch (e) {
    stderr.writeln('Error: $e');
    exit(1);
  }
}

Future<void> _buildAppAndScript() async {
  print('Building app and generating Inno Setup script...');
  final process = await Process.start(
    'dart',
    ['run', 'inno_bundle:build', '--release', '--no-installer'],
    runInShell: true,
    mode: ProcessStartMode.inheritStdio,
  );
  final exitCode = await process.exitCode;
  if (exitCode != 0) {
    throw ProcessException('dart', ['run', 'inno_bundle:build'], 'Build failed', exitCode);
  }
}

File _locateScript() {
  final path = p.join(
    Directory.current.path,
    'build',
    'windows',
    'x64',
    'installer',
    'release',
    'inno-script.iss',
  );
  final file = File(path);
  if (!file.existsSync()) {
    throw FileSystemException('Generated ISS script not found', path);
  }
  return file;
}

Future<void> _patchScript(File file) async {
  print('Patching Inno Setup script to handle process termination and migration...');
  var content = await file.readAsString();

  final migratorPath = p.join(
    Directory.current.path,
    'build',
    'windows',
    'x64',
    'runner',
    'Release',
    'GalleVR-Migrator.exe',
  );
  final escapedMigratorPath = migratorPath.replaceAll('/', '\\');

  // Add the Migrator executable to [Files]
  if (content.contains('[Files]')) {
    content = content.replaceFirst(
      '[Files]',
      '[Files]\nSource: "$escapedMigratorPath"; DestDir: "{tmp}"; Flags: dontcopy',
    );
  } else {
    throw Exception('Could not find [Files] section in generated ISS file.');
  }

  final customPascalCode = r'''
function InitializeSetup(): Boolean;
var
  ResultCode: Integer;
begin
  Result := True;
  
  // Extract and run our elevated migrator helper if the old directory exists
  if DirExists('C:\Program Files\GalleVR') then
  begin
    ExtractTemporaryFile('GalleVR-Migrator.exe');
    ShellExec('runas', ExpandConstant('{tmp}\GalleVR-Migrator.exe'), '', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  end;
end;
''';

  if (content.contains('[Code]')) {
    content = content.replaceFirst('[Code]', '[Code]\n$customPascalCode');
  } else {
    content = '$content\n[Code]\n$customPascalCode';
  }

  await file.writeAsString(content);
}

File _locateCompiler() {
  final sysPath = 'C:\\Program Files (x86)\\Inno Setup 6\\ISCC.exe';
  final userProfile = Platform.environment['UserProfile'] ?? '';
  final userPath = p.join(userProfile, 'AppData', 'Local', 'Programs', 'Inno Setup 6', 'ISCC.exe');

  if (File(sysPath).existsSync()) {
    return File(sysPath);
  }
  if (userProfile.isNotEmpty && File(userPath).existsSync()) {
    return File(userPath);
  }
  throw FileSystemException('Inno Setup Compiler (ISCC.exe) not found. Please install Inno Setup 6.');
}

Future<void> _compileInstaller(File compiler, File issFile) async {
  print('Compiling installer...');
  final process = await Process.start(
    compiler.path,
    [issFile.path],
    runInShell: true,
    mode: ProcessStartMode.inheritStdio,
  );
  final exitCode = await process.exitCode;
  if (exitCode != 0) {
    throw ProcessException(compiler.path, [issFile.path], 'Compilation failed', exitCode);
  }
}
