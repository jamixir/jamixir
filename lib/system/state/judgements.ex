defmodule System.State.Judgements do
  @moduledoc """
  Represents the state and operations related to judgements in the disputes system.
  """
  alias Block.Header
  alias System.State.Judgements

  @type t :: %__MODULE__{
          good: MapSet.t(Types.hash()),
          bad: MapSet.t(Types.hash()),
          wonky: MapSet.t(Types.hash()),
          punish: MapSet.t(Types.ed25519_key())
        }

  # Formula (97) v0.3.4
  defstruct good: MapSet.new(),
            bad: MapSet.new(),
            wonky: MapSet.new(),
            punish: MapSet.new()

  @type verdict :: :good | :bad | :wonky

  def posterior_judgements(%Header{timeslot: ts}, disputes, state) do
    case Block.Extrinsic.Disputes.validate_disputes(disputes, state, ts) do
      {:ok, %{good_set: good_set, bad_set: bad_set, wonky_set: wonky_set}} ->
        new_judgements = %Judgements{
          state.judgements
          | good: MapSet.union(state.judgements.good, good_set),
            bad: MapSet.union(state.judgements.bad, bad_set),
            wonky: MapSet.union(state.judgements.wonky, wonky_set)
        }

        new_punish_set = update_punish_set(new_judgements, disputes.culprits ++ disputes.faults)

        %Judgements{
          new_judgements
          | punish: new_punish_set
        }

      {:error, reason} ->
        IO.puts("Invalid Disputed Extrinsic: #{reason}")
        state.judgements
    end
  end

  defp update_punish_set(state_judgements, offenses) do
    Enum.reduce(offenses, state_judgements.punish, fn offense, acc ->
      MapSet.put(acc, offense.validator_key)
    end)
  end

  defimpl Encodable do
    alias Codec.VariableSize
    # E(↕[x^x ∈ ψg],↕[x^x ∈ ψb],↕[x^x ∈ ψw],↕[x^x ∈ ψo])
    def encode(%Judgements{} = j) do
      Codec.Encoder.encode({
        VariableSize.new(j.good),
        VariableSize.new(j.bad),
        VariableSize.new(j.wonky),
        VariableSize.new(j.punish)
      })
    end
  end
end
