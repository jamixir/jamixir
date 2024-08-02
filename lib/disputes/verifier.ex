defmodule Disputes.Verifier do

  @moduledoc """
  Verifier module for disputes.
  """
  alias Disputes.Judgement
  alias System.State.Validator
  alias Types
  alias Util.Crypto


  @doc """
  Determines if a signature in a judgement is valid for the given work report hash.
  """
  @spec verify_judgement_signature?(Judgement.t(), Types.hash(), list(Validator.t())) :: boolean()
  def verify_judgement_signature?(
         %Judgement{signature: signature, validator_index: index},
         work_report_hash,
         validators
       ) do
    case Enum.at(validators, index) do
      %Validator{ed25519: public_key} ->
        Crypto.verify_signature(signature, work_report_hash, public_key)

      _ ->
        false
    end
  end

end
