defmodule PVM.Accumulate.Executor do
  alias PVM.Accumulate.{Utils, Runner}
  require Logger

  # high timeout to support PVM_TRACE
  @timeout 5000
  def run(
        service_code,
        initial_context,
        encoded_args,
        gas,
        accumulation_inputs,
        n0_,
        timeslot,
        service_index,
        opts \\ []
      ) do
    Logger.debug(
      "Executor.run: Starting with gas=#{gas}, service_index=#{service_index}, timeslot=#{timeslot}"
    )

    {:ok, pid} =
      Runner.start(
        service_code,
        initial_context,
        encoded_args,
        gas,
        accumulation_inputs,
        n0_,
        timeslot,
        opts
      )

    Logger.debug(
      "Executor.run: Started Runner with pid=#{inspect(pid)}, waiting for result with timeout=#{@timeout}ms"
    )

    receive do
      {used_gas, output, final_ctx} ->
        Logger.debug(
          "Executor.run: Received result - used_gas=#{used_gas}, output=#{inspect(output)} [id: #{service_index}]"
        )

        Utils.collapse({used_gas, output, final_ctx})
    after
      @timeout ->
        Logger.error("Executor.run: Timeout after #{@timeout}ms waiting for Runner result")
        {:error, :timeout}
    end
  end
end
