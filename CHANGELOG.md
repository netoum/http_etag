# Changelog

## v0.2.0 (2026-09-11)

  * [HttpEtag] Add `from_content/2` to mint a strong SHA-256 tag from iodata
  * [HttpEtag.Conn] Add optional `Plug.Conn` helpers (requires `:plug`)
  * [HttpEtag] Cap If-Match / If-None-Match lists at 256 comma-separated segments
  * [HttpEtag] Raise `ArgumentError` when `current` is not a `%HttpEtag{}` or `nil`

## v0.1.0 (2026-09-11)

Initial release. RFC 9110 entity tags and If-Match / If-None-Match.

  * [HttpEtag] Add `parse/1`, `parse_list/1`, `new/2`, and `to_header/1`
  * [HttpEtag] Add `strong_match?/2` and `weak_match?/2`
  * [HttpEtag] Add `if_match/2` and `if_none_match/2` with bang variants
  * [HttpEtag.Error] Add `:invalid_etag`, `:invalid_header`, and `:precondition_failed`
