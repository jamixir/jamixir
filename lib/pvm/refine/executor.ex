defmodule PVM.Refine.Executor do
  alias PVM.Host.Refine
  alias PVM.Refine.RefineParams
  alias PVM.Refine.Runner
  require Logger

  @timeout 5_000
  def run(
        service_code,
        refine_context,
        args,
        gas,
        %RefineParams{work_package: wp} = refine_params,
        opts \\ []
      ) do
    Logger.debug("Refine.Executor.run: Starting with gas=#{gas}, service_index=#{wp.service}")
    start_time = System.monotonic_time(:millisecond)
    {:ok, pid} = Runner.start(service_code, refine_context, args, gas, refine_params, opts)

    Logger.debug(
      "Refine.Executor.run: Started Runner with pid=#{inspect(pid)}, waiting result timeout=#{@timeout}ms"
    )

    receive do
      {used_gas, result, %Refine.Context{e: exports}} ->
        end_time = System.monotonic_time(:millisecond)

        Logger.info(
          "Refine.Executor.run: Received result - used_gas=#{used_gas}, output=#{inspect(result)} after #{end_time - start_time}ms"
        )

        {result, exports, used_gas}
    after
      @timeout ->
        Logger.error("Refine.Executor.run: Timeout after #{@timeout}ms waiting for Runner result")
        {:error, :timeout}
    end
  end
end
