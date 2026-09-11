# HttpEtag

[![CI](https://github.com/netoum/http_etag/actions/workflows/ci.yml/badge.svg)](https://github.com/netoum/http_etag/actions/workflows/ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/http_etag.svg)](https://hex.pm/packages/http_etag)
[![Hexdocs.pm](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/http_etag/)

RFC 9110 entity tags and If-Match / If-None-Match for Elixir.

Parses `ETag` / If-Match / If-None-Match and reports whether a precondition is
satisfied. You map that onto 304 or 412. This library does not set
`Cache-Control` and is not a replacement for `Plug.Static`.

```elixir
iex> {:ok, tag} = HttpEtag.new(1)
iex> HttpEtag.to_header(tag)
~S("1")

iex> HttpEtag.if_none_match(tag, ~S("1"))
{:error, %HttpEtag.Error{reason: :precondition_failed}}
```

## Installation

```elixir
def deps do
  [
    {:http_etag, "~> 0.1.0"}
  ]
end
```

`HttpEtag.Conn` is compiled when `Plug.Conn` is available. Add `:plug` if it
is not already in the project (Phoenix already depends on it). Conn only
reads and writes headers; the caller sends 304 or 412.

## Minting tags

Use `new/2` for an opaque validator. Integers are allowed so Ecto
`lock_version` works directly. Prefer that over `updated_at` (second
precision can collide).

```elixir
etag = HttpEtag.new!(user.lock_version)
HttpEtag.to_header(etag)
# => "\"1\""
```

`new("1")` is opaque `1`. `parse(~S("1"))` is the quoted wire field. Do not
`parse("#{user.lock_version}")`.

`from_content/2` hashes **canonical iodata you already have** (file bytes, a
digest input). Do not hash `Jason.encode!(user)`: key order and omitted nils
are unstable.

```elixir
HttpEtag.from_content(file_bytes)
HttpEtag.from_content(["prefix", body], algorithm: :sha512)
```

Weak tags never satisfy If-Match.

## GET and HEAD → 304

`:ok` means send the body. `:precondition_failed` means the client's tag
matches (304). Put `ETag` on both the 200 and the 304.

```elixir
etag = HttpEtag.new!(user.lock_version)

case HttpEtag.Conn.if_none_match(conn, etag) do
  :ok ->
    conn |> HttpEtag.Conn.put_etag(etag) |> json(user)

  {:error, %{reason: :precondition_failed}} ->
    conn
    |> HttpEtag.Conn.put_etag(etag)
    |> Plug.Conn.send_resp(304, "")

  {:error, %{reason: :invalid_header}} ->
    Plug.Conn.send_resp(conn, 400, "")
end
```

HEAD uses the same `if_none_match/2` call.

## PATCH, PUT, and DELETE → 412

```elixir
etag = HttpEtag.new!(user.lock_version)

case HttpEtag.Conn.if_match(conn, etag) do
  :ok ->
    with {:ok, patched} <- JsonMergePatch.apply_patch(document, patch) do
      save(patched)
    end

  {:error, %{reason: :precondition_failed}} ->
    conn
    |> HttpEtag.Conn.put_etag(etag)
    |> Plug.Conn.send_resp(412, "")

  {:error, %{reason: :invalid_header}} ->
    Plug.Conn.send_resp(conn, 400, "")
end
```

[`json_merge_patch`](https://hex.pm/packages/json_merge_patch)
([docs](https://hexdocs.pm/json_merge_patch)) is a separate library;
this package does not depend on it.

Authorize the change in the caller. See
[RFC 9110](https://www.rfc-editor.org/rfc/rfc9110.html) §13.1.

## Related

- [`json_merge_patch`](https://hex.pm/packages/json_merge_patch) —
  RFC 7396 merge patch for a PATCH body
- [`plug`](https://hex.pm/packages/plug) — optional `HttpEtag.Conn`.
  `Plug.Static` serves files and compares If-None-Match with
  `etag in get_req_header(conn, "if-none-match")` (raw field-line membership).
  That misses comma lists, `W/"…"`, and `*`. Use this library for resource
  If-Match / If-None-Match.
- [`plug_http_validator`](https://hex.pm/packages/plug_http_validator) —
  sets ETag / Last-Modified on responses from structs; does not parse
  If-Match / If-None-Match

## Sponsor

[![Netoum](https://i.ibb.co/Zp0MC9VL/netoum-square-1.png)](https://netoum.com)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). This project follows the
[Code of Conduct](CODE_OF_CONDUCT.md).

## License

MIT © [Netoum](https://netoum.com). See `LICENSE`.
