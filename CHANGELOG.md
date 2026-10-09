# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-10-09

### Added

- Initial release of `Makeup.Lexers.LmmlLexer`.
- LMML inline embed support: `@@@name.ext ... @@@` blocks with `:string_delimiter` fences and `:name_entity` embed identifiers.
- LMML external reference support: `@name.ext` entity mentions with punctuation boundary detachment.
- Sub-lexer delegation for embedded files and fenced code blocks based on file extension and language tags.
- Full CommonMark and GFM support:
  - ATX headings (`#` through `######`) and Setext headings (`===`, `---`).
  - Inline code (`code` and double-backtick spans).
  - Emphasis and formatting (`*italic*`, `_italic_`, `**bold**`, `__bold__`, `~~strikethrough~~`).
  - Bulleted, ordered, and task list items (`- [ ]`, `- [x]`).
  - Blockquotes (`>`).
  - Thematic breaks / horizontal rules (`---`, `***`, `___`).
  - Links, images, and reference definitions (`[text](...)`, `![alt](...)`, `[id]: ...`).
  - Tables with pipes and alignment rows.
  - HTML tags, entities, and multiline comments.
  - Autolinks and raw URLs.
- 100% roundtrip guarantee (`input |> LmmlLexer.lex() |> Makeup.Lexer.unlex() == input`).
- Automatic registration in Makeup for `"lmml"`, `"markdown"`, and `"md"` names, and `".lmml"`, `".md"`, `".markdown"` file extensions.
- GitHub Actions CI and Release workflows.
