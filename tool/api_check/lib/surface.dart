import 'dart:collection';
import 'dart:convert';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:path/path.dart' as p;

/// A review baseline, not a semantic-version compatibility classifier.
///
/// Uses the resolved export namespace (including show/hide, parts and reexports).
/// Records declarations and their own public members, not inherited SDK members
/// or implementation behavior. Defaults/constant initializers are source forms,
/// not recursively evaluated values. Both additions and removals require review.
Future<Map<String, Object?>> readSurface(String entrypoint) async {
  final path = p.normalize(p.absolute(entrypoint));
  final collection = AnalysisContextCollection(includedPaths: [path]);
  try {
    final session = collection.contextFor(path).currentSession;
    final result = await session.getResolvedLibrary(path);
    if (result is! ResolvedLibraryResult) {
      throw StateError('Cannot resolve public library: $result');
    }
    final errors = result.units
        .expand((unit) => unit.diagnostics)
        .where((error) => error.severity == Severity.error);
    if (errors.isNotEmpty) throw StateError(errors.join('\n'));
    final exports = result.element.exportNamespace.definedNames2;
    // Errors in an exported library do not necessarily appear on the barrel.
    for (final library
        in exports.values
            .map((e) => e.library)
            .whereType<LibraryElement>()
            .toSet()) {
      final resolved = await session.getResolvedLibraryByElement(library);
      if (resolved is! ResolvedLibraryResult) {
        throw StateError('Cannot resolve ${library.uri}');
      }
      final errors = resolved.units
          .expand((unit) => unit.diagnostics)
          .where((error) => error.severity == Severity.error);
      if (errors.isNotEmpty) throw StateError(errors.join('\n'));
    }
    final entries = SplayTreeMap<String, Object?>();
    final symbols = SplayTreeMap<String, String>();
    final parsed = <LibraryElement, ParsedLibraryResult>{};

    AstNode? declaration(Element element) {
      final library = element.library!;
      final unit = parsed.putIfAbsent(library, () {
        final value = session.getParsedLibraryByElement(library);
        if (value is! ParsedLibraryResult) {
          throw StateError('Cannot parse ${library.uri}');
        }
        return value;
      });
      return unit.getFragmentDeclaration(element.firstFragment)?.node;
    }

    Map<String, Object?> describe(Element element) {
      final data = <String, Object?>{
        'kind': element.kind.displayName,
        if (element.metadata.hasDeprecated) 'deprecated': true,
      };
      if (element is TypeParameterizedElement) {
        data['typeParameters'] = [
          for (final parameter in element.typeParameters)
            {
              'name': parameter.name,
              'bound': parameter.bound?.getDisplayString(),
            },
        ];
      }
      if (element is ClassElement) {
        data['modifiers'] = [
          if (element.isAbstract) 'abstract',
          if (element.isBase) 'base',
          if (element.isFinal) 'final',
          if (element.isInterface) 'interface',
          if (element.isSealed) 'sealed',
          if (element.isMixinClass) 'mixin',
        ];
      }
      if (element is InterfaceElement) {
        data['supertype'] = element.supertype?.getDisplayString();
        data['interfaces'] = [
          for (final type in element.interfaces) type.getDisplayString(),
        ];
        data['mixins'] = [
          for (final type in element.mixins) type.getDisplayString(),
        ];
      }
      if (element is EnumElement) {
        data['values'] = [
          for (final field in element.fields.where((f) => f.isEnumConstant))
            field.name,
        ];
      }
      if (element is MixinElement) {
        data['constraints'] = [
          for (final type in element.superclassConstraints)
            type.getDisplayString(),
        ];
      }
      if (element is ExtensionElement) {
        data['on'] = element.extendedType.getDisplayString();
      }
      if (element is ExtensionTypeElement) {
        throw StateError(
          'Add explicit extension-type coverage before baselining ${element.name}',
        );
      }
      if (element is TypeAliasElement) {
        data['aliasedType'] = element.aliasedType.getDisplayString();
      }
      if (element is FunctionTypedElement) {
        data['returnType'] = element.returnType.getDisplayString();
        data['parameters'] = [
          for (final parameter in element.formalParameters)
            {
              'name': parameter.name,
              'type': parameter.type.getDisplayString(),
              'kind': parameter.isNamed ? 'named' : 'positional',
              'required': parameter.isRequired,
              if (parameter.isCovariant) 'covariant': true,
              if (parameter.hasDefaultValue)
                'default': normalizeExpression(parameter.defaultValueCode!),
            },
        ];
      }
      if (element is ExecutableElement) {
        data['static'] = element.isStatic;
        data['abstract'] = element.isAbstract;
      }
      if (element is ConstructorElement) {
        data['const'] = element.isConst;
        data['factory'] = element.isFactory;
      }
      if (element is VariableElement) {
        data['type'] = element.type.getDisplayString();
        data['const'] = element.isConst;
        data['final'] = element.isFinal;
        data['static'] = element.isStatic;
        data['late'] = element.isLate;
        if (element.isConst) {
          final node = declaration(element);
          if (node is VariableDeclaration) {
            data['initializer'] = node.initializer?.toSource();
          }
        }
      }
      return data;
    }

    for (final entry in exports.entries) {
      final element = entry.value;
      if (element.library == null || element is MultiplyDefinedElement) {
        throw StateError('Ambiguous export: ${entry.key}');
      }
      symbols[entry.key] = element.library!.uri.toString();
      entries[entry.key] = describe(
        element is PropertyAccessorElement && element.isOriginVariable
            ? element.variable
            : element,
      );
      if (element is InstanceElement) {
        final members = <Element>[
          if (element is InterfaceElement) ...element.constructors,
          ...element.fields.where((field) => field.isOriginDeclaration),
          ...element.getters.where((getter) => getter.isOriginDeclaration),
          ...element.setters.where((setter) => setter.isOriginDeclaration),
          ...element.methods,
        ];
        for (final member in members.where((member) => member.isPublic)) {
          final name = member is ConstructorElement && member.name == 'new'
              ? 'new'
              : member.lookupName ?? 'new';
          final key = '${entry.key}/${member.kind.displayName}:$name';
          if (entries.containsKey(key)) {
            throw StateError('Duplicate API key: $key');
          }
          entries[key] = describe(member);
        }
      }
    }
    return {'schemaVersion': 1, 'symbols': symbols, 'declarations': entries};
  } finally {
    await collection.dispose();
  }
}

String normalizeExpression(String code) {
  final parsed = parseString(content: 'const value = $code;');
  final declaration =
      parsed.unit.declarations.single as TopLevelVariableDeclaration;
  return declaration.variables.variables.single.initializer!.toSource();
}

String encodeSurface(Map<String, Object?> surface) =>
    '${const JsonEncoder.withIndent('  ').convert(surface)}\n';

List<String> compareSurface(
  Map<String, dynamic> expected,
  Map<String, dynamic> actual,
) {
  final differences = <String>[];
  for (final section in ['symbols', 'declarations']) {
    final before = Map<String, dynamic>.from(expected[section] as Map);
    final after = Map<String, dynamic>.from(actual[section] as Map);
    final names = {...before.keys, ...after.keys}.toList()..sort();
    for (final name in names) {
      if (!before.containsKey(name)) {
        differences.add('Added $section: $name');
      } else if (!after.containsKey(name)) {
        differences.add('Removed $section: $name');
      } else if (jsonEncode(before[name]) != jsonEncode(after[name])) {
        differences.add('Changed $section: $name');
      }
    }
  }
  if (expected['schemaVersion'] != actual['schemaVersion']) {
    differences.add('Changed schemaVersion');
  }
  return differences;
}
