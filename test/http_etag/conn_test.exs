defmodule HttpEtag.ConnTest do
  use ExUnit.Case, async: true
  import Plug.Test

  alias HttpEtag.Conn, as: EtagConn
  alias HttpEtag.Error

  defp tag, do: HttpEtag.parse!(~S("abc"))

  describe "get_if_match/1 and get_if_none_match/1" do
    test "return the first header or nil" do
      conn = conn(:get, "/")
      assert EtagConn.get_if_match(conn) == nil
      assert EtagConn.get_if_none_match(conn) == nil

      conn =
        conn
        |> Plug.Conn.put_req_header("if-match", ~S("abc"))
        |> Plug.Conn.put_req_header("if-none-match", ~S(W/"abc"))

      assert EtagConn.get_if_match(conn) == ~S("abc")
      assert EtagConn.get_if_none_match(conn) == ~S(W/"abc")
    end
  end

  describe "put_etag/2" do
    test "sets the ETag response header" do
      conn = :get |> conn("/") |> EtagConn.put_etag(tag())
      assert Plug.Conn.get_resp_header(conn, "etag") == [~S("abc")]
    end
  end

  describe "if_match/2" do
    test "evaluates If-Match from the request" do
      current = tag()
      missing = conn(:get, "/")
      assert EtagConn.if_match(missing, current) == :ok

      matched =
        :get
        |> conn("/")
        |> Plug.Conn.put_req_header("if-match", ~S("abc"))

      assert EtagConn.if_match(matched, current) == :ok

      failed =
        :get
        |> conn("/")
        |> Plug.Conn.put_req_header("if-match", ~S("xyz"))

      assert {:error, %Error{reason: :precondition_failed}} =
               EtagConn.if_match(failed, current)
    end
  end

  describe "if_none_match/2" do
    test "evaluates If-None-Match from the request" do
      current = tag()
      missing = conn(:get, "/")
      assert EtagConn.if_none_match(missing, current) == :ok

      stale =
        :get
        |> conn("/")
        |> Plug.Conn.put_req_header("if-none-match", ~S(W/"abc"))

      assert {:error, %Error{reason: :precondition_failed}} =
               EtagConn.if_none_match(stale, current)
    end
  end
end
