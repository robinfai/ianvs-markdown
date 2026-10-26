enum ReadingWidth {
  narrow(560),
  standard(720),
  wide(960);

  const ReadingWidth(this.pixels);
  final double pixels;
}

/// App-wide reading preferences; independent of document content and undo.
class ReadingPreferences {
  const ReadingPreferences._(
    this.fontSize,
    this.lineHeight,
    this.width,
    this.wrapCode,
  );
  static const defaults = ReadingPreferences._(
    14.5,
    1.58,
    ReadingWidth.standard,
    true,
  );

  factory ReadingPreferences({
    double fontSize = 14.5,
    double lineHeight = 1.58,
    ReadingWidth width = ReadingWidth.standard,
    bool wrapCode = true,
  }) => ReadingPreferences._(
    fontSize.isFinite ? fontSize.clamp(12, 28) : defaults.fontSize,
    lineHeight.isFinite ? lineHeight.clamp(1.2, 2.2) : defaults.lineHeight,
    width,
    wrapCode,
  );

  factory ReadingPreferences.fromJson(Object? value) {
    if (value is! Map) return defaults;
    return ReadingPreferences(
      wrapCode: value['wrapCode'] is bool ? value['wrapCode'] as bool : true,
      fontSize: value['fontSize'] is num
          ? (value['fontSize'] as num).toDouble()
          : defaults.fontSize,
      lineHeight: value['lineHeight'] is num
          ? (value['lineHeight'] as num).toDouble()
          : defaults.lineHeight,
      width:
          ReadingWidth.values
              .where((w) => w.name == value['width'])
              .firstOrNull ??
          defaults.width,
    );
  }
  final double fontSize;
  final double lineHeight;
  final ReadingWidth width;
  final bool wrapCode;
  ReadingPreferences copyWith({
    double? fontSize,
    double? lineHeight,
    ReadingWidth? width,
    bool? wrapCode,
  }) => ReadingPreferences(
    fontSize: fontSize ?? this.fontSize,
    lineHeight: lineHeight ?? this.lineHeight,
    width: width ?? this.width,
    wrapCode: wrapCode ?? this.wrapCode,
  );
  Map<String, Object> toJson() => {
    'fontSize': fontSize,
    'lineHeight': lineHeight,
    'width': width.name,
    'wrapCode': wrapCode,
  };
  @override
  bool operator ==(Object other) =>
      other is ReadingPreferences &&
      other.fontSize == fontSize &&
      other.lineHeight == lineHeight &&
      other.width == width &&
      other.wrapCode == wrapCode;
  @override
  int get hashCode => Object.hash(fontSize, lineHeight, width, wrapCode);
}
