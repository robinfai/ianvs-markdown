const largeDocumentTail = 'L07 end 中文😀';
final largeDocuments = <String, String>{
  'lineLength': '${'a' * 4097}\n$largeDocumentTail',
  'syntaxTokens': '${'**x**\n' * 1100}$largeDocumentTail',
  'sourceLength': '${'${'a' * 1023}\n' * 1025}$largeDocumentTail',
};
