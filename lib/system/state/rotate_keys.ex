defmodule System.State.RotateKeys do
  alias Util.{Time, Crypto}
  alias Block.Header

  alias System.State.{
    Validator,
    Judgements,
    Safrole
  }

  @doc """
  Equation (58)
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
          {list(Validator.t()), list(Validator.t()), list(Validator.t()),
           Types.bandersnatch_ring_root()}

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
        # Equation (58) -  new epoch - rotate keys
        # {γ_k', κ', λ', γ_z'} = {Φ(ι), γ_k, κ, z}

        # next -> penfing
        # γ_k' = Φ(ι)
        new_pending = nullify_offenders(next_validators, offenders)
        # penfing -> current
        # κ' = γ_k
        new_current = pending
        # current -> prev
        # λ' = κ
        new_prev = curr_validators

        # γ_z' = z, z = O([kb ∣ k <- γk ])
        new_epoch_root = Crypto.bandersnatch_ring_root(Enum.map(new_pending, & &1.bandersnatch))

        {new_pending, new_current, new_prev, new_epoch_root}

      {:ok, false} ->
        # Equation (59) -  same epoch - no rotation
        # {γ_k', κ', λ', γ_z'} = {γ_k, κ, λ, γ_z}
        {pending, curr_validators, prev_validators, epoch_root}

      {:error, reason} ->
        raise "Error determining new epoch: #{reason}"
    end
  end

  # Equation (59)
  @spec nullify_offenders(
          list(Validator.t()),
          MapSet.t(Types.ed25519_key())
        ) :: list(Validator.t())
  def nullify_offenders([], _offenders), do: []

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
