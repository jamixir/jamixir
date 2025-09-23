defmodule PVM.Refine.Executor do
  alias PVM.Host.Refine
  alias PVM.Refine.RefineParams
  alias PVM.Refine.Runner
  require Logger

  # Increased timeout to 60 seconds to match fuzzer expectations
  @timeout 5_000
  #  this is a "sync" facade over the async runner
  #  it allows to have a "function like" call "Executor.run" => return result
  def run(
        service_code,
        refine_context,
        encoded_args,
        gas,
        %RefineParams{work_package: wp} = refine_params,
        opts \\ []
      ) do
    Logger.debug("Refine.Executor.run: Starting with gas=#{gas}, service_index=#{wp.service}")

    {:ok, pid} =
      Runner.start(service_code, refine_context, encoded_args, gas, refine_params, opts)

    Logger.debug(
      "Refine.Executor.run: Started Runner with pid=#{inspect(pid)}, waiting for result with timeout=#{@timeout}ms"
    )

    receive do
      {used_gas, result, %Refine.Context{e: exports}} ->
        Logger.debug(
          "Refine.Executor.run: Received result - used_gas=#{used_gas}, output=#{inspect(result)}"
        )

        {result, exports, used_gas}
    after
      @timeout ->
        Logger.error("Refine.Executor.run: Timeout after #{@timeout}ms waiting for Runner result")
        {:error, :timeout}
    end
  end
end
