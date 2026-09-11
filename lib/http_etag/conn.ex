if Code.ensure_loaded?(Plug.Conn) do
  defmodule HttpEtag.Conn do
    @moduledoc """
    `Plug.Conn` helpers. Requires the optional `:plug` dependency.

    These are not a pipeline plug. Load the resource's current tag in the
    controller (or equivalent), then call `if_match/2` or `if_none_match/2`.
    """

    alias Plug.Conn

    @doc """
    Returns the first `If-Match` request header, or `nil` if it is absent.
    """
    @spec get_if_match(Conn.t()) :: String.t() | nil
    def get_if_match(%Conn{} = conn), do: first_header(conn, "if-match")

    @doc """
    Returns the first `If-None-Match` request header, or `nil` if it is absent.
    """
    @spec get_if_none_match(Conn.t()) :: String.t() | nil
    def get_if_none_match(%Conn{} = conn), do: first_header(conn, "if-none-match")

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

    defp first_header(conn, name) do
      case Conn.get_req_header(conn, name) do
        [value | _] -> value
        [] -> nil
      end
    end
  end
end
