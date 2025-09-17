defmodule Block.Extrinsic.GuarantorAssignments do
  alias System.State.Validator
  alias Util.Time

  # Formula (11.18) v0.7.2
  # M ∈ (⟦ℕ_C⟧_V, ⟦K⟧_V)
  @type t :: %__MODULE__{
          assigned_cores: list(non_neg_integer()),
          validators: list(Validator.t())
        }

  defstruct assigned_cores: [],
            # d
            validators: []

  # Formula (11.19) v0.7.2
  def rotate(c, n), do: for(x <- c, do: rem(x + n, Constants.core_count()))

  # Formula (11.20) v0.7.2
  def permute(e, t) when is_list(e) or is_binary(e) do
    rotate(
      Shuffle.shuffle(
        for i <- 0..(Constants.validator_count() - 1) do
          div(Constants.core_count() * i, Constants.validator_count())
        end,
        e
      ),
      div(Time.epoch_phase(t), Constants.rotation_period())
    )
  end

  # Formula (11.21) v0.7.2
  def guarantors(n2_, time_stamp_, curr_validators_, offenders) do
    %__MODULE__{
      assigned_cores: permute(n2_, time_stamp_),
      validators: Validator.nullify_offenders(curr_validators_, offenders)
    }
  end

  # Formula (11.22) v0.7.2
  def prev_guarantors(n2_, n3_, t_, curr_validators_, prev_validators_, offenders) do
    {e, k} =
      if div(t_ - Constants.rotation_period(), Constants.epoch_length()) ==
           div(t_, Constants.epoch_length()) do
        {n2_, curr_validators_}
      else
        {n3_, prev_validators_}
      end

    guarantors(e, t_ - Constants.rotation_period(), k, offenders)
  end
end
