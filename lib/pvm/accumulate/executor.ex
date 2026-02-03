defmodule PVM.Accumulate.Executor do
  alias PVM.Accumulate.{Runner, Utils}
  import Util.Hex
  import Codec.Encoder
  require Logger

  # high timeout to support PVM_TRACE
  @timeout 10_000
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

    # immediately handle out-of-gas case
    if gas == 0 do
      Utils.collapse({0, :out_of_gas, {initial_context, initial_context}})
    else
      start_time = System.monotonic_time(:millisecond)

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
          end_time = System.monotonic_time(:millisecond)

          Logger.info(
            "Accumulate.Executor.run: Received result - used_gas=#{used_gas}, output=#{inspect(output)} [id: #{service_index}] after #{end_time - start_time}ms"
          )

          Utils.collapse({used_gas, output, final_ctx})
      after
        @timeout ->
          Logger.error("Executor.run: Timeout after #{@timeout}ms waiting for Runner result")
          {:error, :timeout}
      end
    end
  end
end
