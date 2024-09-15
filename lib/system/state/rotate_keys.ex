defmodule System.State.RotateKeys do
  alias Util.Time
  alias Block.Header

  alias System.State.{
    Validator,
    Judgements,
    Safrole
  }

  @doc """
  Formula (58) v0.3.4
  Rotate keys according to the GP specification.
  returns tuple :{new_pending, new_current, new_prev, new_epoch_root}
  """

  @spec rotate_keys(
          Header.t(),
          integer(),
          list(Validator.t()),
          list(Validator.t()),
          list(Validator.t()),
          Safrole.t(),
          Judgements.t()
        ) ::
          {:ok,
           {list(Validator.t()), list(Validator.t()), list(Validator.t()),
            Types.bandersnatch_ring_root()}}
          | {:error, String.t()}

  def rotate_keys(
        %Header{timeslot: new_timeslot},
        timeslot,
        prev_validators,
        curr_validators,
        next_validators,
        %Safrole{pending: pending, epoch_root: epoch_root},
        %Judgements{punish: offenders}
      ) do
    case Time.new_epoch?(timeslot, new_timeslot) do
      {:ok, true} ->
        # Formula (58) -  new epoch - rotate keys
        # {γ_k', κ', λ', γ_z'} = {Φ(ι), γ_k, κ, z}

        # γ_k' = Φ(ι) (next -> pending)
        new_pending = nullify_offenders(next_validators, offenders)

        # κ' = γ_k (pending -> current)
        new_current = pending

        # λ' = κ (current -> prev)
        new_prev = curr_validators

        # γ_z' = z, z = O([kb ∣ k <- γk ])
        new_epoch_root = RingVrf.create_commitment(Enum.map(new_pending, & &1.bandersnatch))

        {:ok, {new_pending, new_current, new_prev, new_epoch_root}}

      {:ok, false} ->
        # Formula (58) -  same epoch - no rotation
        # {γ_k', κ', λ', γ_z'} = {γ_k, κ, λ, γ_z}
        {:ok, {pending, curr_validators, prev_validators, epoch_root}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Formula (59) v0.3.4
  @spec nullify_offenders(
          list(Validator.t()),
          MapSet.t(Types.ed25519_key())
        ) :: list(Validator.t())
  def nullify_offenders([], _), do: []

  def nullify_offenders(
        [%System.State.Validator{} | _] = next_validators,
        offenders
      ) do
    Enum.map(next_validators, fn %Validator{} = validator ->
      if MapSet.member?(offenders, validator.ed25519) do
        %Validator{
          bandersnatch: <<0::size(bit_size(validator.bandersnatch))>>,
          ed25519: <<0::size(bit_size(validator.ed25519))>>,
          bls: <<0::size(bit_size(validator.bls))>>,
          metadata: <<0::size(bit_size(validator.metadata))>>
        }
      else
        validator
      end
    end)
  end
end
