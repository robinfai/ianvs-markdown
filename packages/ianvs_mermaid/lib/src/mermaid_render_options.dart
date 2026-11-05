import 'dart:convert';

enum MermaidSvgPipeline { parity, readable, resvgSafe }

const Map<String, String> kMermaidFlutterSvgThemeVariables = <String, String>{
  'primaryColor': '#f8fafc',
  'primaryTextColor': '#111827',
  'primaryBorderColor': '#94a3b8',
  'lineColor': '#475569',
  'secondaryColor': '#eef2ff',
  'secondaryTextColor': '#111827',
  'secondaryBorderColor': '#818cf8',
  'tertiaryColor': '#ffffff',
  'tertiaryTextColor': '#111827',
  'tertiaryBorderColor': '#cbd5e1',
  'edgeLabelBackground': '#ffffff',
  'clusterBkg': '#f8fafc',
  'clusterBorder': '#cbd5e1',
  'labelTextColor': '#111827',
  'textColor': '#111827',
  'mainBkg': '#f8fafc',
  'nodeBorder': '#94a3b8',
  'titleColor': '#111827',
};

extension MermaidSvgPipelineWire on MermaidSvgPipeline {
  String get wireName => switch (this) {
    MermaidSvgPipeline.parity => 'parity',
    MermaidSvgPipeline.readable => 'readable',
    MermaidSvgPipeline.resvgSafe => 'resvg-safe',
  };
}

class MermaidRenderOptions {
  const MermaidRenderOptions({
    this.diagramId,
    this.pipeline = MermaidSvgPipeline.resvgSafe,
    this.theme = 'default',
    this.themeVariables = kMermaidFlutterSvgThemeVariables,
    this.fontFamily,
    this.rootBackgroundColor = 'transparent',
    this.viewportWidth,
    this.viewportHeight,
    this.fixedToday,
    this.fixedLocalOffsetMinutes,
    this.resourceProfile = 'interactive',
    this.maxSourceBytes = 524288,
    this.maxSvgBytes = 8 * 1024 * 1024,
    this.maxModelItems,
  });

  final String? diagramId;
  final MermaidSvgPipeline pipeline;
  final String theme;
  final Map<String, String> themeVariables;
  final String? fontFamily;
  final String rootBackgroundColor;
  final double? viewportWidth;
  final double? viewportHeight;
  final String? fixedToday;
  final int? fixedLocalOffsetMinutes;
  final String resourceProfile;
  final int maxSourceBytes;
  final int maxSvgBytes;
  final int? maxModelItems;

  Map<String, Object?> toJson() {
    final mergedThemeVariables = <String, Object?>{
      ...themeVariables,
      if (fontFamily != null) 'fontFamily': fontFamily,
    };
    return <String, Object?>{
      'version': 2,
      if (fixedToday != null) 'fixed_today': fixedToday,
      if (fixedLocalOffsetMinutes != null)
        'fixed_local_offset_minutes': fixedLocalOffsetMinutes,
      'site_config': <String, Object?>{
        'theme': theme,
        'look': 'classic',
        'layout': 'dagre',
        if (mergedThemeVariables.isNotEmpty)
          'themeVariables': mergedThemeVariables,
      },
      'layout': <String, Object?>{
        if (viewportWidth != null) 'container_width': viewportWidth,
        if (viewportHeight != null) 'container_height': viewportHeight,
      },
      'environment': <String, Object?>{'text_measurement': 'deterministic'},
      'resources': <String, Object?>{
        'profile': resourceProfile,
        'limits': <String, Object?>{
          'max_source_bytes': maxSourceBytes,
          'max_svg_bytes': maxSvgBytes,
          if (maxModelItems != null) 'max_model_items': maxModelItems,
        },
      },
      'svg': <String, Object?>{
        if (diagramId != null) 'diagram_id': diagramId,
        'pipeline': pipeline.wireName,
        'root_background_color': rootBackgroundColor,
      },
    };
  }

  String toOptionsJson() => jsonEncode(toJson());

  static const flutterSvgDefault = MermaidRenderOptions();
}
