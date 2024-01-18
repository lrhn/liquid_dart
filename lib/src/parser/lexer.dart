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
  static const _tableSize = 128;
  // Table of table of token-creators that can start at a given ASCII character,
  // for the first 128 ASCII characters.
  static final List<List<_TokenCreator>?> _tokenCreatorTable = _createTokenCreatorTable();

  static List<_TokenCreator> _tokenCreatorsForNextChar(int nextChar) {
    if (nextChar >= 0 && nextChar < _tableSize) {
      var tokenCreators = _tokenCreatorTable[nextChar];
      if (tokenCreators != null) return tokenCreators;
    }
    return const <_TokenCreator>[];
  }

  static List<List<_TokenCreator>?> _createTokenCreatorTable() {
    var table = List<List<_TokenCreator>?>.filled(_tableSize, null);
    // Adds token creator for the start-characters in `firstChars`,
    // which can contain single characters or `A-Z` ranges, like a RegExp
    // character class (put an actual `-` at either end).
    void addTokenCreator(String firstChars, _TokenCreator tokenCreator) {
      const dashChar = 0x2D;
      for (var i = 0; i < firstChars.length; i++) {
        var code = firstChars.codeUnitAt(i);
        var endCode = code;
        if (i + 2 < firstChars.length && firstChars.codeUnitAt(i + 1) == dashChar) {
          endCode = firstChars.codeUnitAt(i + 2);
          i += 2;
        }
        while (code <= endCode) {
          (table[code] ??= []).add(tokenCreator);
          code++;
        }
      }
    }

    addTokenCreator('!=<>', _TokenCreator.re(TokenType.comparison, r'[=!]=|<[=>]?|>=?'));
    addTokenCreator("'", _TokenCreator.re(TokenType.single_string, r"'.*?'"));
    addTokenCreator('"', _TokenCreator.re(TokenType.double_string, r'".*?"'));
    addTokenCreator('-0-9', _TokenCreator.re(TokenType.number, r'-?\d+(?:\.\d+)?'));
    addTokenCreator('a-zA-Z_', _TokenCreator.re(TokenType.identifier, r'[a-zA-Z_][\w-]*\??'));
    addTokenCreator('.', _TokenCreator(TokenType.dotdot, '..'));
    addTokenCreator('|', _TokenCreator(TokenType.pipe, '|'));
    addTokenCreator('.', _TokenCreator(TokenType.dot, '.'));
    addTokenCreator('=', _TokenCreator(TokenType.assign, '='));
    addTokenCreator(':', _TokenCreator(TokenType.colon, ':'));
    addTokenCreator(',', _TokenCreator(TokenType.comma, ','));
    addTokenCreator('[', _TokenCreator(TokenType.open_square, '['));
    addTokenCreator(']', _TokenCreator(TokenType.close_square, ']'));
    addTokenCreator('(', _TokenCreator(TokenType.open_banana, '('));
    addTokenCreator(')', _TokenCreator(TokenType.close_banana, ')'));
    addTokenCreator('?', _TokenCreator(TokenType.question, '?'));
    addTokenCreator('-', _TokenCreator(TokenType.dash, '-'));

    return table;
  }

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

      var nextChar = ss.peekChar();
      if (nextChar != null) {
        for (final creator in _tokenCreatorsForNextChar(nextChar)) {
          final token = creator.scan(source, ss);
          if (token != null) {
            yield token;
            continue mainLoop;
          }
        }
      }

      // if we get here then we didn't match a token, or end,
      // so this `expect` call will throw.
      ss.expect(end);
    }

    yield Token(endType, ss.lastMatch![0]!, source: source, line: ss.line, column: ss.column - 2);
  }
}
