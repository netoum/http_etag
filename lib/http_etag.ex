defmodule HttpEtag do
  @moduledoc """
  RFC 9110 entity tags and If-Match / If-None-Match.

  Parses entity tags and evaluates preconditions. The library reports whether
  a precondition is satisfied; the caller maps that to 304 or 412. It does not
  send those statuses or set `Cache-Control`.

  ## Behaviour

    * Build tags with `new/2` (opaque octets or an integer such as
      `lock_version`), `parse/1` (a quoted `ETag` field), or `from_content/2`
      (hash of canonical iodata you already have — not `Jason.encode!/1`).
    * `new("1")` is opaque `1`. `parse(~S("1"))` is the wire field `"1"`.
    * If-Match uses strong comparison; If-None-Match uses weak comparison. Do
      not use `==` on the struct.
    * A missing header is `nil` and skips the precondition (`:ok`). `""` is an
      empty list, not a missing header.
    * Functions return `:ok` or `{:error, exception}`. Programmer mistakes
      (wrong `current` or `header` type) raise `ArgumentError`.
    * Hand-built structs are not validated. A `"` in `opaque` is not a valid
      entity-tag.

  ## Examples

      iex> {:ok, tag} = HttpEtag.parse(~S("abc"))
      iex> HttpEtag.to_header(tag)
      ~S("abc")

      iex> HttpEtag.if_match(HttpEtag.parse!(~S("abc")), ~S("abc"))
      :ok

  See `HttpEtag.Conn`, `HttpEtag.Error`, and
  [RFC 9110](https://www.rfc-editor.org/rfc/rfc9110.html) §8.8.3 and §13.1.
  """

  alias HttpEtag.Error

  @typedoc """
  A parsed entity-tag.

  `opaque` is the octets inside the quotes. `weak` is `true` for a weak tag
  (`W/"…"`).
  """
  @type t :: %__MODULE__{opaque: binary(), weak: boolean()}

  @typedoc "A parsed If-Match or If-None-Match field: a tag list, or `:any` for `*`."
  @type tag_list :: [t()] | :any

  @typedoc "Option for `from_content/2`."
  @type from_content_opt :: {:algorithm, atom()} | {:weak, boolean()}

  @typedoc "Keyword options for `from_content/2`."
  @type from_content_opts :: [from_content_opt()]

  defstruct opaque: "", weak: false

  # RFC 9110 §5.6.1.2: parse a reasonable number of empty list elements.
  @max_list_elements 256

  defguardp is_etagc(c) when c === 0x21 or (c >= 0x23 and c <= 0x7E) or c >= 0x80

  @doc """
  Builds an entity-tag from opaque octets.

  `weak` defaults to `false` (a strong tag). Opaque octets must match RFC 9110
  `etagc` (`!` / `%x23-7E` / obs-text). Double quotes and spaces are rejected.

  An integer is formatted with `Integer.to_string/1` (use `user.lock_version`,
  not `parse/1` of the version string).

  ## Examples

      iex> HttpEtag.new("abc")
      {:ok, %HttpEtag{opaque: "abc", weak: false}}

      iex> HttpEtag.new(1)
      {:ok, %HttpEtag{opaque: "1", weak: false}}

      iex> HttpEtag.new("abc", true)
      {:ok, %HttpEtag{opaque: "abc", weak: true}}

      iex> HttpEtag.new("a b")
      {:error, %HttpEtag.Error{reason: :invalid_etag}}
  """
  @spec new(term()) :: {:ok, t()} | {:error, Error.t()}
  @spec new(term(), term()) :: {:ok, t()} | {:error, Error.t()}
  def new(opaque, weak \\ false)

  def new(n, weak) when is_integer(n) and is_boolean(weak) do
    new(Integer.to_string(n), weak)
  end

  def new(opaque, weak) when is_binary(opaque) and is_boolean(weak) do
    if valid_opaque?(opaque) do
      {:ok, %__MODULE__{opaque: opaque, weak: weak}}
    else
      error(:invalid_etag)
    end
  end

  def new(_opaque, _weak), do: error(:invalid_etag)

  @doc """
  Same as `new/2` but raises `HttpEtag.Error` on failure.

  ## Examples

      iex> HttpEtag.new!("abc")
      %HttpEtag{opaque: "abc", weak: false}

      iex> HttpEtag.new!(42)
      %HttpEtag{opaque: "42", weak: false}
  """
  @spec new!(term()) :: t()
  @spec new!(term(), term()) :: t()
  def new!(opaque, weak \\ false) do
    unwrap!(new(opaque, weak))
  end

  @doc """
  Builds an entity-tag from representation octets.

  Hashes `content` (iodata) with `:sha256` by default and encodes the digest as
  lowercase hex, which is always valid `etagc`. The result is a **strong** tag
  unless `weak: true`.

  Pass canonical bytes you already control (a file, a digest input). Do not
  hash `Jason.encode!/1` of a struct: key order and omitted nils are unstable.
  Prefer `new/2` with `lock_version` (or another unique validator) for Ecto
  rows. `updated_at` at second precision can collide.

  Unknown option keys raise `ArgumentError`. A non-boolean `:weak` or
  non-atom `:algorithm` raises `ArgumentError`. An atom that is not a
  `:crypto.hash_algorithm()` raises from `:crypto.hash/2`.

  ## Options

    * `:algorithm` - a `:crypto.hash_algorithm()`, default `:sha256`
    * `:weak` - when `true`, mark the tag weak

  ## Examples

      iex> tag = HttpEtag.from_content("abc")
      iex> tag.weak
      false
      iex> tag.opaque
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"

      iex> HttpEtag.from_content(["ab", "c"]) == HttpEtag.from_content("abc")
      true
  """
  @spec from_content(iodata()) :: t()
  @spec from_content(iodata(), from_content_opts()) :: t()
  def from_content(content, opts \\ []) do
    opts = Keyword.validate!(opts, algorithm: :sha256, weak: false)
    algorithm = opts |> Keyword.fetch!(:algorithm) |> validate_algorithm()
    weak = opts |> Keyword.fetch!(:weak) |> validate_weak()
    opaque = algorithm |> :crypto.hash(content) |> Base.encode16(case: :lower)
    %__MODULE__{opaque: opaque, weak: weak}
  end

  @doc """
  Parses a single entity-tag.

  Surrounding optional whitespace (SP / HTAB) is ignored. The whole value
  after that must be one entity-tag. `"W/"` is case-sensitive. There is no
  backslash unescaping.

  ## Examples

      iex> HttpEtag.parse(~S("abc"))
      {:ok, %HttpEtag{opaque: "abc", weak: false}}

      iex> HttpEtag.parse(~S(W/"abc"))
      {:ok, %HttpEtag{opaque: "abc", weak: true}}

      iex> HttpEtag.parse(~S(""))
      {:ok, %HttpEtag{opaque: "", weak: false}}
  """
  @spec parse(term()) :: {:ok, t()} | {:error, Error.t()}
  def parse(value) when is_binary(value) do
    rest = trim_ows(value)

    case parse_entity_tag(rest) do
      {:ok, etag, <<>>} -> {:ok, etag}
      _ -> error(:invalid_etag)
    end
  end

  def parse(_value), do: error(:invalid_etag)

  @doc """
  Same as `parse/1` but raises `HttpEtag.Error` on failure.

  ## Examples

      iex> HttpEtag.parse!(~S("abc"))
      %HttpEtag{opaque: "abc", weak: false}
  """
  @spec parse!(term()) :: t()
  def parse!(value), do: unwrap!(parse(value))

  @doc """
  Parses an If-Match or If-None-Match field.

  Returns `{:ok, :any}` for `*`, `{:ok, tags}` for `#entity-tag` (empty list
  elements are ignored), or `{:error, exception}` when the field is invalid.
  `*` mixed with tags is invalid.

  Recipients ignore empty list elements. More than 256 comma-separated
  segments is `:invalid_header` (RFC 9110 §5.6.1.2).

  ## Examples

      iex> HttpEtag.parse_list("*")
      {:ok, :any}

      iex> HttpEtag.parse_list(~S("a", W/"b"))
      {:ok, [%HttpEtag{opaque: "a", weak: false}, %HttpEtag{opaque: "b", weak: true}]}
  """
  @spec parse_list(term()) :: {:ok, tag_list()} | {:error, Error.t()}
  def parse_list(value) when is_binary(value) do
    case trim_ows(value) do
      "*" -> {:ok, :any}
      rest -> parse_list_body(rest, [], 0)
    end
  end

  def parse_list(_value), do: error(:invalid_header)

  @doc """
  Same as `parse_list/1` but raises `HttpEtag.Error` on failure.

  ## Examples

      iex> HttpEtag.parse_list!("*")
      :any
  """
  @spec parse_list!(term()) :: tag_list()
  def parse_list!(value), do: unwrap!(parse_list(value))

  @doc """
  Formats an entity-tag as an `ETag` field value.

  Build the struct with `new/2`, `parse/1`, or `from_content/2`. A hand-built
  struct whose `opaque` contains `"` is not a valid entity-tag.

  ## Examples

      iex> HttpEtag.to_header(%HttpEtag{opaque: "abc", weak: false})
      ~S("abc")

      iex> HttpEtag.to_header(%HttpEtag{opaque: "abc", weak: true})
      ~S(W/"abc")
  """
  @spec to_header(t()) :: String.t()
  def to_header(%__MODULE__{opaque: opaque, weak: true}) do
    <<"W/\"", opaque::binary, "\"">>
  end

  def to_header(%__MODULE__{opaque: opaque, weak: false}) do
    <<"\"", opaque::binary, "\"">>
  end

  @doc """
  Strong comparison (RFC 9110 §8.8.3.2).

  Both tags must be strong and their opaque octets equal. A weak tag never
  matches. Use this for If-Match, not `==` on the struct.

  Comparison uses `==` and is not constant-time. Entity tags are validators,
  not secrets.

  ## Examples

      iex> HttpEtag.strong_match?(HttpEtag.parse!(~S("1")), HttpEtag.parse!(~S("1")))
      true

      iex> HttpEtag.strong_match?(HttpEtag.parse!(~S(W/"1")), HttpEtag.parse!(~S("1")))
      false
  """
  @spec strong_match?(t(), t()) :: boolean()
  def strong_match?(%__MODULE__{weak: false, opaque: left}, %__MODULE__{
        weak: false,
        opaque: right
      }) do
    left == right
  end

  def strong_match?(%__MODULE__{}, %__MODULE__{}), do: false

  @doc """
  Weak comparison (RFC 9110 §8.8.3.2).

  Opaque octets must be equal; weakness is ignored. Use this for If-None-Match.

  Comparison uses `==` and is not constant-time. Entity tags are validators,
  not secrets.

  ## Examples

      iex> HttpEtag.weak_match?(HttpEtag.parse!(~S(W/"1")), HttpEtag.parse!(~S("1")))
      true
  """
  @spec weak_match?(t(), t()) :: boolean()
  def weak_match?(%__MODULE__{opaque: left}, %__MODULE__{opaque: right}), do: left == right

  @doc """
  Evaluates If-Match (RFC 9110 §13.1.1).

  Uses strong comparison. `header` `nil` means the field is absent (no
  precondition) and returns `:ok`. `current` `nil` means the resource has no
  representation. `If-Match: *` succeeds only when `current` is present.

  `current` must be a `%HttpEtag{}` or `nil`. `header` must be a binary or
  `nil`. Any other term raises `ArgumentError`.

  A weak `current` never strongly matches a tag list. Prefer strong tags for
  lost-update protection.

  Returns `:ok` or `{:error, exception}` with `:precondition_failed` or
  `:invalid_header`. Does not choose 412; the caller does.

  ## Examples

      iex> HttpEtag.if_match(HttpEtag.parse!(~S("abc")), ~S("abc"))
      :ok

      iex> HttpEtag.if_match(nil, "*")
      {:error, %HttpEtag.Error{reason: :precondition_failed}}
  """
  @spec if_match(t() | nil, String.t() | nil) :: :ok | {:error, Error.t()}
  def if_match(%__MODULE__{} = current, header) when is_binary(header) or is_nil(header) do
    eval_precondition(current, header, :if_match)
  end

  def if_match(nil, header) when is_binary(header) or is_nil(header) do
    eval_precondition(nil, header, :if_match)
  end

  def if_match(current, header) when is_struct(current, __MODULE__) or is_nil(current) do
    bad_header!(header)
  end

  def if_match(current, _header), do: bad_current!(current)

  @doc """
  Same as `if_match/2` but raises `HttpEtag.Error` on failure.

  ## Examples

      iex> HttpEtag.if_match!(HttpEtag.parse!(~S("abc")), ~S("abc"))
      :ok
  """
  @spec if_match!(t() | nil, String.t() | nil) :: :ok
  def if_match!(current, header), do: unwrap!(if_match(current, header))

  @doc """
  Evaluates If-None-Match (RFC 9110 §13.1.2).

  Uses weak comparison. `header` `nil` returns `:ok`. `If-None-Match: *`
  succeeds only when `current` is `nil`. A tag list fails when any listed tag
  weakly matches `current`. If `current` is `nil`, a tag list succeeds.

  `current` must be a `%HttpEtag{}` or `nil`. `header` must be a binary or
  `nil`. Any other term raises `ArgumentError`.

  Returns `:ok` or `{:error, exception}` with `:precondition_failed` or
  `:invalid_header`. The caller maps a failed GET/HEAD to 304 and other methods
  to 412.

  ## Examples

      iex> HttpEtag.if_none_match(nil, "*")
      :ok

      iex> HttpEtag.if_none_match(HttpEtag.parse!(~S("abc")), ~S("abc"))
      {:error, %HttpEtag.Error{reason: :precondition_failed}}
  """
  @spec if_none_match(t() | nil, String.t() | nil) :: :ok | {:error, Error.t()}
  def if_none_match(%__MODULE__{} = current, header)
      when is_binary(header) or is_nil(header) do
    eval_precondition(current, header, :if_none_match)
  end

  def if_none_match(nil, header) when is_binary(header) or is_nil(header) do
    eval_precondition(nil, header, :if_none_match)
  end

  def if_none_match(current, header) when is_struct(current, __MODULE__) or is_nil(current) do
    bad_header!(header)
  end

  def if_none_match(current, _header), do: bad_current!(current)

  @doc """
  Same as `if_none_match/2` but raises `HttpEtag.Error` on failure.

  ## Examples

      iex> HttpEtag.if_none_match!(nil, "*")
      :ok
  """
  @spec if_none_match!(t() | nil, String.t() | nil) :: :ok
  def if_none_match!(current, header), do: unwrap!(if_none_match(current, header))

  defp eval_precondition(_current, nil, _kind), do: :ok

  defp eval_precondition(current, header, kind) when is_binary(header) do
    case parse_list(header) do
      {:ok, :any} -> eval_star(current, kind)
      {:ok, tags} -> eval_tags(current, tags, kind)
      {:error, %Error{}} = err -> err
    end
  end

  defp eval_star(nil, :if_match), do: error(:precondition_failed)
  defp eval_star(_current, :if_match), do: :ok
  defp eval_star(nil, :if_none_match), do: :ok
  defp eval_star(_current, :if_none_match), do: error(:precondition_failed)

  defp eval_tags(nil, _tags, :if_match), do: error(:precondition_failed)
  defp eval_tags(nil, _tags, :if_none_match), do: :ok

  defp eval_tags(current, tags, :if_match) do
    if Enum.any?(tags, &strong_match?(&1, current)) do
      :ok
    else
      error(:precondition_failed)
    end
  end

  defp eval_tags(current, tags, :if_none_match) do
    if Enum.any?(tags, &weak_match?(&1, current)) do
      error(:precondition_failed)
    else
      :ok
    end
  end

  defp parse_list_body(_rest, _acc, n) when n >= @max_list_elements, do: error(:invalid_header)
  defp parse_list_body(<<>>, acc, _n), do: {:ok, Enum.reverse(acc)}

  defp parse_list_body(rest, acc, n) do
    {acc, rest} =
      case parse_entity_tag(rest) do
        {:ok, etag, rest} -> {[etag | acc], rest}
        :error -> {acc, rest}
      end

    rest = trim_ows_left(rest)

    case rest do
      <<>> -> {:ok, Enum.reverse(acc)}
      <<",", rest::binary>> -> parse_list_body(trim_ows_left(rest), acc, n + 1)
      _ -> error(:invalid_header)
    end
  end

  defp parse_entity_tag(<<"W/", rest::binary>>), do: parse_opaque(rest, true)
  defp parse_entity_tag(rest), do: parse_opaque(rest, false)

  defp parse_opaque(<<"\"", rest::binary>>, weak), do: take_opaque(rest, [], weak)
  defp parse_opaque(_rest, _weak), do: :error

  defp take_opaque(<<"\"", rest::binary>>, acc, weak) do
    {:ok, %__MODULE__{opaque: IO.iodata_to_binary(acc), weak: weak}, rest}
  end

  defp take_opaque(<<c, rest::binary>>, acc, weak) when is_etagc(c) do
    take_opaque(rest, [acc, c], weak)
  end

  defp take_opaque(_rest, _acc, _weak), do: :error

  defp valid_opaque?(<<>>), do: true
  defp valid_opaque?(<<c, rest::binary>>) when is_etagc(c), do: valid_opaque?(rest)
  defp valid_opaque?(_opaque), do: false

  defp trim_ows(value), do: value |> trim_ows_left() |> trim_ows_right()

  defp trim_ows_left(<<c, rest::binary>>) when c === ?\s or c === ?\t, do: trim_ows_left(rest)
  defp trim_ows_left(rest), do: rest

  defp trim_ows_right(<<>>), do: <<>>

  defp trim_ows_right(value) do
    size = byte_size(value) - 1

    case value do
      <<prefix::binary-size(size), c>> when c === ?\s or c === ?\t -> trim_ows_right(prefix)
      _ -> value
    end
  end

  defp validate_weak(weak) when is_boolean(weak), do: weak

  defp validate_weak(other) do
    raise ArgumentError, ":weak must be a boolean, got: #{inspect(other)}"
  end

  defp validate_algorithm(algorithm) when is_atom(algorithm), do: algorithm

  defp validate_algorithm(other) do
    raise ArgumentError,
          ":algorithm must be a :crypto hash algorithm, got: #{inspect(other)}"
  end

  defp bad_current!(current) do
    raise ArgumentError, "current must be a %HttpEtag{} or nil, got: #{inspect(current)}"
  end

  defp bad_header!(header) do
    raise ArgumentError, "header must be a binary or nil, got: #{inspect(header)}"
  end

  defp error(reason), do: {:error, %Error{reason: reason}}

  defp unwrap!(:ok), do: :ok
  defp unwrap!({:ok, result}), do: result
  defp unwrap!({:error, %Error{} = exception}), do: raise(exception)
end
