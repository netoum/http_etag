defmodule HttpEtag.Error do
  @moduledoc """
  Exception returned or raised by `HttpEtag`.

  `HttpEtag.parse/1` and `HttpEtag.new/2` return `{:error, exception}` with
  `reason` `:invalid_etag`. `HttpEtag.parse_list/1`, `HttpEtag.if_match/2`, and
  `HttpEtag.if_none_match/2` use `:invalid_header` when the field does not match
  RFC 9110. Bang variants raise.

    * `:invalid_etag` - the value is not a single entity-tag
    * `:invalid_header` - the field is not `"*"` or `#entity-tag`
    * `:precondition_failed` - If-Match or If-None-Match is not satisfied
  """

  @type reason :: :invalid_etag | :invalid_header | :precondition_failed
  @type t :: %__MODULE__{reason: reason()}

  defexception [:reason]

  @impl true
  def message(%__MODULE__{reason: :invalid_etag}) do
    "invalid entity-tag"
  end

  def message(%__MODULE__{reason: :invalid_header}) do
    "invalid If-Match or If-None-Match header"
  end

  def message(%__MODULE__{reason: :precondition_failed}) do
    "precondition failed"
  end

  def message(%__MODULE__{}) do
    "entity-tag error"
  end
end
