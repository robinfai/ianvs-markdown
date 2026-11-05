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
      (OS.iOS, Architecture.arm64) => (
        config.iOS.targetSdk == IOSSdk.iPhoneSimulator
            ? 'aarch64-apple-ios-sim'
            : 'aarch64-apple-ios',
        'libianvs_svg.dylib',
      ),
      (OS.iOS, Architecture.x64) => ('x86_64-apple-ios', 'libianvs_svg.dylib'),
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
        'Unsupported Mermaid vector preprocessing target: '
        '${config.targetOS}/${config.targetArchitecture}',
      ),
    };
    if (config.targetOS == OS.macOS || config.targetOS == OS.iOS) {
      final sdkName = config.targetOS == OS.macOS
          ? 'macosx'
          : config.iOS.targetSdk.type;
      final sdkResult = await Process.run('/usr/bin/xcrun', [
        '--sdk',
        sdkName,
        '--show-sdk-path',
      ]);
      if (sdkResult.exitCode != 0) throw StateError('${sdkResult.stderr}');
      final arch = config.targetArchitecture == Architecture.arm64
          ? 'arm64'
          : 'x86_64';
      final platform = config.targetOS == OS.macOS
          ? 'macos12.0'
          : 'ios${config.iOS.targetVersion}.0${config.iOS.targetSdk == IOSSdk.iPhoneSimulator ? '-simulator' : ''}';
      final native = input.packageRoot.resolve('native/pele_jsc.c');
      final library = input.outputDirectory.resolve('libianvs_pele.dylib');
      // Keep the object file until Flutter creates the framework dSYM. Linking
      // a C source directly leaves a deleted temporary object in the debug map.
      final object = input.outputDirectory.resolve('pele_jsc.o');
      final compilerArguments = [
        '--sdk',
        sdkName,
        'clang',
        '-target',
        '$arch-apple-$platform',
        '-isysroot',
        (sdkResult.stdout as String).trim(),
      ];
      final compiled = await Process.run('/usr/bin/xcrun', [
        ...compilerArguments,
        '-std=c11',
        '-O2',
        '-g',
        '-Wall',
        '-Wextra',
        '-Werror',
        '-c',
        native.toFilePath(),
        '-o',
        object.toFilePath(),
      ]);
      if (compiled.exitCode != 0) {
        throw StateError('System JSC bridge compile: ${compiled.stderr}');
      }
      final linked = await Process.run('/usr/bin/xcrun', [
        ...compilerArguments,
        '-dynamiclib',
        '-Wl,-headerpad_max_install_names',
        '-framework',
        'JavaScriptCore',
        object.toFilePath(),
        '-o',
        library.toFilePath(),
        '-install_name',
        '@rpath/libianvs_pele.dylib',
      ]);
      if (linked.exitCode != 0) {
        throw StateError('System JSC bridge link: ${linked.stderr}');
      }
      output.assets.code.add(
        CodeAsset(
          package: input.packageName,
          name: 'src/native_pele_bridge.dart',
          linkMode: DynamicLoadingBundled(),
          file: library,
        ),
      );
      output.dependencies.add(native);
    }
    final root = input.packageRoot.resolve('rust/');
    final target = input.outputDirectoryShared.resolve('cargo/');
    final cargoHome =
        Platform.environment['CARGO_HOME'] ??
        '${Platform.environment['HOME'] ?? Platform.environment['USERPROFILE']}/.cargo';
    final cargo = File(
      '$cargoHome/bin/cargo${Platform.isWindows ? '.exe' : ''}',
    );
    final environment = <String, String>{};
    if (config.targetOS == OS.macOS || config.targetOS == OS.iOS) {
      // Hooks retain Xcode's compiler PATH but filter out SDKROOT. Unlike the
      // /usr/bin shim, the toolchain's cc needs the SDK specified explicitly.
      final sdk = await Process.run('/usr/bin/xcrun', [
        '--sdk',
        config.targetOS == OS.iOS ? config.iOS.targetSdk.type : 'macosx',
        '--show-sdk-path',
      ]);
      if (sdk.exitCode != 0) {
        throw StateError('Cannot locate the Apple SDK: ${sdk.stderr}');
      }
      environment['SDKROOT'] = (sdk.stdout as String).trim();
      // Cargo build scripts run on macOS even while the library targets iOS.
      // Use Apple's shim for host links; Xcode's toolchain cc has no default
      // macOS sysroot when invoked in an iPhone build environment.
      if (config.targetOS == OS.iOS) {
        environment['CARGO_TARGET_AARCH64_APPLE_DARWIN_LINKER'] = '/usr/bin/cc';
        environment['CARGO_TARGET_X86_64_APPLE_DARWIN_LINKER'] = '/usr/bin/cc';
      }
      if (config.targetOS == OS.iOS) {
        environment['IPHONEOS_DEPLOYMENT_TARGET'] =
            '${config.iOS.targetVersion}.0';
      } else {
        environment['MACOSX_DEPLOYMENT_TARGET'] = '12.0';
      }
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
      root.resolve('fonts/NotoSansCJKsc-Regular.otf'),
      ...Directory.fromUri(
        root.resolve('src/'),
      ).listSync(recursive: true).whereType<File>().map((file) => file.uri),
    ]);
  });
}
