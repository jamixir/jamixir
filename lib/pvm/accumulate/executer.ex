defmodule PVM.Accumulate.Executor do
  alias PVM.Accumulate.{Utils, Runner}
  require Logger

  @timeout 5_000  # Increased timeout to 60 seconds to match fuzzer expectations
  #  this is a "sync" facade over the async runner
  #  it allows to have a "function like" call "Executor.run" => return result
  def run(
        service_code,
        initial_context,
        encoded_args,
        gas,
        operands,
        n0_,
        timeslot,
        service_index,
        opts \\ []
      ) do
    Logger.debug("Executor.run: Starting with gas=#{gas}, service_index=#{service_index}, timeslot=#{timeslot}")

    {:ok, pid} =
      Runner.start(
        service_code,
        initial_context,
        encoded_args,
        gas,
        operands,
        n0_,
        timeslot,
        service_index,
        opts
      )

    Logger.debug("Executor.run: Started Runner with pid=#{inspect(pid)}, waiting for result with timeout=#{@timeout}ms")

    receive do
      {used_gas, output, final_ctx} ->
        Logger.debug("Executor.run: Received result - used_gas=#{used_gas}, output=#{inspect(output)}")
        Utils.collapse({used_gas, output, final_ctx})
    after
      @timeout ->
        Logger.error("Executor.run: Timeout after #{@timeout}ms waiting for Runner result")
        {:error, :timeout}
    end
  end
end
