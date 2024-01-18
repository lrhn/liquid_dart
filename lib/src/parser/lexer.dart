import 'package:string_scanner/string_scanner.dart';

import '../model.dart';

class _TokenCreator {
  final TokenType type;
  final Pattern pattern;

  _TokenCreator(this.type, this.pattern);
  _TokenCreator.re(this.type, String pattern) : pattern = RegExp(pattern, dotAll: true);

  Token? scan(Source source, LineScanner ss) {
    final line = ss.line;
    final column = ss.column;
    if (ss.scan(pattern)) {
      return Token(type, ss.lastMatch![0]!, source: source, line: line, column: column);
    }
    return null;
  }
}

class Lexer {
  final List<_TokenCreator> tokenCreators = [
    _TokenCreator.re(TokenType.comparison, r'[=!]=|<[=>]?|>=?'),
    _TokenCreator.re(TokenType.single_string, r"'.*?'"),
    _TokenCreator.re(TokenType.double_string, r'".*?"'),
    _TokenCreator.re(TokenType.number, r'-?\d+(?:\.\d+)?'),
    _TokenCreator.re(TokenType.identifier, r'[a-zA-Z_][\w-]*\??'),
    _TokenCreator(TokenType.dotdot, '..'),
    _TokenCreator(TokenType.pipe, '|'),
    _TokenCreator(TokenType.dot, '.'),
    _TokenCreator(TokenType.assign, '='),
    _TokenCreator(TokenType.colon, ':'),
    _TokenCreator(TokenType.comma, ','),
    _TokenCreator(TokenType.open_square, '['),
    _TokenCreator(TokenType.close_square, ']'),
    _TokenCreator(TokenType.open_banana, '('),
    _TokenCreator(TokenType.close_banana, ')'),
    _TokenCreator(TokenType.question, '?'),
    _TokenCreator(TokenType.dash, '-'),
  ];

  final markup = _TokenCreator.re(TokenType.markup, r'(?:[^\s{]|\{(?![{%])|\s+?(?!\s|\{[{%]-))+');
  final whitespace = RegExp(r'\s*');

  Iterable<Token> tokenize(Source source) sync* {
    var ss = LineScanner(source.content, sourceUrl: source.file);
    while (!ss.isDone) {
      var token = markup.scan(source, ss);
      if (token != null) {
        yield token;
      }

      if (ss.matches(tagStart)) {
        yield* tokenizeTag(source, ss);
      } else if (ss.matches(varStart)) {
        yield* tokenizeVar(source, ss);
      }
    }
  }

  RegExp tagStart = RegExp(r'\{%-?|\s+\{%-');
  RegExp tagEnd = RegExp(r'%\}|-%\}\s*');
  Iterable<Token> tokenizeTag(Source source, LineScanner ss) => tokenizeNonMarkup(
        source,
        ss,
        TokenType.tag_start,
        tagStart,
        TokenType.tag_end,
        tagEnd,
      );

  RegExp varStart = RegExp(r'\{\{-?|\s+\{\{-');
  RegExp varEnd = RegExp(r'\}\}|-\}\}\s*');
  Iterable<Token> tokenizeVar(Source source, LineScanner ss) => tokenizeNonMarkup(
        source,
        ss,
        TokenType.var_start,
        varStart,
        TokenType.var_end,
        varEnd,
      );

  Iterable<Token> tokenizeNonMarkup(Source source, LineScanner ss, TokenType startType, Pattern start, TokenType endType, Pattern end) sync* {
    ss.expect(start);
    yield Token(startType, ss.lastMatch!.group(0)!, source: source, line: ss.line, column: ss.column - 2);

    mainLoop:
    while (true) {
      ss.scan(whitespace);
      if (ss.scan(end)) break;

      for (final creator in tokenCreators) {
        final token = creator.scan(source, ss);
        if (token != null) {
          yield token;
          continue mainLoop;
        }
      }

      // if we get here then we didn't match a token, or end,
      // so this `expect` call will throw.
      ss.expect(end);
    }

    yield Token(endType, ss.lastMatch![0]!, source: source, line: ss.line, column: ss.column - 2);
  }
}
