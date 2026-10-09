defmodule Makeup.Lexers.LmmlLexer do
  @moduledoc """
  A `Makeup` lexer for LMML (Language Model Markup Language) narratives and Markdown.

  LMML is a strict superset of Markdown designed for LLM conversations and multimodal
  interactions. It adds two primary constructs to standard Markdown:

    * **Inline embeds** (`@@@name.ext ... @@@`) — self-contained blocks carrying named
      content directly in the narrative text.
    * **External references** (`@name.ext`) — inline references to named assets carried
      in a `.lmmlz` zip container or defined by inline embeds.

  Because LMML is a strict superset of CommonMark, this lexer also highlights standard
  Markdown documents, including:

    * ATX and Setext headings (`#`, `##`, `===`, `---`)
    * Fenced code blocks (`` ``` `` and `~~~`) with sub-lexer delegation
    * Inline code (`` `code` ``)
    * Emphasis and strikethrough (`*italic*`, `**bold**`, `~~deleted~~`)
    * Blockquotes (`> quote`)
    * Bulleted and numbered lists, and task checkboxes (`- [x]`)
    * Links and images (`[text](url)`, `![alt](url)`, `[ref]: url`)
    * Tables (`| col1 | col2 |`)
    * HTML tags, comments, and entities (`<!-- comment -->`, `&amp;`)
    * Autolinks and raw URLs (`https://...`)

  ## Token mapping

    * `:string_delimiter` — embed fences (`@@@`) and code fences (`` ``` ``)
    * `:name_entity` — external references (`@diagram.png`), embed names (`settings.yaml`),
      and HTML entities (`&copy;`)
    * `:name_class` / `:keyword` — language hints on fenced code blocks
    * `:generic_heading` — level-1 headings (`# Heading`, `===` underlines)
    * `:generic_subheading` — level 2–6 headings (`## Heading`, `---` underlines)
    * `:generic_strong` — bold text (`**bold**`, `__bold__`)
    * `:generic_emph` — emphasized text (`*italic*`, `_italic_`)
    * `:generic_deleted` — strikethrough text (`~~strikethrough~~`)
    * `:string_backtick` — inline code spans (`` `code` ``)
    * `:string` — embed/code block bodies without specific lexers, link titles
    * `:name_tag` — link text, image alt text, HTML tag names
    * `:name_attribute` — link URLs, image URLs, HTML attributes
    * `:name_label` — reference link identifiers (`[id]:`)
    * `:keyword` — list markers (`-`, `*`, `1.`), blockquote markers (`>`)
    * `:comment_multiline` — HTML comments (`<!-- ... -->`)
    * `:string_escape` — backslash-escaped characters (`\\*`, `\\@`)
    * `:punctuation` — delimiters, brackets, table bars, thematic breaks
    * `:whitespace` — spaces, tabs, and newlines
    * `:text` — prose and unclassified content

  ## Sub-lexer delegation

  When an inline embed (`@@@settings.yaml` or `@@@app.ex`) or fenced code block
  (`` ```elixir ``) specifies a recognized file extension or language name, the body
  content is highlighted using the registered Makeup lexer for that language when
  available. If no lexer is registered or if nested lexing fails, the body falls
  back to `:string` or `:text`.

  Sub-lexer delegation can be disabled by passing `handle_codeblocks: false` in `opts`.

  ## Registering the lexer

  The lexer is automatically registered on application start for the language names
  `"lmml"`, `"markdown"`, and `"md"`, and for the file extensions `".lmml"`, `".md"`,
  and `".markdown"`.
  """

  import NimbleParsec
  import Makeup.Lexer.Combinators

  @behaviour Makeup.Lexer

  ###################################################################
  # Step 1: tokenize the input
  ###################################################################

  # -- Whitespace and newlines ------------------------------------------

  newline =
    choice([string("\r\n"), string("\n"), string("\r")])
    |> token(:whitespace)

  spaces =
    ascii_string([?\s, ?\t], min: 1)
    |> token(:whitespace)

  # Rest of line not consuming newline
  line_tail = utf8_string([not: ?\n, not: ?\r], min: 1)

  # -- Escaped characters -----------------------------------------------

  escaped_char =
    string("\\")
    |> utf8_string([], 1)
    |> lexeme()
    |> token(:string_escape)

  # -- Embed fences (LMML) ----------------------------------------------
  #
  # Line starting with `@@@`: either `@@@name.ext` (open) or `@@@` (close).
  # Emitted as provisional `:__lmml_embed__` and resolved in `postprocess/2`.

  embed_fence =
    string("@@@")
    |> concat(optional(line_tail))
    |> lexeme()
    |> token(:__lmml_embed__)

  # -- Code fences (CommonMark) -----------------------------------------
  #
  # 3 or more backticks or tildes, plus optional lang and info string.
  # Emitted as provisional `:__code_fence__` and resolved in `postprocess/2`.

  code_fence_backtick =
    ascii_string([?`], min: 3)
    |> concat(optional(line_tail))
    |> lexeme()
    |> token(:__code_fence__)

  code_fence_tilde =
    ascii_string([?~], min: 3)
    |> concat(optional(line_tail))
    |> lexeme()
    |> token(:__code_fence__)

  # -- External references (LMML: `@name.ext`) --------------------------
  #
  # A bare `@` followed by non-whitespace characters.
  # Per LMML Language Reference (section 3.2), trailing ASCII punctuation
  # preceding whitespace or EOF (e.g. `@image.png,`, `@image.png)`,
  # `@image.png.`, `@image.png*`) is detached as its own token.

  @ascii_punct ~c",.!?:;[](){}*~_`\"'<>\\/=-"

  def __parse_ref__(rest, [name_part, "@"], context, _line, _offset) do
    {clean_name, trailing} = split_trailing_punct(name_part)

    if clean_name == "" do
      trailing_toks =
        if trailing != "", do: [{:punctuation, %{}, trailing}], else: []

      {rest, trailing_toks ++ [{:punctuation, %{}, "@"}], context}
    else
      trailing_toks =
        case trailing do
          "" ->
            []

          "*" ->
            [{:generic_emph, %{}, "*"}]

          "_" ->
            [{:generic_emph, %{}, "_"}]

          "~~" ->
            [{:generic_deleted, %{}, "~~"}]

          "~" ->
            [{:generic_deleted, %{}, "~"}]

          other ->
            [{:punctuation, %{}, other}]
        end

      entity_tok = {:name_entity, %{}, "@" <> clean_name}
      # NimbleParsec post_traverse accumulates in reverse, so [trailing, entity]
      # results in [entity, trailing] in final parsed token stream.
      {rest, trailing_toks ++ [entity_tok], context}
    end
  end

  defp split_trailing_punct(str) do
    rev = str |> String.to_charlist() |> :lists.reverse()
    strip_rev(rev, [])
  end

  defp strip_rev([], acc), do: {"", List.to_string(acc)}

  defp strip_rev([c | rest], acc) when c in @ascii_punct do
    strip_rev(rest, [c | acc])
  end

  defp strip_rev(rev_remaining, acc) do
    {rev_remaining |> :lists.reverse() |> List.to_string(), List.to_string(acc)}
  end

  lmml_reference =
    string("@")
    |> utf8_string([not: ?\s, not: ?\t, not: ?\r, not: ?\n], min: 1)
    |> post_traverse({__MODULE__, :__parse_ref__, []})

  # -- Inline code spans ------------------------------------------------

  inline_code_double =
    string("``")
    |> repeat(
      lookahead_not(string("``"))
      |> utf8_string([not: ?\n, not: ?\r], 1)
    )
    |> concat(string("``"))
    |> lexeme()
    |> token(:string_backtick)

  inline_code_single =
    string("`")
    |> repeat(
      lookahead_not(string("`"))
      |> utf8_string([not: ?\n, not: ?\r], 1)
    )
    |> concat(string("`"))
    |> lexeme()
    |> token(:string_backtick)

  # -- HTML comments and entities ---------------------------------------

  html_comment =
    string("<!--")
    |> repeat(
      lookahead_not(string("-->"))
      |> utf8_string([], 1)
    )
    |> concat(string("-->"))
    |> lexeme()
    |> token(:comment_multiline)

  html_entity =
    string("&")
    |> concat(ascii_string([?a..?z, ?A..?Z, ?0..?9, ?#], min: 1))
    |> concat(string(";"))
    |> lexeme()
    |> token(:name_entity)

  # -- Autolinks and URLs -----------------------------------------------

  autolink_bracketed =
    string("<")
    |> concat(
      choice([string("http://"), string("https://"), string("mailto:")])
      |> concat(utf8_string([not: ?>, not: ?\s, not: ?\t, not: ?\r, not: ?\n], min: 1))
    )
    |> concat(string(">"))
    |> lexeme()
    |> token(:name_attribute)

  raw_url =
    choice([string("https://"), string("http://")])
    |> concat(
      utf8_string(
        [
          not: ?\s,
          not: ?\t,
          not: ?\r,
          not: ?\n,
          not: ?),
          not: ?],
          not: ?>,
          not: ?\",
          not: ?'
        ],
        min: 1
      )
    )
    |> lexeme()
    |> token(:name_attribute)

  # -- Headings (ATX) ---------------------------------------------------

  atx_heading_h1 =
    string("#")
    |> concat(ascii_string([?\s, ?\t], min: 1))
    |> lexeme()
    |> token(:__atx_h1__)

  atx_heading_hsub =
    ascii_string([?#], min: 2, max: 6)
    |> concat(ascii_string([?\s, ?\t], min: 1))
    |> lexeme()
    |> token(:__atx_hsub__)

  # -- Thematic breaks / Horizontal rules & Setext underlines -----------

  setext_or_hr_equals =
    ascii_string([?=], min: 2)
    |> concat(lookahead(choice([newline, eos()])))
    |> lexeme()
    |> token(:__setext_h1__)

  setext_or_hr_dashes =
    ascii_string([?-], min: 2)
    |> concat(lookahead(choice([newline, eos()])))
    |> lexeme()
    |> token(:__setext_or_hr__)

  thematic_break_stars =
    ascii_string([?*], min: 3)
    |> concat(lookahead(choice([newline, eos()])))
    |> lexeme()
    |> token(:punctuation)

  thematic_break_underscores =
    ascii_string([?_], min: 3)
    |> concat(lookahead(choice([newline, eos()])))
    |> lexeme()
    |> token(:punctuation)

  # -- Blockquotes & Lists ----------------------------------------------

  blockquote_marker =
    ascii_string([?>], min: 1)
    |> concat(optional(ascii_string([?\s, ?\t], min: 1)))
    |> lexeme()
    |> token(:keyword)

  task_checkbox =
    string("[")
    |> concat(choice([string(" "), string("x"), string("X")]))
    |> concat(string("]"))
    |> lexeme()
    |> token(:keyword)

  list_marker_unordered =
    choice([string("- "), string("* "), string("+ "), string("• ")])
    |> token(:keyword)

  list_marker_ordered =
    ascii_string([?0..?9], min: 1)
    |> concat(choice([string(". "), string(") ")]))
    |> lexeme()
    |> token(:keyword)

  # -- Links and Images -------------------------------------------------

  image_open = string("![") |> token(:punctuation)
  link_open = string("[") |> token(:punctuation)
  link_middle = string("](") |> token(:punctuation)
  link_close = string(")") |> token(:punctuation)
  ref_link_middle = string("][") |> token(:punctuation)
  ref_def_middle = string("]:") |> token(:punctuation)
  bracket_close = string("]") |> token(:punctuation)

  # -- Emphasis markers -------------------------------------------------

  bold_italic_stars = string("***") |> token(:generic_strong)
  bold_italic_underscores = string("___") |> token(:generic_strong)
  bold_stars = string("**") |> token(:generic_strong)
  bold_underscores = string("__") |> token(:generic_strong)
  italic_star = string("*") |> token(:generic_emph)
  italic_underscore = string("_") |> token(:generic_emph)
  strikethrough = string("~~") |> token(:generic_deleted)

  # -- HTML tags --------------------------------------------------------

  html_tag_name = ascii_string([?a..?z, ?A..?Z, ?0..?9, ?-, ?:], min: 1)

  html_tag =
    choice([string("</"), string("<")])
    |> concat(html_tag_name)
    |> concat(
      repeat(
        lookahead_not(choice([string(">"), string("/>")]))
        |> utf8_string([not: ?\n, not: ?\r], 1)
      )
    )
    |> concat(choice([string("/>"), string(">")]))
    |> lexeme()
    |> token(:name_tag)

  # -- Tables -----------------------------------------------------------

  table_pipe = string("|") |> token(:punctuation)

  table_delimiter_cell =
    optional(string(":"))
    |> concat(ascii_string([?-], min: 1))
    |> concat(optional(string(":")))
    |> lexeme()
    |> token(:punctuation)

  # -- Text words and general punctuation -------------------------------

  word =
    utf8_string(
      [
        not: ?\s,
        not: ?\t,
        not: ?\r,
        not: ?\n,
        not: ?@,
        not: ?#,
        not: ?*,
        not: ?_,
        not: ?~,
        not: ?`,
        not: ?[,
        not: ?],
        not: ?(,
        not: ?),
        not: ?<,
        not: ?>,
        not: ?!,
        not: ?&,
        not: ?\\,
        not: ?|,
        not: ?:,
        not: ?;,
        not: ?,,
        not: ?.,
        not: ?-,
        not: ?=,
        not: ?+,
        not: ?/,
        not: ?",
        not: ?'
      ],
      min: 1
    )
    |> token(:text)

  general_punct =
    utf8_string(
      [
        ?!,
        ?:,
        ?;,
        ?,,
        ?.,
        ?-,
        ?=,
        ?+,
        ?/,
        ?",
        ?',
        ?(,
        ?),
        ?[,
        ?],
        ?{,
        ?},
        ?~,
        ?*,
        ?_,
        ?#,
        ?@
      ],
      1
    )
    |> token(:punctuation)

  any_fallback = utf8_char([]) |> token(:text)

  # -- Root element combinator ------------------------------------------

  root_element_combinator =
    choice([
      newline,
      spaces,
      escaped_char,
      embed_fence,
      code_fence_backtick,
      code_fence_tilde,
      html_comment,
      html_entity,
      autolink_bracketed,
      raw_url,
      atx_heading_h1,
      atx_heading_hsub,
      setext_or_hr_equals,
      setext_or_hr_dashes,
      thematic_break_stars,
      thematic_break_underscores,
      blockquote_marker,
      task_checkbox,
      list_marker_unordered,
      list_marker_ordered,
      image_open,
      link_middle,
      ref_link_middle,
      ref_def_middle,
      link_open,
      bracket_close,
      link_close,
      inline_code_double,
      inline_code_single,
      lmml_reference,
      bold_italic_stars,
      bold_italic_underscores,
      bold_stars,
      bold_underscores,
      italic_star,
      italic_underscore,
      strikethrough,
      table_pipe,
      table_delimiter_cell,
      html_tag,
      word,
      general_punct,
      any_fallback
    ])

  @doc false
  def __as_lmml_language__({ttype, meta, value}) do
    {ttype, Map.put(meta, :language, :lmml), value}
  end

  ##############################################################################
  # Semi-public API: parsec entry points
  ##############################################################################

  @impl Makeup.Lexer
  defparsec(
    :root_element,
    root_element_combinator |> map({__MODULE__, :__as_lmml_language__, []})
  )

  @impl Makeup.Lexer
  defparsec(
    :root,
    repeat(parsec(:root_element))
  )

  ###################################################################
  # Step 2: postprocess the list of tokens
  ###################################################################

  @impl Makeup.Lexer
  def postprocess(tokens, opts \\ []) do
    handle_codeblocks = Keyword.get(opts, :handle_codeblocks, true)
    resolve(tokens, :normal, [], true, handle_codeblocks)
  end

  defp resolve([], :normal, acc, _line_start, _handle_codeblocks), do: Enum.reverse(acc)

  defp resolve([], {:in_embed, name, body_acc, open_tokens}, acc, _line_start, handle_codeblocks) do
    highlighted = highlight_embed(body_acc, name, handle_codeblocks)
    block_tokens = open_tokens ++ highlighted
    Enum.reverse(acc) ++ block_tokens
  end

  defp resolve([], {:in_code, lang, body_acc, open_tokens}, acc, _line_start, handle_codeblocks) do
    highlighted = highlight_code(body_acc, lang, handle_codeblocks)
    block_tokens = open_tokens ++ highlighted
    Enum.reverse(acc) ++ block_tokens
  end

  defp resolve([], {:in_heading, level, heading_acc}, acc, _line_start, _handle_codeblocks) do
    flushed_rev = flush_heading(heading_acc, level)
    Enum.reverse(flushed_rev ++ acc)
  end

  # -- When in normal mode ----------------------------------------------

  # Newline: resets line_start to true, flushes any active heading
  defp resolve(
         [{:whitespace, _meta, val} = tok | rest],
         {:in_heading, level, heading_acc},
         acc,
         _line_start,
         handle_codeblocks
       )
       when val in ["\n", "\r\n", "\r"] do
    flushed_rev = flush_heading(heading_acc, level)
    resolve(rest, :normal, [tok | flushed_rev] ++ acc, true, handle_codeblocks)
  end

  defp resolve(
         [{:whitespace, _meta, val} = tok | rest],
         :normal,
         acc,
         _line_start,
         handle_codeblocks
       )
       when val in ["\n", "\r\n", "\r"] do
    resolve(rest, :normal, [tok | acc], true, handle_codeblocks)
  end

  # Leading spaces/tabs do not clear line_start
  defp resolve([{:whitespace, _meta, _val} = tok | rest], :normal, acc, true, handle_codeblocks) do
    resolve(rest, :normal, [tok | acc], true, handle_codeblocks)
  end

  # ATX Headings at start of line
  defp resolve([{:__atx_h1__, meta, val} | rest], :normal, acc, true, handle_codeblocks) do
    h_token = {:generic_heading, meta, val}
    resolve(rest, {:in_heading, :generic_heading, [h_token]}, acc, false, handle_codeblocks)
  end

  defp resolve([{:__atx_hsub__, meta, val} | rest], :normal, acc, true, handle_codeblocks) do
    h_token = {:generic_subheading, meta, val}
    resolve(rest, {:in_heading, :generic_subheading, [h_token]}, acc, false, handle_codeblocks)
  end

  # Setext underline: `===...`
  defp resolve([{:__setext_h1__, meta, val} | rest], :normal, acc, true, handle_codeblocks) do
    {rewritten_acc, _found?} = promote_prev_line_to_heading(acc, :generic_heading)
    u_token = {:generic_heading, meta, val}
    resolve(rest, :normal, [u_token | rewritten_acc], false, handle_codeblocks)
  end

  # Setext underline or HR: `---...`
  defp resolve([{:__setext_or_hr__, meta, val} | rest], :normal, acc, true, handle_codeblocks) do
    case promote_prev_line_to_heading(acc, :generic_subheading) do
      {rewritten_acc, true} ->
        u_token = {:generic_subheading, meta, val}
        resolve(rest, :normal, [u_token | rewritten_acc], false, handle_codeblocks)

      {_acc, false} ->
        hr_token = {:punctuation, meta, val}
        resolve(rest, :normal, [hr_token | acc], false, handle_codeblocks)
    end
  end

  # Embed fence at start of line: opening `@@@name`
  defp resolve(
         [{:__lmml_embed__, meta, "@@@" <> name} | rest],
         :normal,
         acc,
         true,
         handle_codeblocks
       )
       when name != "" and not is_nil(name) do
    if String.trim(name) == "" do
      # Closing fence without an open block: treat as string delimiter
      close_tokens =
        [{:string_delimiter, meta, "@@@"}] ++
          if(name != "", do: [{:whitespace, meta, name}], else: [])

      resolve(rest, :normal, Enum.reverse(close_tokens, acc), false, handle_codeblocks)
    else
      [_, leading_ws, embed_name, trailing] = Regex.run(~r/^(\s*)(\S+)(.*)$/s, name)

      open_tokens = [{:string_delimiter, meta, "@@@"}]

      open_tokens =
        if leading_ws != "",
          do: open_tokens ++ [{:whitespace, meta, leading_ws}],
          else: open_tokens

      open_tokens = open_tokens ++ [{:name_entity, meta, embed_name}]

      open_tokens =
        if trailing != "", do: open_tokens ++ [{:whitespace, meta, trailing}], else: open_tokens

      resolve(
        rest,
        {:in_embed, embed_name, [], open_tokens},
        acc,
        false,
        handle_codeblocks
      )
    end
  end

  # Embed fence at start of line: lone `@@@` outside of block
  defp resolve([{:__lmml_embed__, meta, "@@@"} | rest], :normal, acc, true, handle_codeblocks) do
    close_token = {:string_delimiter, meta, "@@@"}
    resolve(rest, :normal, [close_token | acc], false, handle_codeblocks)
  end

  # Code fence at start of line: opening
  defp resolve(
         [{:__code_fence__, meta, fence_and_info} | rest],
         :normal,
         acc,
         true,
         handle_codeblocks
       ) do
    {fence, lang_and_info} = split_code_fence(fence_and_info)

    if String.trim(lang_and_info) == "" do
      # Closing fence without open code block: emit delimiter
      close_tokens =
        [{:string_delimiter, meta, fence}] ++
          if(lang_and_info != "", do: [{:whitespace, meta, lang_and_info}], else: [])

      resolve(rest, :normal, Enum.reverse(close_tokens, acc), false, handle_codeblocks)
    else
      [_, leading_ws, lang, trailing] = Regex.run(~r/^(\s*)(\S+)(.*)$/s, lang_and_info)

      open_tokens = [{:string_delimiter, meta, fence}]

      open_tokens =
        if leading_ws != "",
          do: open_tokens ++ [{:whitespace, meta, leading_ws}],
          else: open_tokens

      open_tokens = open_tokens ++ [{:name_class, meta, lang}]

      open_tokens =
        if trailing != "", do: open_tokens ++ [{:text, meta, trailing}], else: open_tokens

      resolve(
        rest,
        {:in_code, lang, [], open_tokens},
        acc,
        false,
        handle_codeblocks
      )
    end
  end

  # Fallback for fences mid-line: treat as delimiter/text
  defp resolve([{:__lmml_embed__, meta, val} | rest], :normal, acc, false, handle_codeblocks) do
    tok = {:punctuation, meta, val}
    resolve(rest, :normal, [tok | acc], false, handle_codeblocks)
  end

  defp resolve([{:__code_fence__, meta, val} | rest], :normal, acc, false, handle_codeblocks) do
    tok = {:string_backtick, meta, val}
    resolve(rest, :normal, [tok | acc], false, handle_codeblocks)
  end

  defp resolve([{:__setext_or_hr__, meta, val} | rest], :normal, acc, false, handle_codeblocks) do
    tok = {:punctuation, meta, val}
    resolve(rest, :normal, [tok | acc], false, handle_codeblocks)
  end

  defp resolve([{:__setext_h1__, meta, val} | rest], :normal, acc, false, handle_codeblocks) do
    tok = {:punctuation, meta, val}
    resolve(rest, :normal, [tok | acc], false, handle_codeblocks)
  end

  # Inside heading line: accumulate tokens and style text appropriately
  defp resolve(
         [tok | rest],
         {:in_heading, level, heading_acc},
         acc,
         _line_start,
         handle_codeblocks
       ) do
    resolve(rest, {:in_heading, level, [tok | heading_acc]}, acc, false, handle_codeblocks)
  end

  # General token pass-through in normal mode
  defp resolve([tok | rest], :normal, acc, _line_start, handle_codeblocks) do
    resolve(rest, :normal, [tok | acc], false, handle_codeblocks)
  end

  # -- When in embed block ----------------------------------------------

  # Closing embed fence at start of line
  defp resolve(
         [{:__lmml_embed__, meta, "@@@" <> tail} | rest],
         {:in_embed, name, body_acc, open_tokens},
         acc,
         true,
         handle_codeblocks
       ) do
    if String.trim(tail) == "" do
      highlighted = highlight_embed(body_acc, name, handle_codeblocks)
      close_token = {:string_delimiter, meta, "@@@"}

      close_tokens =
        if tail != "",
          do: [close_token, {:whitespace, meta, tail}],
          else: [close_token]

      block_tokens = open_tokens ++ highlighted ++ close_tokens
      new_acc = Enum.reverse(block_tokens, acc)
      resolve(rest, :normal, new_acc, false, handle_codeblocks)
    else
      resolve(
        rest,
        {:in_embed, name, [{:__lmml_embed__, meta, "@@@" <> tail} | body_acc], open_tokens},
        acc,
        false,
        handle_codeblocks
      )
    end
  end

  defp resolve(
         [{:whitespace, _meta, val} = tok | rest],
         {:in_embed, name, body_acc, open_tokens},
         acc,
         _line_start,
         handle_codeblocks
       )
       when val in ["\n", "\r\n", "\r"] do
    resolve(
      rest,
      {:in_embed, name, [tok | body_acc], open_tokens},
      acc,
      true,
      handle_codeblocks
    )
  end

  defp resolve(
         [tok | rest],
         {:in_embed, name, body_acc, open_tokens},
         acc,
         line_start,
         handle_codeblocks
       ) do
    resolve(
      rest,
      {:in_embed, name, [tok | body_acc], open_tokens},
      acc,
      line_start && match?({:whitespace, _, _}, tok),
      handle_codeblocks
    )
  end

  # -- When in code block -----------------------------------------------

  # Closing code fence at start of line
  defp resolve(
         [{:__code_fence__, meta, fence_and_tail} | rest],
         {:in_code, lang, body_acc, open_tokens},
         acc,
         true,
         handle_codeblocks
       ) do
    {fence, tail} = split_code_fence(fence_and_tail)

    if String.trim(tail) == "" do
      highlighted = highlight_code(body_acc, lang, handle_codeblocks)
      close_token = {:string_delimiter, meta, fence}

      close_tokens =
        if tail != "",
          do: [close_token, {:whitespace, meta, tail}],
          else: [close_token]

      block_tokens = open_tokens ++ highlighted ++ close_tokens
      new_acc = Enum.reverse(block_tokens, acc)
      resolve(rest, :normal, new_acc, false, handle_codeblocks)
    else
      # Not a closing fence (has extra words), treat as code body
      resolve(
        rest,
        {:in_code, lang, [{:__code_fence__, meta, fence_and_tail} | body_acc], open_tokens},
        acc,
        false,
        handle_codeblocks
      )
    end
  end

  defp resolve(
         [{:whitespace, _meta, val} = tok | rest],
         {:in_code, lang, body_acc, open_tokens},
         acc,
         _line_start,
         handle_codeblocks
       )
       when val in ["\n", "\r\n", "\r"] do
    resolve(
      rest,
      {:in_code, lang, [tok | body_acc], open_tokens},
      acc,
      true,
      handle_codeblocks
    )
  end

  defp resolve(
         [tok | rest],
         {:in_code, lang, body_acc, open_tokens},
         acc,
         line_start,
         handle_codeblocks
       ) do
    resolve(
      rest,
      {:in_code, lang, [tok | body_acc], open_tokens},
      acc,
      line_start && match?({:whitespace, _, _}, tok),
      handle_codeblocks
    )
  end

  # -- Helpers for block splitting and sub-lexer delegation -------------

  defp split_code_fence("```" <> rest), do: {"```", rest}
  defp split_code_fence("~~~" <> rest), do: {"~~~", rest}
  defp split_code_fence(other), do: {other, ""}

  defp highlight_embed(body_tokens_rev, name, handle_codeblocks) do
    tokens = Enum.reverse(body_tokens_rev)
    body_str = Enum.map_join(tokens, fn {_, _, val} -> val end)

    if handle_codeblocks and body_str != "" do
      ext = Path.extname(name) |> String.trim_leading(".")

      case fetch_lexer(ext) do
        {:ok, {lexer, opts}} ->
          run_sub_lexer(lexer, body_str, opts, tokens)

        :error ->
          mark_as_string(tokens)
      end
    else
      mark_as_string(tokens)
    end
  end

  defp highlight_code(body_tokens_rev, lang, handle_codeblocks) do
    tokens = Enum.reverse(body_tokens_rev)
    body_str = Enum.map_join(tokens, fn {_, _, val} -> val end)

    if handle_codeblocks and body_str != "" and lang != "" do
      case fetch_lexer(lang) do
        {:ok, {lexer, opts}} ->
          run_sub_lexer(lexer, body_str, opts, tokens)

        :error ->
          mark_as_string(tokens)
      end
    else
      mark_as_string(tokens)
    end
  end

  defp fetch_lexer(name_or_ext) when is_binary(name_or_ext) and name_or_ext != "" do
    case Makeup.Registry.fetch_lexer_by_name(name_or_ext) do
      {:ok, res} -> {:ok, res}
      :error -> Makeup.Registry.fetch_lexer_by_extension(name_or_ext)
    end
  end

  defp fetch_lexer(_), do: :error

  defp run_sub_lexer(lexer, body_str, opts, fallback_tokens) do
    lexer.lex(body_str, opts)
  rescue
    _ -> mark_as_string(fallback_tokens)
  end

  defp mark_as_string(tokens) do
    Enum.map(tokens, fn
      {:whitespace, meta, val} -> {:whitespace, meta, val}
      {_type, meta, val} -> {:string, meta, val}
    end)
  end

  # Flushes an ATX heading line, preserving entities/spans but styling text
  defp flush_heading(heading_tokens_rev, level) do
    Enum.map(heading_tokens_rev, fn
      {:text, meta, val} ->
        {level, meta, val}

      {:punctuation, meta, val} when val not in ["#", "##", "###", "####", "#####", "######"] ->
        {level, meta, val}

      other ->
        other
    end)
  end

  # Promotes the preceding line of text in acc to a heading if separated only
  # by a single newline (Setext heading style)
  defp promote_prev_line_to_heading([{:whitespace, meta_nl, nl} | rest_acc], heading_level)
       when nl in ["\n", "\r\n", "\r"] do
    case extract_line(rest_acc, []) do
      {line_tokens_fwd, remaining, true} ->
        promoted_fwd =
          Enum.map(line_tokens_fwd, fn
            {:text, meta, val} -> {heading_level, meta, val}
            {:punctuation, meta, val} -> {heading_level, meta, val}
            other -> other
          end)

        promoted_rev = Enum.reverse(promoted_fwd)
        {[{:whitespace, meta_nl, nl} | promoted_rev] ++ remaining, true}

      _ ->
        {[{:whitespace, meta_nl, nl} | rest_acc], false}
    end
  end

  defp promote_prev_line_to_heading(acc, _heading_level), do: {acc, false}

  defp extract_line([], line_acc), do: {line_acc, [], line_acc != []}

  defp extract_line([{:whitespace, _m, val} = tok | rest], line_acc)
       when val in ["\n", "\r\n", "\r"] do
    if line_acc == [] do
      # Blank line: no content line immediately above
      {[], [tok | rest], false}
    else
      {line_acc, [tok | rest], true}
    end
  end

  defp extract_line([tok | rest], line_acc) do
    extract_line(rest, [tok | line_acc])
  end

  ###################################################################
  # Step 3: match groups (delimiters)
  ###################################################################

  @impl Makeup.Lexer
  def match_groups(tokens, _group_prefix \\ ""), do: tokens

  ###################################################################
  # Public API
  ###################################################################

  @impl Makeup.Lexer
  def lex(string, opts \\ []) do
    {:ok, tokens, "", _, _, _} = root(string)

    tokens
    |> postprocess(opts)
    |> match_groups()
  end
end
