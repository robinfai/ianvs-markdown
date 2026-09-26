import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

// Flutter bundles and signs this code asset along with the app. Cargo is only
// needed on the build machine; runtime rendering uses FFI, never a subprocess.
void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final config = input.config.code;
    final (triple, filename) = switch ((
      config.targetOS,
      config.targetArchitecture,
    )) {
      (OS.macOS, Architecture.arm64) => (
        'aarch64-apple-darwin',
        'libianvs_svg.dylib',
      ),
      (OS.macOS, Architecture.x64) => (
        'x86_64-apple-darwin',
        'libianvs_svg.dylib',
      ),
      (OS.linux, Architecture.x64) => (
        'x86_64-unknown-linux-gnu',
        'libianvs_svg.so',
      ),
      (OS.linux, Architecture.arm64) => (
        'aarch64-unknown-linux-gnu',
        'libianvs_svg.so',
      ),
      (OS.windows, Architecture.x64) => (
        'x86_64-pc-windows-msvc',
        'ianvs_svg.dll',
      ),
      _ => throw UnsupportedError(
        'Mermaid vector preprocessing supports desktop targets only: '
        '${config.targetOS}/${config.targetArchitecture}',
      ),
    };
    final root = input.packageRoot.resolve('rust/');
    final target = input.outputDirectoryShared.resolve('cargo/');
    final cargoHome =
        Platform.environment['CARGO_HOME'] ??
        '${Platform.environment['HOME'] ?? Platform.environment['USERPROFILE']}/.cargo';
    final cargo = File(
      '$cargoHome/bin/cargo${Platform.isWindows ? '.exe' : ''}',
    );
    final environment = <String, String>{};
    if (config.targetOS == OS.macOS) {
      // Hooks retain Xcode's compiler PATH but filter out SDKROOT. Unlike the
      // /usr/bin shim, the toolchain's cc needs the SDK specified explicitly.
      final sdk = await Process.run('/usr/bin/xcrun', [
        '--sdk',
        'macosx',
        '--show-sdk-path',
      ]);
      if (sdk.exitCode != 0) {
        throw StateError('Cannot locate the macOS SDK: ${sdk.stderr}');
      }
      environment['SDKROOT'] = (sdk.stdout as String).trim();
      environment['MACOSX_DEPLOYMENT_TARGET'] = '12.0';
      final compiler = config.cCompiler?.compiler.toFilePath();
      if (compiler != null) {
        environment['CC'] = compiler;
        environment['CARGO_TARGET_${triple.replaceAll('-', '_').toUpperCase()}_LINKER'] =
            compiler;
      }
    }
    final result =
        await Process.run(cargo.existsSync() ? cargo.path : 'cargo', [
          'build',
          '--release',
          '--locked',
          '--manifest-path',
          root.resolve('Cargo.toml').toFilePath(),
          '--target',
          triple,
          '--target-dir',
          target.toFilePath(),
        ], environment: environment);
    if (result.exitCode != 0) {
      throw StateError(
        'Cargo failed to build the Mermaid SVG bridge. Install Rust and '
        'the $triple target.\n${result.stdout}\n${result.stderr}',
      );
    }
    final library = await File.fromUri(
      target.resolve('$triple/release/$filename'),
    ).copy(input.outputDirectory.resolve(filename).toFilePath());
    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'src/native_svg_bridge.dart',
        linkMode: DynamicLoadingBundled(),
        file: library.uri,
      ),
    );
    output.dependencies.addAll([
      root.resolve('Cargo.toml'),
      root.resolve('Cargo.lock'),
      ...Directory.fromUri(
        root.resolve('src/'),
      ).listSync(recursive: true).whereType<File>().map((file) => file.uri),
    ]);
  });
}
