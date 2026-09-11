if Code.ensure_loaded?(Plug.Conn) do
  defmodule HttpEtag.Conn do
    @moduledoc """
    `Plug.Conn` helpers. Requires the optional `:plug` dependency.

    These are not a pipeline plug. They read and write headers only; they do
    not send 304, 412, or 400. Load the resource, mint a tag with
    `HttpEtag.new!/1` (for example `user.lock_version`), then call `if_match/2`
    or `if_none_match/2`. Repeated If-Match / If-None-Match field lines are
    combined with `", "` (RFC 9110 §5.3).

    `if_match/2` and `if_none_match/2` return the same RFC tuples as
    `HttpEtag`. This is not `Plug.Static`: that plug compares If-None-Match as
    raw field-line membership.

    ## Examples

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

    See `HttpEtag.if_match/2` and `HttpEtag.if_none_match/2`.
    """

    alias Plug.Conn

    @doc """
    Returns the combined `If-Match` request field, or `nil` if it is absent.

    Repeated field lines are joined with `", "` (RFC 9110 §5.3).
    """
    @spec get_if_match(Conn.t()) :: String.t() | nil
    def get_if_match(%Conn{} = conn), do: combined_header(conn, "if-match")

    @doc """
    Returns the combined `If-None-Match` request field, or `nil` if it is absent.

    Repeated field lines are joined with `", "` (RFC 9110 §5.3).
    """
    @spec get_if_none_match(Conn.t()) :: String.t() | nil
    def get_if_none_match(%Conn{} = conn), do: combined_header(conn, "if-none-match")

    @doc """
    Sets the `ETag` response header from a parsed tag.
    """
    @spec put_etag(Conn.t(), HttpEtag.t()) :: Conn.t()
    def put_etag(%Conn{} = conn, %HttpEtag{} = tag) do
      Conn.put_resp_header(conn, "etag", HttpEtag.to_header(tag))
    end

    @doc """
    Evaluates `If-Match` on `conn` against `current`.

    See `HttpEtag.if_match/2`.
    """
    @spec if_match(Conn.t(), HttpEtag.t() | nil) :: :ok | {:error, HttpEtag.Error.t()}
    def if_match(%Conn{} = conn, current) do
      HttpEtag.if_match(current, get_if_match(conn))
    end

    @doc """
    Evaluates `If-None-Match` on `conn` against `current`.

    See `HttpEtag.if_none_match/2`.
    """
    @spec if_none_match(Conn.t(), HttpEtag.t() | nil) :: :ok | {:error, HttpEtag.Error.t()}
    def if_none_match(%Conn{} = conn, current) do
      HttpEtag.if_none_match(current, get_if_none_match(conn))
    end

    defp combined_header(conn, name) do
      case Conn.get_req_header(conn, name) do
        [] -> nil
        values -> Enum.join(values, ", ")
      end
    end
  end
end
