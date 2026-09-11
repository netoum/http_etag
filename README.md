# HttpEtag

[![CI](https://github.com/netoum/http_etag/actions/workflows/ci.yml/badge.svg)](https://github.com/netoum/http_etag/actions/workflows/ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/http_etag.svg)](https://hex.pm/packages/http_etag)
[![Hexdocs.pm](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/http_etag/)

RFC 9110 entity tags and If-Match / If-None-Match for Elixir.

Parses `ETag` / If-Match / If-None-Match field values and reports whether a
precondition is satisfied. The caller maps that onto 304 or 412. Optional
`Plug.Conn` helpers live in `HttpEtag.Conn` when `:plug` is in the project.

```elixir
HttpEtag.parse(~S("abc"))
HttpEtag.if_match(current, if_match_header)
HttpEtag.if_none_match(current, if_none_match_header)
```

## Installation

```elixir
def deps do
  [
    {:http_etag, "~> 0.1.0"}
  ]
end
```

## Generating tags

Mint a **strong** tag from a version (weak tags never satisfy If-Match):

```elixir
{:ok, etag} = HttpEtag.new(Integer.to_string(version))
HttpEtag.to_header(etag)
# => "\"1\""
```

Hash representation bytes with `from_content/2` (SHA-256 hex, strong by
default):

```elixir
etag = HttpEtag.from_content(body)
HttpEtag.from_content(body, weak: true)
HttpEtag.from_content(body, algorithm: :sha512)
```

Build tags with `new/2`, `parse/1`, or `from_content/2`. Hand-built structs
with a `"` in `opaque` are not valid entity-tags.

## Usage

`HttpEtag.parse/1` and `HttpEtag.parse_list/1` return `{:ok, result}` or
`{:error, exception}`. Bang variants raise `HttpEtag.Error`.

```elixir
HttpEtag.parse(~S("abc"))
HttpEtag.parse(~S(W/"abc"))
HttpEtag.parse_list(~S("a", W/"b"))
HttpEtag.parse_list("*")
```

Missing headers are `nil` and skip the precondition (`:ok`). An empty string
is an empty list, not a missing header.

`current` must be a `%HttpEtag{}` or `nil`. Any other term raises
`ArgumentError`.

## Optional Plug integration

Add `:plug` to the project (Phoenix already does). `HttpEtag.Conn` is
compiled only when `Plug.Conn` is available.

### GET → 304

```elixir
case HttpEtag.Conn.if_none_match(conn, etag) do
  :ok ->
    conn
    |> HttpEtag.Conn.put_etag(etag)
    |> send_resource()

  {:error, %HttpEtag.Error{reason: :precondition_failed}} ->
    conn
    |> HttpEtag.Conn.put_etag(etag)
    |> Plug.Conn.send_resp(304, "")

  {:error, %HttpEtag.Error{reason: :invalid_header}} ->
    Plug.Conn.send_resp(conn, 400, "")
end
```

### PATCH → 412 then merge patch

```elixir
with :ok <- HttpEtag.Conn.if_match(conn, etag),
     {:ok, patched} <- JsonMergePatch.apply_patch(document, patch) do
  save(patched)
end
```

`json_merge_patch` is a separate library; this package does not depend on it.

Authorize the change in the caller. See
[RFC 9110](https://www.rfc-editor.org/rfc/rfc9110.html) §13.1.

## Sponsor

[![Netoum](https://i.ibb.co/Zp0MC9VL/netoum-square-1.png)](https://netoum.com)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). This project follows the
[Code of Conduct](CODE_OF_CONDUCT.md).

## License

MIT © [Netoum](https://netoum.com). See `LICENSE`.
