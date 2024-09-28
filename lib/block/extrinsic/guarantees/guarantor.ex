defmodule Block.Extrinsic.Guarantor do
  @moduledoc """
  # Formula (133) v0.3.4 - section 11.3
  Every block, each core has three validators uniquely assigned to guarantee workreports for it.
  This is borne out with V = 1, 023 validators and C = 341 cores, since V/C = 3.
  The core index assigned to each of the validators, as well as the validators’ Ed25519 keys
  are denoted by G:
  """
  alias System.State.Validator
  alias Util.Time

  @type t :: %__MODULE__{
          assigned_cores: list(non_neg_integer()),
          validators: list(Types.ed25519_key())
        }

  defstruct assigned_cores: [],
            # d
            validators: []

  # Formula (134) v0.3.4
  def rotate(list, n) do
    list |> Enum.map(&rem(&1 + n, Constants.core_count()))
  end

  # Formula (135) v0.3.4
  def permute(e, t) when is_list(e) or is_binary(e) do
    0..(Constants.validator_count() - 1)
    |> Enum.map(&div(Constants.core_count() * &1, Constants.validator_count()))
    |> Shuffle.shuffle(e)
    |> rotate(div(Time.epoch_phase(t), Constants.rotation_period()))
  end

  # Formula (136) v0.3.4
  def guarantors(n2_, time_stamp_, curr_validators_, offenders) do
    %__MODULE__{
      assigned_cores: permute(n2_, time_stamp_),
      validators: Validator.nullify_offenders(curr_validators_, offenders)
    }
  end

  # Formula (137) v0.3.4
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
