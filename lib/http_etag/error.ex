defmodule HttpEtag.Error do
  @moduledoc """
  Exception returned or raised by `HttpEtag`.

  Untrusted field text returns `{:error, exception}` (or the bang variant
  raises). Programmer mistakes raise `ArgumentError` instead.

    * `:invalid_etag` - the value is not a single entity-tag
    * `:invalid_header` - the field is not `"*"` or `#entity-tag`
    * `:precondition_failed` - If-Match or If-None-Match is not satisfied

  ## Examples

      iex> Exception.message(%HttpEtag.Error{reason: :invalid_etag})
      "invalid entity-tag"

      iex> Exception.message(%HttpEtag.Error{reason: :invalid_header})
      "invalid If-Match or If-None-Match header"

      iex> Exception.message(%HttpEtag.Error{reason: :precondition_failed})
      "precondition failed"
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
