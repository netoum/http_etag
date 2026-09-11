defmodule HttpEtagTest do
  use ExUnit.Case, async: true
  use ExUnitProperties
  doctest HttpEtag
  doctest HttpEtag.Error

  alias HttpEtag.Error

  defp tag!(value), do: HttpEtag.parse!(value)

  describe "new/2" do
    test "builds a strong tag by default" do
      assert HttpEtag.new("abc") == {:ok, %HttpEtag{opaque: "abc", weak: false}}
    end

    test "accepts an empty opaque" do
      assert HttpEtag.new("") == {:ok, %HttpEtag{opaque: "", weak: false}}
    end

    test "default struct is an empty strong tag" do
      assert struct(HttpEtag) == %HttpEtag{opaque: "", weak: false}
    end

    test "accepts obs-text octets" do
      opaque = <<0x80, 0xFF>>
      assert HttpEtag.new(opaque) == {:ok, %HttpEtag{opaque: opaque, weak: false}}
    end

    test "rejects a double quote in the opaque" do
      assert {:error, %Error{reason: :invalid_etag}} = HttpEtag.new(~S(a"b))
    end

    test "rejects space and DEL" do
      assert {:error, %Error{reason: :invalid_etag}} = HttpEtag.new("a b")
      assert {:error, %Error{reason: :invalid_etag}} = HttpEtag.new(<<0x7F>>)
    end

    test "accepts an integer as opaque digits" do
      assert HttpEtag.new(1) == {:ok, %HttpEtag{opaque: "1", weak: false}}
      assert HttpEtag.new(-1) == {:ok, %HttpEtag{opaque: "-1", weak: false}}
      assert HttpEtag.new(1, true) == {:ok, %HttpEtag{opaque: "1", weak: true}}

      tag = HttpEtag.new!(42)
      assert tag == %HttpEtag{opaque: "42", weak: false}
      assert HttpEtag.parse!(HttpEtag.to_header(tag)) == tag
    end

    test "rejects a non-binary opaque or non-boolean weak flag" do
      assert {:error, %Error{reason: :invalid_etag}} = HttpEtag.new(:abc)
      assert {:error, %Error{reason: :invalid_etag}} = HttpEtag.new("abc", :weak)
    end
  end

  describe "parse/1" do
    test "parses strong, weak, and empty opaque tags" do
      assert HttpEtag.parse(~S("abc")) == {:ok, %HttpEtag{opaque: "abc", weak: false}}
      assert HttpEtag.parse(~S(W/"abc")) == {:ok, %HttpEtag{opaque: "abc", weak: true}}
      assert HttpEtag.parse(~S("")) == {:ok, %HttpEtag{opaque: "", weak: false}}
      assert HttpEtag.parse(~S(W/"")) == {:ok, %HttpEtag{opaque: "", weak: true}}
    end

    test "trims surrounding SP and HTAB" do
      assert HttpEtag.parse(" \t\"abc\"\t ") == {:ok, %HttpEtag{opaque: "abc", weak: false}}
    end

    test "parses opaque that looks like a weak prefix" do
      assert HttpEtag.parse(~S("W/foo")) == {:ok, %HttpEtag{opaque: "W/foo", weak: false}}
    end

    test "parses obs-text inside quotes" do
      assert HttpEtag.parse(<<?", 0x80, ?">>) == {:ok, %HttpEtag{opaque: <<0x80>>, weak: false}}
    end

    test "rejects lowercase w, a space after W/, and leftover tokens" do
      assert {:error, %Error{reason: :invalid_etag}} = HttpEtag.parse(~S(w/"abc"))
      assert {:error, %Error{reason: :invalid_etag}} = HttpEtag.parse(~S(W/ "abc"))
      assert {:error, %Error{reason: :invalid_etag}} = HttpEtag.parse(~S("abc" "def"))
      assert {:error, %Error{reason: :invalid_etag}} = HttpEtag.parse("*")
      assert {:error, %Error{reason: :invalid_etag}} = HttpEtag.parse(~S("a", "b"))
    end

    test "rejects space, DEL, and an unclosed quote inside the opaque" do
      assert {:error, %Error{reason: :invalid_etag}} = HttpEtag.parse(~S("a b"))
      assert {:error, %Error{reason: :invalid_etag}} = HttpEtag.parse(<<?", 0x7F, ?">>)
      assert {:error, %Error{reason: :invalid_etag}} = HttpEtag.parse(~S("abc))
    end

    test "does not unescape backslashes" do
      assert HttpEtag.parse(~S("a\b")) == {:ok, %HttpEtag{opaque: ~S(a\b), weak: false}}
      assert {:error, %Error{reason: :invalid_etag}} = HttpEtag.parse(~S("a\"b"))
    end

    test "rejects a non-binary value" do
      assert {:error, %Error{reason: :invalid_etag}} = HttpEtag.parse(nil)
    end

    test "rejects W/ without an entity-tag" do
      assert {:error, %Error{reason: :invalid_etag}} = HttpEtag.parse("W/")
    end
  end

  describe "parse_list/1" do
    test "parses * after OWS as :any" do
      assert HttpEtag.parse_list("*") == {:ok, :any}
      assert HttpEtag.parse_list(" *\t") == {:ok, :any}
    end

    test "parses a list of tags and ignores empty elements" do
      assert HttpEtag.parse_list(~S("a", W/"b")) ==
               {:ok, [%HttpEtag{opaque: "a", weak: false}, %HttpEtag{opaque: "b", weak: true}]}

      assert HttpEtag.parse_list(~S("a",, "b")) ==
               {:ok, [%HttpEtag{opaque: "a", weak: false}, %HttpEtag{opaque: "b", weak: false}]}

      assert HttpEtag.parse_list(~S(,"a",)) == {:ok, [%HttpEtag{opaque: "a", weak: false}]}
    end

    test "treats an empty or OWS-only field as an empty list" do
      assert HttpEtag.parse_list("") == {:ok, []}
      assert HttpEtag.parse_list(" \t") == {:ok, []}
      assert HttpEtag.parse_list(",") == {:ok, []}
    end

    test "treats quoted * as an entity-tag, not :any" do
      assert HttpEtag.parse_list(~S("*")) == {:ok, [%HttpEtag{opaque: "*", weak: false}]}
    end

    test "rejects * mixed with tags" do
      assert {:error, %Error{reason: :invalid_header}} = HttpEtag.parse_list(~S(*, "a"))
      assert {:error, %Error{reason: :invalid_header}} = HttpEtag.parse_list(~S("a", *))
    end

    test "rejects leftover tokens and non-binaries" do
      assert {:error, %Error{reason: :invalid_header}} = HttpEtag.parse_list("foo")
      assert {:error, %Error{reason: :invalid_header}} = HttpEtag.parse_list("W/")
      assert {:error, %Error{reason: :invalid_header}} = HttpEtag.parse_list(:star)
    end
  end

  describe "to_header/1" do
    test "round-trips strong and weak tags" do
      assert HttpEtag.to_header(tag!(~S("abc"))) == ~S("abc")
      assert HttpEtag.to_header(tag!(~S(W/"abc"))) == ~S(W/"abc")
      assert HttpEtag.to_header(tag!(~S(""))) == ~S("")
    end
  end

  describe "RFC 9110 §8.8.3.2 comparison table" do
    test "matches the spec examples" do
      weak1 = tag!(~S(W/"1"))
      weak2 = tag!(~S(W/"2"))
      strong1 = tag!(~S("1"))

      refute HttpEtag.strong_match?(weak1, weak1)
      assert HttpEtag.weak_match?(weak1, weak1)

      refute HttpEtag.strong_match?(weak1, weak2)
      refute HttpEtag.weak_match?(weak1, weak2)

      refute HttpEtag.strong_match?(weak1, strong1)
      assert HttpEtag.weak_match?(weak1, strong1)

      assert HttpEtag.strong_match?(strong1, strong1)
      assert HttpEtag.weak_match?(strong1, strong1)
    end
  end

  describe "if_match/2" do
    test "missing header is :ok" do
      assert HttpEtag.if_match(tag!(~S("abc")), nil) == :ok
      assert HttpEtag.if_match(nil, nil) == :ok
    end

    test "* succeeds only when the resource exists" do
      assert HttpEtag.if_match(tag!(~S("abc")), "*") == :ok
      assert HttpEtag.if_match(tag!(~S(W/"abc")), "*") == :ok
      assert {:error, %Error{reason: :precondition_failed}} = HttpEtag.if_match(nil, "*")
    end

    test "uses strong comparison on a tag list" do
      current = tag!(~S("abc"))
      assert HttpEtag.if_match(current, ~S("xyz", "abc")) == :ok

      assert {:error, %Error{reason: :precondition_failed}} =
               HttpEtag.if_match(current, ~S(W/"abc"))

      assert {:error, %Error{reason: :precondition_failed}} =
               HttpEtag.if_match(current, ~S("xyz"))
    end

    test "a weak current never matches a tag list" do
      current = tag!(~S(W/"abc"))

      assert {:error, %Error{reason: :precondition_failed}} =
               HttpEtag.if_match(current, ~S("abc"))

      assert {:error, %Error{reason: :precondition_failed}} =
               HttpEtag.if_match(current, ~S(W/"abc"))
    end

    test "empty list or missing current with tags fails" do
      assert {:error, %Error{reason: :precondition_failed}} =
               HttpEtag.if_match(tag!(~S("abc")), "")

      assert {:error, %Error{reason: :precondition_failed}} = HttpEtag.if_match(nil, ~S("abc"))
    end

    test "invalid field text is :invalid_header" do
      assert {:error, %Error{reason: :invalid_header}} =
               HttpEtag.if_match(tag!(~S("abc")), "nope")
    end
  end

  describe "if_none_match/2" do
    test "missing header is :ok" do
      assert HttpEtag.if_none_match(tag!(~S("abc")), nil) == :ok
    end

    test "* succeeds only when the resource does not exist" do
      assert HttpEtag.if_none_match(nil, "*") == :ok

      assert {:error, %Error{reason: :precondition_failed}} =
               HttpEtag.if_none_match(tag!(~S("abc")), "*")
    end

    test "uses weak comparison on a tag list" do
      current = tag!(~S("abc"))

      assert {:error, %Error{reason: :precondition_failed}} =
               HttpEtag.if_none_match(current, ~S(W/"abc"))

      assert HttpEtag.if_none_match(current, ~S("xyz")) == :ok
    end

    test "a tag list succeeds when the resource does not exist" do
      assert HttpEtag.if_none_match(nil, ~S("abc")) == :ok
    end

    test "empty list is satisfied" do
      assert HttpEtag.if_none_match(tag!(~S("abc")), "") == :ok
    end

    test "invalid field text is :invalid_header" do
      assert {:error, %Error{reason: :invalid_header}} = HttpEtag.if_none_match(nil, "nope")
    end
  end

  describe "bang variants" do
    test "new!/1 and new!/2 return a tag" do
      assert HttpEtag.new!("abc") == %HttpEtag{opaque: "abc", weak: false}
      assert HttpEtag.new!("abc", true) == %HttpEtag{opaque: "abc", weak: true}
    end

    test "parse!/1 and parse_list!/1 return the parsed value" do
      assert HttpEtag.parse!(~S("abc")) == %HttpEtag{opaque: "abc", weak: false}
      assert HttpEtag.parse_list!("*") == :any
      assert HttpEtag.parse_list!(~S("a")) == [%HttpEtag{opaque: "a", weak: false}]
    end

    test "if_match!/2 and if_none_match!/2 return :ok" do
      assert HttpEtag.if_match!(tag!(~S("abc")), ~S("abc")) == :ok
      assert HttpEtag.if_none_match!(nil, "*") == :ok
    end

    test "new!/1 raises on an invalid opaque" do
      assert_raise Error, "invalid entity-tag", fn -> HttpEtag.new!("a b") end
    end

    test "parse!/1 raises on an invalid entity-tag" do
      assert_raise Error, "invalid entity-tag", fn -> HttpEtag.parse!("*") end
    end

    test "parse_list!/1 raises on an invalid field" do
      assert_raise Error, "invalid If-Match or If-None-Match header", fn ->
        HttpEtag.parse_list!("nope")
      end
    end

    test "if_match!/2 raises when the precondition fails" do
      assert_raise Error, "precondition failed", fn -> HttpEtag.if_match!(nil, "*") end
    end

    test "if_none_match!/2 raises when the precondition fails" do
      assert_raise Error, "precondition failed", fn ->
        HttpEtag.if_none_match!(tag!(~S("abc")), "*")
      end
    end
  end

  describe "HttpEtag.Error" do
    test "exception/1 builds the struct" do
      assert %Error{reason: :invalid_etag} = Error.exception(reason: :invalid_etag)
    end

    test "messages cover each reason" do
      assert Exception.message(%Error{reason: :invalid_etag}) == "invalid entity-tag"

      assert Exception.message(%Error{reason: :invalid_header}) ==
               "invalid If-Match or If-None-Match header"

      assert Exception.message(%Error{reason: :precondition_failed}) == "precondition failed"
      assert Exception.message(%Error{reason: :other}) == "entity-tag error"
    end
  end

  describe "from_content/2" do
    test "hashes with SHA-256 and is strong by default" do
      tag = HttpEtag.from_content("abc")

      assert tag == %HttpEtag{
               opaque: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
               weak: false
             }

      assert {:ok, ^tag} = HttpEtag.parse(HttpEtag.to_header(tag))
    end

    test "marks the tag weak when asked" do
      tag = HttpEtag.from_content("abc", weak: true)
      assert tag.weak
      assert HttpEtag.to_header(tag) == ~s(W/"#{tag.opaque}")
    end

    test "accepts another hash algorithm" do
      tag = HttpEtag.from_content("abc", algorithm: :sha512)

      assert tag.opaque ==
               "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f"
    end

    test "accepts iodata" do
      assert HttpEtag.from_content(["ab", "c"]) == HttpEtag.from_content("abc")
    end

    test "rejects a non-boolean :weak or non-atom :algorithm" do
      assert_raise ArgumentError, ~r/:weak must be a boolean/, fn ->
        HttpEtag.from_content("abc", weak: :yes)
      end

      assert_raise ArgumentError, ~r/:algorithm must be a :crypto hash algorithm/, fn ->
        HttpEtag.from_content("abc", algorithm: "sha256")
      end
    end

    test "rejects an unknown option" do
      assert_raise ArgumentError, fn ->
        HttpEtag.from_content("abc", extra: true)
      end
    end
  end

  describe "current and header type errors" do
    test "if_match/2 and if_none_match/2 raise ArgumentError on a bad current" do
      assert_raise ArgumentError, ~r/current must be a %HttpEtag\{\} or nil/, fn ->
        HttpEtag.if_match(~S("abc"), ~S("abc"))
      end

      assert_raise ArgumentError, ~r/current must be a %HttpEtag\{\} or nil/, fn ->
        HttpEtag.if_none_match(~S("abc"), ~S("abc"))
      end
    end

    test "if_match/2 and if_none_match/2 raise ArgumentError on a non-binary header" do
      tag = tag!(~S("abc"))

      assert_raise ArgumentError, ~r/header must be a binary or nil/, fn ->
        HttpEtag.if_match(tag, :bad)
      end

      assert_raise ArgumentError, ~r/header must be a binary or nil/, fn ->
        HttpEtag.if_none_match(tag, :bad)
      end

      assert_raise ArgumentError, ~r/header must be a binary or nil/, fn ->
        HttpEtag.if_match(nil, :bad)
      end

      assert_raise ArgumentError, ~r/header must be a binary or nil/, fn ->
        HttpEtag.if_none_match(nil, :bad)
      end
    end
  end

  describe "parse_list/1 empty-element cap" do
    test "rejects more than 256 comma-separated segments" do
      over = String.duplicate(",", 256)
      assert {:error, %Error{reason: :invalid_header}} = HttpEtag.parse_list(over)

      ok =
        1..256
        |> Enum.map_join(", ", fn i -> ~s("#{i}") end)

      assert {:ok, tags} = HttpEtag.parse_list(ok)
      assert length(tags) == 256
    end
  end

  describe "properties" do
    property "new/2 tags round-trip through to_header/1 and parse/1" do
      check all(
              opaque <- opaque_generator(),
              weak <- StreamData.boolean()
            ) do
        tag = HttpEtag.new!(opaque, weak)
        assert HttpEtag.parse!(HttpEtag.to_header(tag)) == tag
      end
    end

    property "parse_list/1 round-trips a generated tag list" do
      check all(tags <- StreamData.list_of(tag_generator(), max_length: 16)) do
        header = Enum.map_join(tags, ", ", &HttpEtag.to_header/1)
        assert HttpEtag.parse_list!(header) == tags
      end
    end

    property "strong_match?/2 and weak_match?/2 follow weakness rules" do
      check all(
              left <- tag_generator(),
              right <- tag_generator()
            ) do
        assert HttpEtag.weak_match?(left, left)
        assert HttpEtag.weak_match?(left, right) == (left.opaque == right.opaque)

        if left.weak or right.weak do
          refute HttpEtag.strong_match?(left, right)
        else
          assert HttpEtag.strong_match?(left, right) == (left.opaque == right.opaque)
        end
      end
    end

    property "invalid octets never succeed new/1 or quoted parse/1" do
      check all(byte <- StreamData.integer(0..0xFF)) do
        if byte === 0x21 or (byte >= 0x23 and byte <= 0x7E) or byte >= 0x80 do
          assert {:ok, %HttpEtag{opaque: <<^byte>>, weak: false}} = HttpEtag.new(<<byte>>)
        else
          assert {:error, %Error{reason: :invalid_etag}} = HttpEtag.new(<<byte>>)
          quoted = <<?", byte, ?">>
          assert {:error, %Error{reason: :invalid_etag}} = HttpEtag.parse(quoted)
        end
      end
    end
  end

  defp opaque_generator do
    etagc =
      StreamData.one_of([
        StreamData.constant(0x21),
        StreamData.integer(0x23..0x7E),
        StreamData.integer(0x80..0xFF)
      ])

    StreamData.map(StreamData.list_of(etagc, max_length: 64), &:binary.list_to_bin/1)
  end

  defp tag_generator do
    StreamData.bind(opaque_generator(), fn opaque ->
      StreamData.map(StreamData.boolean(), fn weak -> HttpEtag.new!(opaque, weak) end)
    end)
  end
end
