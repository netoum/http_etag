defmodule HttpEtag.ConnTest do
  use ExUnit.Case, async: true
  import Plug.Test
  doctest HttpEtag.Conn

  alias HttpEtag.Conn, as: EtagConn
  alias HttpEtag.Error

  defp tag, do: HttpEtag.parse!(~S("abc"))

  describe "get_if_match/1 and get_if_none_match/1" do
    test "return the combined field or nil" do
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

    test "combines repeated If-Match field lines" do
      conn = %{
        conn(:get, "/")
        | req_headers: [{"if-match", ~S("a")}, {"if-match", ~S("xyz")}]
      }

      assert EtagConn.get_if_match(conn) == ~S("a", "xyz")
      assert EtagConn.if_match(conn, HttpEtag.parse!(~S("xyz"))) == :ok
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

    test "a missing current fails If-Match: *" do
      conn =
        :get
        |> conn("/")
        |> Plug.Conn.put_req_header("if-match", "*")

      assert {:error, %Error{reason: :precondition_failed}} = EtagConn.if_match(conn, nil)
    end

    test "an invalid field is :invalid_header" do
      conn =
        :get
        |> conn("/")
        |> Plug.Conn.put_req_header("if-match", "nope")

      assert {:error, %Error{reason: :invalid_header}} = EtagConn.if_match(conn, tag())
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

    test "succeeds when the listed tag differs" do
      conn =
        :get
        |> conn("/")
        |> Plug.Conn.put_req_header("if-none-match", ~S("xyz"))

      assert EtagConn.if_none_match(conn, tag()) == :ok
    end
  end
end
