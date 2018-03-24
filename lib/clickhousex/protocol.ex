defmodule Clickhousex.Protocol do
  @moduledoc false

  require Logger
  @behaviour DBConnection

  defstruct [pid: nil, clickhouse: :idle, conn_opts: []]

  @type state :: %__MODULE__{
                   pid: pid(),
                   clickhouse: :idle,
                   conn_opts: Keyword.t
                 }

  @type query :: Clickhousex.Query.t
  @type params :: [{:odbc.odbc_data_type(), :odbc.value()}]
  @type result :: Clickhousex.Result.t
  @type cursor :: any

  @doc false
  @spec connect(opts :: Keyword.t) :: {:ok, state} |
                                      {:error, Exception.t}
  def connect(opts) do
    driver = opts[:driver] || "/usr/local/lib/libclickhouseodbc.so"
    host = opts[:hostname] || "localhost"
    port = opts[:port] || 8123
    database = opts[:database] || "default"
    username = opts[:username] || ""
    password = opts[:password] || ""
    timeout = opts[:timeout] || Clickhousex.timeout()

    conn_opts = [
      {"DRIVER", driver},
      {"SERVER", host},
      {"PORT", port},
      {"USERNAME", username},
      {"PASSWORD", password},
      {"DATABASE", database},
      {"TIMEOUT", timeout}
    ]
    conn_str = Enum.reduce(conn_opts, "", fn {key, value}, acc -> acc <> "#{key}=#{value};" end)

    case Clickhousex.ODBC.start_link(conn_str, opts) do
      {:ok, pid} -> {:ok, %__MODULE__{
        pid: pid,
        conn_opts: opts,
        clickhouse: :idle
      }}
      response -> response
    end
  end

  @doc false
  @spec disconnect(err :: Exception.t, state) :: :ok
  def disconnect(_err, %{pid: pid} = state) do
    case Clickhousex.ODBC.disconnect(pid) do
      :ok -> :ok
      {:error, reason} -> {:error, reason, state}
    end
  end

  @spec ping(state) ::
    {:ok, state} |
    {:disconnect, term, state}
  def ping(state) do
    query = %Clickhousex.Query{name: "ping", statement: "SELECT 1"}
    case do_query(query, [], [], state) do
      {:ok, _, new_state} -> {:ok, new_state}
      {:error, reason, new_state} -> {:disconnect, reason, new_state}
      other -> other
    end
  end

  @doc false
  @spec reconnect(new_opts :: Keyword.t, state) :: {:ok, state}
  def reconnect(new_opts, state) do
    with :ok <- disconnect("Reconnecting", state),
         do: connect(new_opts)
  end

  @spec checkin(state) ::
    {:ok, state} |
    {:disconnect, term, state}
  def checkin(state) do
    {:ok, state}
  end

  @spec checkout(state) ::
    {:ok, state} |
    {:disconnect, term, state}
  def checkout(state) do
    {:ok, state}
  end

  @spec handle_prepare(Clickhousex.Query.t, Keyword.t, state) ::
      {:ok, Clickhousex.Query.t, state} |
      {:error, %ArgumentError{} | term, state} |
      {:error | :disconnect, %RuntimeError{}, state} |
      {:disconnect, %DBConnection.ConnectionError{}, state}
  def handle_prepare(query, _, state) do
    {:ok, query, state}
  end

  @doc false
  @spec handle_execute(query, params, opts :: Keyword.t, state) ::
          {:ok, result, state} |
          {:error | :disconnect, Exception.t, state}
  def handle_execute(query, params, opts, state) do
    do_query(query, params, opts, state)
  end

  defp do_query(query, params, opts, state) do
    case Clickhousex.ODBC.query(state.pid, query.statement, params, opts) do
      {:error,
        %Clickhousex.Error{odbc_code: :connection_exception} = reason} ->
        {:disconnect, reason, state}
      {:error, reason} ->
        {:error, reason, state}
      {:selected, columns, rows} ->
        {
          :ok,
          %Clickhousex.Result{
            command: :selected,
            columns: Enum.map(columns, &(to_string(&1))),
            rows: rows,
            num_rows: Enum.count(rows)
          },
          state
        }
      {:updated, count} ->
        {
          :ok,
          %Clickhousex.Result{
            command: :updated,
            columns: ["count"],
            rows: [[count]],
            num_rows: 1
          },
          state
        }
      {command, columns, rows} ->
        {
          :ok,
          %Clickhousex.Result{
            command: command,
            columns: Enum.map(columns, &(to_string(&1))),
            rows: rows,
            num_rows: Enum.count(rows)
          },
          state
        }
    end
  end

  def handle_begin(opts, state) do
    {:ok, %Clickhousex.Result{}, state}
  end

  @spec handle_close(Clickhousex.Query.t, Keyword.t, state) ::
    {:ok, Clickhousex.Result.t, state} |
    {:error, %ArgumentError{} | term, state} |
    {:error | :disconnect, %RuntimeError{}, state} |
    {:disconnect, %DBConnection.ConnectionError{}, state}
  def handle_close(query, opts, state) do
    {:ok, %Clickhousex.Result{}, state}
  end

  def handle_commit(opts, state) do
    {:ok, %Clickhousex.Result{}, state}
  end

  def handle_info(msg, state) do
    {:ok, state}
  end

  def handle_rollback(opts, state) do
    {:ok, %Clickhousex.Result{}, state}
  end

#  def handle_deallocate(query, cursor, opts, state) do
#    {:ok, %Clickhousex.Result{}, state}
#  end

#  def handle_declare(query, params, opts, state) do
#    {:ok, nil, state}
#  end

#  def handle_first(query, cursor, opts, state) do
#    {:ok, %Clickhousex.Result{}, state}
#  end

#  def handle_next(query, cursor, opts, state) do
#    {:ok, %Clickhousex.Result{}, state}
#  end
end
