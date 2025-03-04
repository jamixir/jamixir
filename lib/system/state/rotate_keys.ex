defmodule System.State.RotateKeys do
  alias System.State
  alias Block.Header
  alias System.State.{Judgements, Safrole, Validator}
  alias Util.Time

  @doc """
  Formula (6.13) v0.6.2

  returns tuple :{pending_, current_, prev_, epoch_root_}
  """

  @spec rotate_keys(
          Header.t(),
          State.t(),
          Judgements.t()
        ) ::
          {list(Validator.t()), list(Validator.t()), list(Validator.t()),
           Types.bandersnatch_ring_root()}

  def rotate_keys(
        %Header{timeslot: timeslot_},
        %State{
          timeslot: timeslot,
          prev_validators: prev_validators,
          curr_validators: curr_validators,
          next_validators: next_validators,
          safrole: %Safrole{pending: pending, epoch_root: epoch_root}
        },
        %Judgements{offenders: offenders}
      ) do
    if Time.new_epoch?(timeslot, timeslot_) do
      # Formula (6.13) v0.6.0 -  new epoch - rotate keys
      # {γ_k', κ', λ', γ_z'} = {Φ(ι), γ_k, κ, z}

      # γ_k' = Φ(ι) (next -> pending)
      pending_ = Validator.nullify_offenders(next_validators, offenders)
      # κ' = γ_k (pending -> current)
      current_ = pending
      # λ' = κ (current -> prev)
      prev_ = curr_validators
      # γ_z' = z, z = O([kb ∣ k <- γk ])
      epoch_root_ = RingVrf.create_commitment(for p <- pending_, do: p.bandersnatch)

      {pending_, current_, prev_, epoch_root_}
    else
      # Formula (6.13) v0.6.0 -  same epoch - no rotation
      # {γ_k', κ', λ', γ_z'} = {γ_k, κ, λ, γ_z}
      {pending, curr_validators, prev_validators, epoch_root}
    end
  end
end
