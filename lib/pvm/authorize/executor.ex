defmodule PVM.Authorize.Executor do
  alias PVM.Authorize.Runner
  require Logger

  @timeout 200

  def run(service_code, args, wp, opts \\ []) do
    Logger.debug("Authorize.Executor.run: service_index=#{wp.service}")

    {:ok, pid} = Runner.start(service_code, args, wp, opts)

    Logger.debug(
      "Authorize.Executor.run: Started Runner with pid=#{inspect(pid)}, waiting result timeout=#{@timeout}ms"
    )

    receive do
      {used_gas, result} ->
        Logger.debug(
          "Authorize.Executor.run: Received result - used_gas=#{used_gas}, output=#{inspect(result)}"
        )

        {result, used_gas}
    after
      @timeout ->
        Logger.error(
          "Authorize.Executor.run: Timeout after #{@timeout}ms waiting for Runner result"
        )

        {:error, :timeout}
    end
  end
end
