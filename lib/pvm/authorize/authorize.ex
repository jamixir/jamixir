defmodule PVM.Authorize do
  alias Block.Extrinsic.WorkPackage
  alias PVM.Authorize.Executor
  alias PVM.Host
  alias PVM.Host.General
  alias PVM.Host.General.FetchArgs
  import Codec.Encoder
  import PVM.Constants.{HostCallId, HostCallResult}
  import PVM.Host.Gas

  def execute(%WorkPackage{} = p, core_index, services) do
    p_u = WorkPackage.authorization_code(p, services)

    w_a = Constants.max_is_authorized_code_size()

    case p_u do
      nil ->
        {:bad, 0}

      bytes when byte_size(bytes) > w_a ->
        {:big, 0}

      _ ->
        args = e(t(core_index))
        Executor.run(p_u, args, p)
    end
  end

  def handle_host_call(n, %{gas: gas, registers: registers, memory_ref: memory_ref}, p) do
    # Formula (B.2) v0.7.2
    host_call_result =
      case host(n) do
        :gas ->
          Host.General.gas(gas, registers, memory_ref, nil)

        :fetch ->
          Host.General.fetch(%FetchArgs{
            gas: gas,
            registers: registers,
            memory_ref: memory_ref,
            work_package: p,
            n: nil,
            authorizer_trace: nil,
            index: nil,
            import_segments: nil,
            preimages: nil,
            operands: nil,
            transfers: nil,
            context: nil
          })

        :log ->
          Host.General.log(gas, registers, memory_ref, nil)

        _ ->
          g_ = gas - default_gas()

          %General.Result{
            exit_reason: if(g_ < 0, do: :out_of_gas, else: :continue),
            gas: gas - default_gas(),
            registers: %{registers | r: put_elem(registers.r, 7, what())}
          }
      end

    %{exit_reason: e, gas: g, registers: r, context: _c} = host_call_result

    {e, %{gas: g, registers: r}}
  end
end
