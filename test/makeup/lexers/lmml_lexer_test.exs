defmodule Makeup.Lexers.LmmlLexerTest do
  use ExUnit.Case, async: true

  alias Makeup.Lexer
  alias Makeup.Lexers.LmmlLexer

  defp lex_no_ws(string, opts \\ []) do
    string
    |> LmmlLexer.lex(opts)
    |> Enum.reject(fn {type, _, _} -> type == :whitespace end)
  end

  defp token_types(string, opts \\ []) do
    string |> lex_no_ws(opts) |> Enum.map(&elem(&1, 0))
  end

  defp value(token), do: token |> elem(2) |> List.wrap() |> IO.iodata_to_binary()

  # -- LMML Embeds and References ---------------------------------------

  describe "LMML external references (@name.ext)" do
    test "parses bare reference to :name_entity" do
      assert [{:name_entity, meta, val}] = lex_no_ws("@diagram.png")
      assert meta.language == :lmml
      assert val == "@diagram.png"
    end

    test "reference in running prose" do
      tokens = lex_no_ws("Please review @diagram.png before the meeting.")
      types = Enum.map(tokens, &elem(&1, 0))
      assert :name_entity in types

      ref_token = Enum.find(tokens, fn {t, _, _} -> t == :name_entity end)
      assert value(ref_token) == "@diagram.png"
    end

    test "reference followed by comma stops cleanly before punctuation" do
      tokens = lex_no_ws("cc @bob, thanks!")
      ref_token = Enum.find(tokens, fn {t, _, _} -> t == :name_entity end)
      assert value(ref_token) == "@bob"

      punct_token = Enum.find(tokens, fn {t, _, v} -> t == :punctuation and v == "," end)
      assert punct_token != nil
    end

    test "reference inside parentheses" do
      tokens = lex_no_ws("(see @image.png)")

      assert [
               {:punctuation, _, "("},
               {:text, _, "see"},
               {:name_entity, _, "@image.png"},
               {:punctuation, _, ")"}
             ] =
               tokens
    end

    test "reference followed by bold/italic marker detached cleanly" do
      tokens = lex_no_ws("@image.png*")
      assert [{:name_entity, _, "@image.png"}, {:generic_emph, _, "*"}] = tokens
    end

    test "reference followed by end-of-sentence period" do
      tokens = lex_no_ws("Attached: @report.pdf.")

      assert [
               {:text, _, "Attached"},
               {:punctuation, _, ":"},
               {:name_entity, _, "@report.pdf"},
               {:punctuation, _, "."}
             ] =
               tokens
    end

    test "reference inside emphasis span" do
      tokens = lex_no_ws("*see @image.png inside*")
      ref_tok = Enum.find(tokens, fn {t, _, _} -> t == :name_entity end)
      assert ref_tok != nil
      assert value(ref_tok) == "@image.png"
    end

    test "multiple references in single sentence" do
      tokens = lex_no_ws("Compare @a.png and @b.png.")
      entities = Enum.filter(tokens, fn {t, _, _} -> t == :name_entity end)
      assert length(entities) == 2
      assert Enum.map(entities, &value/1) == ["@a.png", "@b.png"]
    end
  end

  describe "LMML inline embeds (@@@name.ext ... @@@)" do
    test "bare inline embed block" do
      source = """
      @@@settings.yaml
      model: gpt-5
      temperature: 0.2
      @@@
      """

      tokens = LmmlLexer.lex(source)
      types = Enum.map(tokens, &elem(&1, 0))

      assert :string_delimiter in types
      assert :name_entity in types
      assert :string in types

      # Delimiters and entity name
      assert [{:string_delimiter, _, "@@@"}, {:name_entity, _, "settings.yaml"} | _] = tokens
    end

    test "embed surrounded by prose" do
      source = """
      Here is the config:

      @@@settings.yaml
      theme: dark
      @@@

      Done.
      """

      tokens = lex_no_ws(source)
      delimiters = Enum.filter(tokens, fn {t, _, v} -> t == :string_delimiter and v == "@@@" end)
      assert length(delimiters) == 2
    end

    test "embeds containing blank lines preserve content" do
      source = """
      @@@notes.txt
      first line

      second line
      @@@
      """

      tokens = LmmlLexer.lex(source)
      assert Lexer.unlex(tokens) == source
    end

    test "multiple embeds in sequence" do
      source = """
      @@@a.yaml
      first: 1
      @@@

      @@@b.yaml
      second: 2
      @@@
      """

      tokens = LmmlLexer.lex(source)
      names = tokens |> Enum.filter(fn {t, _, _} -> t == :name_entity end) |> Enum.map(&value/1)
      assert "a.yaml" in names
      assert "b.yaml" in names
      assert Lexer.unlex(tokens) == source
    end

    test "embed with registered sub-lexer delegates body highlight" do
      Application.ensure_all_started(:makeup_elixir)

      source = """
      @@@app.ex
      def hello do
        :ok
      end
      @@@
      """

      tokens = LmmlLexer.lex(source)
      types = Enum.map(tokens, &elem(&1, 0))

      assert :keyword_declaration in types
      assert :name_function in types
      assert Lexer.unlex(tokens) == source
    end

    test "unclosed embed at EOF does not crash and preserves text" do
      source = "@@@notes.txt\nunclosed text"
      tokens = LmmlLexer.lex(source)
      assert Lexer.unlex(tokens) == source
    end
  end

  # -- Markdown Headings ------------------------------------------------

  describe "ATX headings" do
    test "level 1 heading (# Heading) is generic_heading" do
      tokens = lex_no_ws("# Main Heading")

      assert [:generic_heading, :generic_heading, :generic_heading] =
               Enum.map(tokens, &elem(&1, 0))
    end

    test "level 2 heading (## Subheading) is generic_subheading" do
      tokens = lex_no_ws("## Section One")

      assert [:generic_subheading, :generic_subheading, :generic_subheading] =
               Enum.map(tokens, &elem(&1, 0))
    end

    test "headings level 3 through 6 are generic_subheading" do
      for level <- 3..6 do
        hashes = String.duplicate("#", level)
        tokens = lex_no_ws("#{hashes} Sub")
        assert hd(tokens) |> elem(0) == :generic_subheading
      end
    end

    test "heading containing LMML reference preserves entity token" do
      tokens = lex_no_ws("# Overview of @diagram.png")
      types = Enum.map(tokens, &elem(&1, 0))
      assert :generic_heading in types
      assert :name_entity in types
    end
  end

  describe "Setext headings" do
    test "=== underline promotes preceding line to generic_heading" do
      source = """
      Main Title
      ===
      """

      tokens = lex_no_ws(source)
      types = Enum.map(tokens, &elem(&1, 0))
      assert Enum.all?(types, &(&1 == :generic_heading))
    end

    test "--- underline promotes preceding line to generic_subheading" do
      source = """
      Subtitle
      ---
      """

      tokens = lex_no_ws(source)
      types = Enum.map(tokens, &elem(&1, 0))
      assert Enum.all?(types, &(&1 == :generic_subheading))
    end
  end

  # -- Fenced and Inline Code -------------------------------------------

  describe "fenced code blocks" do
    test "standard backtick fence without language" do
      source = """
      ```
      plain text code
      ```
      """

      tokens = LmmlLexer.lex(source)
      assert Lexer.unlex(tokens) == source
    end

    test "backtick fence with elixir sub-lexer" do
      Application.ensure_all_started(:makeup_elixir)

      source = """
      ```elixir
      def foo, do: :ok
      ```
      """

      tokens = LmmlLexer.lex(source)
      types = Enum.map(tokens, &elem(&1, 0))
      assert :string_delimiter in types
      assert :name_class in types
      assert :keyword_declaration in types
      assert Lexer.unlex(tokens) == source
    end

    test "tilde fence (~~~)" do
      source = """
      ~~~
      code block
      ~~~
      """

      tokens = LmmlLexer.lex(source)
      assert Lexer.unlex(tokens) == source
    end

    test "code fence with space before language name" do
      source = """
      ``` elixir
      def foo, do: 1
      ```
      """

      tokens = LmmlLexer.lex(source)
      assert Lexer.unlex(tokens) == source
    end

    test "handle_codeblocks: false disables nested lexing" do
      Application.ensure_all_started(:makeup_elixir)

      source = """
      ```elixir
      def foo, do: 1
      ```
      """

      tokens = LmmlLexer.lex(source, handle_codeblocks: false)
      types = Enum.map(tokens, &elem(&1, 0))
      refute :keyword_declaration in types
      assert Lexer.unlex(tokens) == source
    end
  end

  describe "inline code" do
    test "single backtick code span" do
      assert [{:string_backtick, _, "`foo`"}] = lex_no_ws("`foo`")
    end

    test "double backtick code span with inner backtick" do
      assert [{:string_backtick, _, "``foo ` bar``"}] = lex_no_ws("``foo ` bar``")
    end
  end

  # -- Emphasis, Lists, Quotes, Tables, Rules ---------------------------

  describe "emphasis and formatting" do
    test "bold with double stars and underscores" do
      assert [:generic_strong, :text, :generic_strong] = token_types("**bold**")
      assert [:generic_strong, :text, :generic_strong] = token_types("__bold__")
    end

    test "italic with single star and underscore" do
      assert [:generic_emph, :text, :generic_emph] = token_types("*italic*")
      assert [:generic_emph, :text, :generic_emph] = token_types("_italic_")
    end

    test "strikethrough" do
      assert [:generic_deleted, :text, :generic_deleted] = token_types("~~strike~~")
    end
  end

  describe "lists and blockquotes" do
    test "unordered list markers" do
      assert [:keyword, :text] = token_types("- item")
      assert [:keyword, :text] = token_types("* item")
      assert [:keyword, :text] = token_types("+ item")
    end

    test "task list checkboxes" do
      tokens = lex_no_ws("- [ ] todo")
      assert [:keyword, :keyword, :text] = Enum.map(tokens, &elem(&1, 0))

      tokens_done = lex_no_ws("- [x] done")
      assert [:keyword, :keyword, :text] = Enum.map(tokens_done, &elem(&1, 0))
    end

    test "ordered list markers" do
      assert [:keyword, :text] = token_types("1. first")
      assert [:keyword, :text] = token_types("2. second")
    end

    test "blockquote marker" do
      assert [:keyword, :text, :text] = token_types("> quoted text")
    end
  end

  describe "thematic breaks / horizontal rules" do
    test "three dashes, stars, underscores" do
      assert [:punctuation] = token_types("---")
      assert [:punctuation] = token_types("***")
      assert [:punctuation] = token_types("___")
    end
  end

  describe "links, images, and HTML" do
    test "markdown link" do
      tokens = lex_no_ws("[elixir](https://elixir-lang.org)")
      types = Enum.map(tokens, &elem(&1, 0))
      assert :punctuation in types
      assert :name_attribute in types
    end

    test "markdown image" do
      tokens = lex_no_ws("![logo](logo.png)")
      types = Enum.map(tokens, &elem(&1, 0))
      assert :punctuation in types
    end

    test "reference-style link" do
      tokens = lex_no_ws("[id]: https://example.com")
      types = Enum.map(tokens, &elem(&1, 0))
      assert :name_attribute in types
    end

    test "HTML comments" do
      assert [{:comment_multiline, _, "<!-- comment -->"}] = lex_no_ws("<!-- comment -->")
    end

    test "HTML entity" do
      assert [{:name_entity, _, "&copy;"}] = lex_no_ws("&copy;")
      assert [{:name_entity, _, "&amp;"}] = lex_no_ws("&amp;")
    end

    test "escaped characters" do
      assert [{:string_escape, _, "\\*"}, {:text, _, "not"}, {:text, _, "bold"}] =
               lex_no_ws("\\*not bold")

      assert [{:string_escape, _, "\\@"}, {:text, _, "not"}, {:text, _, "ref"}] =
               lex_no_ws("\\@not ref")
    end

    test "autolink in brackets" do
      assert [{:name_attribute, _, "<https://example.com>"}] = lex_no_ws("<https://example.com>")
    end

    test "raw url in prose" do
      tokens = lex_no_ws("See https://example.com for details.")

      assert Enum.any?(tokens, fn {t, _, v} ->
               t == :name_attribute and v == "https://example.com"
             end)
    end
  end

  # -- Roundtrip Guarantee ----------------------------------------------

  describe "roundtrip property" do
    test "any string unlexes back to the original input" do
      samples = [
        "",
        "\n",
        "Hello world\n",
        "# Heading\n\nParagraph with @diagram.png and `inline code`.\n",
        "@@@settings.yaml\nmodel: gpt-5\ntemp: 0.2\n@@@\n",
        "```elixir\ndef hello, do: :world\n```\n",
        "- [ ] task 1\n- [x] task 2\n",
        "| a | b |\n| --- | --- |\n| 1 | 2 |\n",
        "> Quote with *bold* and _italic_\n",
        "Title\n===\n\nSubtitle\n---\n"
      ]

      for sample <- samples do
        tokens = LmmlLexer.lex(sample)
        assert Lexer.unlex(tokens) == sample
      end
    end
  end

  # -- Registry Integration ---------------------------------------------

  describe "application registry" do
    test "registers lmml, markdown, and md names" do
      assert {:ok, {LmmlLexer, _}} = Makeup.Registry.fetch_lexer_by_name("lmml")
      assert {:ok, {LmmlLexer, _}} = Makeup.Registry.fetch_lexer_by_name("markdown")
      assert {:ok, {LmmlLexer, _}} = Makeup.Registry.fetch_lexer_by_name("md")
    end

    test "registers lmml, md, and markdown file extensions" do
      assert {:ok, {LmmlLexer, _}} = Makeup.Registry.fetch_lexer_by_extension("lmml")
      assert {:ok, {LmmlLexer, _}} = Makeup.Registry.fetch_lexer_by_extension("md")
      assert {:ok, {LmmlLexer, _}} = Makeup.Registry.fetch_lexer_by_extension("markdown")
    end
  end
end
