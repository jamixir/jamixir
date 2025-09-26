defmodule PVM.OnTransfer.Executor do
  alias System.State.ServiceAccount
  alias PVM.OnTransfer.{OnTransferParams, Runner}
  require Logger

  @timeout 2_000
  def run(
        service_code,
        service,
        args,
        gas,
        %OnTransferParams{} = params,
        opts \\ []
      ) do
    Logger.debug(
      "OnTransfer.Executor.run: Starting with gas=#{gas}, service_index=#{inspect(service)}"
    )

    {:ok, pid} = Runner.start(service_code, service, args, gas, params, opts)

    Logger.debug(
      "OnTransfer.Executor.run: Started Runner with pid=#{inspect(pid)}, waiting result timeout=#{@timeout}ms"
    )

    receive do
      {used_gas, %ServiceAccount{} = service_} ->
        Logger.debug(
          "OnTransfer.Executor.run: Received result - used_gas=#{used_gas}, output=#{inspect(service_)}"
        )

        {service_, used_gas}
    after
      @timeout ->
        Logger.error(
          "OnTransfer.Executor.run: Timeout after #{@timeout}ms waiting for Runner result"
        )

        {:error, :timeout}
    end
  end
end
