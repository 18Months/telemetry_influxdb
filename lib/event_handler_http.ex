defmodule TelemetryMetricsInfluxDB.EventHandlerHTTP do
  alias TelemetryMetricsInfluxDB.Formatter
  import HTTPoison.Response
  require Logger

  @type event_spec() :: map()
  @type event_name() :: [atom()]
  @type event_measurements :: map()
  @type event_metadata :: map()
  @type handler_config :: term()
  @type handler_id() :: term()

  @spec attach(event_spec, pid(), handler_config()) :: [handler_id()]
  def attach(event_specs, reporter, db_config) do
    Enum.map(event_specs, fn e ->
      handler_id = handler_id(e.name, reporter)
      :ok = :telemetry.attach(handler_id, e.name, &__MODULE__.handle_event/4, db_config)
      handler_id
    end)
  end

  @spec handle_event(event_name(), event_measurements(), event_metadata(), handler_config()) ::
          :ok
  def handle_event(event, measurements, metadata, config) do
    query = config.host <> ":" <> config.port <> "/write?db=" <> config.db
    event_tags = Map.get(metadata, :tags, %{})
    body = Formatter.format(event, measurements, Map.merge(config.tags, event_tags))

    headers =
      Map.merge(authentication_header(config.username, config.password), binary_data_header())

    process_response(HTTPoison.post(query, body, headers))
  end

  @spec detach([handler_id()]) :: :ok
  def detach(handler_ids) do
    for handler_id <- handler_ids do
      :telemetry.detach(handler_id)
    end

    :ok
  end

  @spec handler_id(event_name(), reporter :: pid) :: handler_id()
  defp handler_id(event_name, reporter) do
    {__MODULE__, reporter, event_name}
  end

  defp process_response({:ok, %HTTPoison.Response{status_code: 204}}), do: :ok

  defp process_response({:ok, %HTTPoison.Response{status_code: 404}}) do
    Logger.error("Failed to push data to InfluxDB. Invalid credentials")
    :ok
  end

  defp process_response({:ok, %{status_code: 401}}) do
    Logger.error("Failed to push data to InfluxDB. Invalid credentials")
    :ok
  end

  defp process_response(res) do
    Logger.error("Failed to send event to InfluxDB. Response: #{inspect(res)}")
    :ok
  end

  defp authentication_header(username, password) do
    %{"Authorization" => "Basic #{Base.encode64(username <> ":" <> password)}"}
  end

  defp binary_data_header() do
    %{"Content-Type" => "text/plain"}
  end
end