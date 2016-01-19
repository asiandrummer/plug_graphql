defmodule GraphQL.Plug.Endpoint do
  import Plug.Conn
  alias Plug.Conn

  @behaviour Plug


  require EEx
  EEx.function_from_file :defp, :graphiql_html,
    Path.absname(Path.relative_to_cwd("templates/graphiql.eex")),
    [:graphiql_version, :query, :variables, :result]

  def init(opts) do
    schema = case Keyword.get(opts, :schema) do
      {mod, func} -> apply(mod, func, [])
      s -> s
    end
    %{schema: schema}
  end

  def call(%Conn{method: m} = conn, opts) when m in ["GET", "POST"] do
    %{schema: schema} = conn.assigns[:graphql_options] || opts

    query = query(conn)
    cond do
      query && use_graphiql?(conn) -> handle_graphiql_call(conn, schema, query)
      query -> handle_call(conn, schema, query)
      true -> handle_error(conn, "Must provide query string.")
    end
  end

  def call(%Conn{method: _} = conn, _) do
    handle_error(conn, "GraphQL only supports GET and POST requests.")
  end

  defp handle_call(conn, schema, query) do
    conn
    |> put_resp_content_type("application/json")
    |> execute(schema, query)
  end

  defp handle_graphiql_call(conn, schema, query) do
    {:ok, data} = GraphQL.execute(schema, query)
    {:ok, result} = Poison.encode(%{data: data})
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, graphiql_html("0.4.4", query, nil, result))
  end

  defp handle_error(conn, message) do
    {:ok, errors} = Poison.encode %{errors: [%{message: message}]}
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(400, errors)
  end

  defp execute(conn, schema, query) do
    case GraphQL.execute(schema, query) do
      {:ok, data} ->
        case Poison.encode(%{data: data}) do
          {:ok, json}      -> send_resp(conn, 200, json)
          {:error, errors} -> send_resp(conn, 400, errors)
        end
      {:error, errors} ->
        case Poison.encode(errors) do
          {:ok, json}      -> send_resp(conn, 400, json)
          {:error, errors} -> send_resp(conn, 400, errors)
        end
    end
  end

  defp query(%Conn{params: %{"query" => query}}) do
    if query && String.strip(query) != "", do: query, else: nil
  end

  defp query(_) do
    nil
  end

  defp use_graphiql?(conn) do
    case get_req_header(conn, "accept") do
      [accept_header | _] ->
        String.contains?(accept_header, "text/html") &&
        !Map.has_key?(conn.params, "raw")
      _ ->
        false
    end
  end
end
