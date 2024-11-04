defmodule System.State.AuthorizerPool do
  alias Block.Extrinsic.Guarantee
  alias Block.Extrinsic.Guarantee.WorkReport
  # Formula (86) v0.4.5
  def calculate_authorizer_pool_(
        guarantees,
        authorizer_queue_,
        authorizer_pools,
        timeslot
      ) do
    for(
      {{current_pool, queue}, core_index} <-
        Enum.zip(authorizer_pools, authorizer_queue_) |> Enum.with_index()
    ) do
      adjusted_pool = remove_oldest_used_authorizer(core_index, current_pool, guarantees)

      selected_queue_element =
        Enum.at(queue, rem(timeslot, Constants.max_authorization_queue_items()))

      (adjusted_pool ++ [selected_queue_element])
      |> Enum.take(-Constants.max_authorizations_items())
    end
  end

  # Formula (87) v0.4.5 F(c)
  def remove_oldest_used_authorizer(core_index, current_pool, guarantees) do
    case Enum.find(guarantees, &(&1.work_report.core_index == core_index)) do
      nil ->
        current_pool

      %Guarantee{work_report: %WorkReport{authorizer_hash: hash}} ->
        {left, right} = Enum.split_while(current_pool, &(&1 != hash))

        case right do
          [] -> left
          [_ | tail] -> left ++ tail
        end
    end
  end
end
