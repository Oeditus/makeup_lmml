<img src="stuff/img/logo-128.png" alt="makeup_lmml" width="128" align="right">

# MakeupLmml

[![CI](https://github.com/cure-lang/makeup_lmml/actions/workflows/ci.yml/badge.svg)](https://github.com/cure-lang/makeup_lmml/actions/workflows/ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/makeup_lmml.svg)](https://hex.pm/packages/makeup_lmml)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-purple.svg)](https://hexdocs.pm/makeup_lmml)
[![License](https://img.shields.io/hexpm/l/makeup_lmml.svg)](LICENSE)

A [Makeup](https://hex.pm/packages/makeup) lexer for [LMML](https://github.com/Oeditus/lmml) (Language Model Markup Language) narratives and [Markdown](https://commonmark.org/).

LMML is a strict superset of Markdown designed for structuring LLM conversations and multimodal payloads: any standard Markdown text is already valid LMML. This library provides syntax highlighting for both LMML constructs and full CommonMark formatting in ExDoc and any other tool using Makeup.

## Key Features

- **LMML Inline Embeds (`@@@name.ext ... @@@`)**: Highlighted with distinct delimiters (`:string_delimiter`), embed names (`:name_entity`), and sub-lexer delegation for the embed content based on its file extension (e.g. `@@@app.ex` highlights as Elixir, `@@@settings.yaml` as YAML/string).
- **LMML External References (`@name.ext`)**: Tokenized as entities (`:name_entity`), respecting LMML's punctuation detachment rules (e.g., `@diagram.png,`, `(see @image.png)`, and `@image.png*` cleanly isolate the reference from surrounding punctuation).
- **Sub-lexer Delegation**: Fenced code blocks (`` ```elixir ``) and inline embeds (`@@@manifest.json`) automatically delegate their bodies to installed Makeup lexers when available (e.g. `makeup_elixir`, `makeup_cure`, `makeup_diff`, `makeup_json`).
- **Full CommonMark & GFM Support**:
  - ATX headings (`# Heading` as `:generic_heading`, `## Subheading` as `:generic_subheading`)
  - Setext headings (`===` as `:generic_heading`, `---` as `:generic_subheading`)
  - Inline code (`code` and double-backtick spans as `:string_backtick`)
  - Emphasis (`*italic*`, `_italic_` as `:generic_emph`; `**bold**`, `__bold__` as `:generic_strong`)
  - Strikethrough (`~~deleted~~` as `:generic_deleted`)
  - Blockquotes (`> quote` as `:keyword`)
  - Bulleted and numbered lists, and task checkboxes (`- [ ]`, `- [x]` as `:keyword`)
  - Links, images, and reference definitions (`[text](...)`, `![alt](...)`, `[id]: ...`)
  - Tables (`| col1 | col2 |`)
  - HTML tags (`<div>`), multiline comments (`<!-- comment -->`), and entities (`&amp;`)
  - Thematic breaks / horizontal rules (`---`, `***`, `___`)
  - Autolinks (`<https://...>`, raw `https://...`)
- **100% Roundtrip Guarantee**: For any input text, `input |> LmmlLexer.lex() |> Makeup.Lexer.unlex() == input`.

## Installation

Add `makeup_lmml` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:makeup_lmml, "~> 0.1"}
  ]
end
```

The lexer automatically registers with Makeup on application start for:
- Language names: `"lmml"`, `"markdown"`, and `"md"`
- File extensions: `".lmml"`, `".md"`, and `".markdown"`

## Usage

### In ExDoc

Once added to your project, ExDoc will automatically highlight code blocks tagged with `lmml`, `markdown`, or `md`:

````markdown
```lmml
# Project Context

Please review @diagram.png before the meeting.

@@@settings.yaml
model: gpt-5
temperature: 0.2
@@@
```
````

### Direct Usage

```elixir
alias Makeup.Lexers.LmmlLexer

# Tokenize an LMML document:
tokens = LmmlLexer.lex("""
# Project Context

Please review @diagram.png before the meeting.

@@@settings.yaml
model: gpt-5
temperature: 0.2
@@@
""")

# Render HTML using Makeup:
html = Makeup.highlight(doc, lexer: LmmlLexer)
```

## Token Mapping

| Construct | Token Type | CSS Class |
| --- | --- | --- |
| Embed fence (`@@@`), Code fence (```` ``` ````) | `:string_delimiter` | `dl` |
| Embed name (`settings.yaml`), External ref (`@a.png`) | `:name_entity` | `ni` |
| Code block language hint (`elixir`) | `:name_class` | `nc` |
| Level-1 heading (`# Heading`, `===`) | `:generic_heading` | `gh` |
| Level 2–6 heading (`## Heading`, `---`) | `:generic_subheading` | `gu` |
| Bold text (`**bold**`, `__bold__`) | `:generic_strong` | `gs` |
| Italic text (`*italic*`, `_italic_`) | `:generic_emph` | `ge` |
| Strikethrough (`~~deleted~~`) | `:generic_deleted` | `gd` |
| Inline code (`code`) | `:string_backtick` | `sb` |
| Embed / code block body (fallback) | `:string` | `s` |
| Link text, Image alt, HTML tag | `:name_tag` | `nt` |
| Link URL, Image destination, HTML attribute | `:name_attribute` | `na` |
| Reference link identifier (`[id]:`) | `:name_label` | `nl` |
| List markers (`-`, `*`, `1.`), blockquotes (`>`) | `:keyword` | `k` |
| HTML comments (`<!-- ... -->`) | `:comment_multiline` | `cm` |
| Escaped characters (`\*`, `\@`) | `:string_escape` | `se` |
| Delimiters, brackets, table pipes | `:punctuation` | `p` |
| Prose and unclassified text | `:text` | (unstyled) |
| Whitespace and line breaks | `:whitespace` | `w` |

## License

MIT — see [LICENSE](LICENSE) for details.
