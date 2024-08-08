defmodule System.State.Judgements do
  @moduledoc """
  Represents the state and operations related to judgements in the disputes system.
  """
  alias Types

  @type t :: %__MODULE__{
          good: MapSet.t(Types.hash()),
          bad: MapSet.t(Types.hash()),
          wonky: MapSet.t(Types.hash()),
          punish: MapSet.t(Types.ed25519_key())
        }

  defstruct good: MapSet.new(),
            bad: MapSet.new(),
            wonky: MapSet.new(),
            punish: MapSet.new()

  @type verdict :: :good | :bad | :wonky

  @doc """
  Adds a judgement to the appropriate set based on the verdict type.
  """
  def add_verdict(%__MODULE__{} = judgement_state, report_hash, :good) do
    update_in(judgement_state.good, &MapSet.put(&1, report_hash))
  end

  def add_verdict(%__MODULE__{} = judgement_state, report_hash, :bad) do
    update_in(judgement_state.bad, &MapSet.put(&1, report_hash))
  end

  def add_verdict(%__MODULE__{} = judgement_state, report_hash, :wonky) do
    update_in(judgement_state.wonky, &MapSet.put(&1, report_hash))
  end

  @doc """
  Adds an offender's key to the punish set.
  """
  def add_offender(%__MODULE__{} = judgement_state, offender_key) do
    update_in(judgement_state.punish, &MapSet.put(&1, offender_key))
  end
end
