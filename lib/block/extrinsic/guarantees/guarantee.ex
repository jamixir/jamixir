defmodule Block.Extrinsic.Guarantee do
  @moduledoc """
  Work report guarantee.
  11.4
  Formula (138) v0.3.4
  """
  alias Block.Extrinsic.Guarantee.WorkReport
  alias Codec.Encoder
  alias SigningContexts
  alias Util.{Collections, Crypto, Hash}

  use SelectiveMock

  # {validator_index, ed25519 signature}
  @type credential :: {Types.validator_index(), Types.ed25519_signature()}

  @type t :: %__MODULE__{
          # w
          work_report: WorkReport.t(),
          # t
          timeslot: non_neg_integer(),
          # a
          credential: list(credential())
        }

  defstruct work_report: %WorkReport{},
            timeslot: 0,
            credential: [{0, <<0::512>>}]

  # Formula (138) v0.3.4
  # Formula (139) v0.3.4
  # Formula (140) v0.3.4
  @spec validate(list(t()), list(System.State.Validator.t())) :: :ok | {:error, String.t()}
  def validate(guarantees, curr_validators) do
    with :ok <- Collections.validate_unique_and_ordered(guarantees, & &1.work_report.core_index),
         true <-
           Enum.all?(guarantees, fn %__MODULE__{credential: cred} ->
             length(cred) in [2, 3]
           end),
         true <-
           Collections.all_ok?(guarantees, fn %__MODULE__{credential: cred} ->
             Collections.validate_unique_and_ordered(cred, &elem(&1, 0))
           end),
         :ok <- validate_signatures(guarantees, curr_validators) do
      :ok
    else
      {:error, :duplicates} -> {:error, "Duplicate core_index found in guarantees"}
      {:error, :not_in_order} -> {:error, "Guarantees not ordered by core_index"}
      false -> {:error, "Invalid credentials in one or more guarantees"}
      {:error, reason} -> {:error, reason}
    end
  end

  mockable validate_signatures(guarantees, curr_validators) do
    Enum.all?(guarantees, fn guarantee ->
      message =
        SigningContexts.jam_guarantee() <> Hash.default(Encoder.encode(guarantee.work_report))

      Enum.all?(guarantee.credential, fn {validator_index, signature} ->
        validator = Enum.at(curr_validators, validator_index)
        Crypto.valid_signature?(signature, message, validator.ed25519)
      end)
    end)
    |> if do
      :ok
    else
      {:error, "Invalid signature in one or more guarantees"}
    end
  end

  def mock(:validate_signatures, _), do: :ok

  def reporters_set(_guarantees) do
    # TODO
    []
  end

  defimpl Encodable do
    alias Block.Extrinsic.Guarantee

    def encode(%Guarantee{}) do
      # TODO
      <<0>>
    end
  end
end
