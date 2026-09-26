class MermaidRenderResult {
  const MermaidRenderResult({
    required this.source,
    required this.svg,
    required this.optionsJson,
    this.layoutJson,
    this.engineVersion,
    this.fromCache = false,
    this.width,
    this.height,
    this.preprocessingIdentity,
  });

  final String source;
  final String svg;
  final String optionsJson;
  final String? layoutJson;
  final String? engineVersion;
  final bool fromCache;
  final double? width;
  final double? height;
  final String? preprocessingIdentity;
}

class MermaidValidationResult {
  const MermaidValidationResult({
    required this.valid,
    this.raw,
    this.errorMessage,
    this.code,
    this.codeName,
  });

  final bool valid;
  final Object? raw;
  final String? errorMessage;
  final int? code;
  final String? codeName;
}
