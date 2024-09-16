defmodule Block.Extrinsic.Guarantor do
  @moduledoc """
  # Formula (133) v0.3.4 - section 11.3
  Every block, each core has three validators uniquely assigned to guarantee workreports for it.
  This is borne out with V = 1, 023 validators and C = 341 cores, since V/C = 3.
  The core index assigned to each of the validators, as well as the validators’ Ed25519 keys
  are denoted by G:
  """
  alias System.State.RotateKeys
  alias Util.Time

  @type t :: %__MODULE__{
          assigned_cores: list(non_neg_integer()),
          validator_keys: list(Types.ed25519_key())
        }

  defstruct assigned_cores: [],
            # d
            validator_keys: []

  # Formula (134) v0.3.4
  def rotate(list, n) do
    list |> Enum.map(&rem(&1 + n, Constants.core_count()))
  end

  # Formula (135) v0.3.4
  def permute(e, t) when is_list(e) or is_binary(e) do
    1..Constants.validator_count()
    |> Enum.map(&div(Constants.core_count() * &1, Constants.validator_count()))
    |> Shuffle.shuffle(e)
    |> rotate(div(Time.epoch_phase(t), Constants.rotation_period()))
  end

  # Formula (136) v0.3.4
  def guarantor_assignements(
        post_n2,
        post_timestamp,
        post_kurrent_validators,
        offenders
      ) do
    {permute(post_n2, post_timestamp),
     RotateKeys.nullify_offenders(post_kurrent_validators, offenders)}
  end

  def previous_guarantor_assignements(
        post_n2,
        post_n3,
        post_timestamp,
        post_kurrent_validators,
        post_previous_validators,
        offenders
      ) do
    {e, k} =
      if div(post_timestamp - Constants.rotation_period(), Time.epoch_duration()) ==
           div(post_timestamp, Time.epoch_duration()) do
        {post_n2, post_kurrent_validators}
      else
        {post_n3, post_previous_validators}
      end

    guarantor_assignements(e, post_timestamp - Constants.rotation_period(), k, offenders)
  end
end
