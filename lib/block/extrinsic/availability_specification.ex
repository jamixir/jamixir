defmodule Block.Extrinsic.AvailabilitySpecification do
  alias Util.Hash

  @type t :: %__MODULE__{
          # h: hash of the work-package
          work_package_hash: Types.hash(),
          # l: auditable work bundle length
          len: Types.max_age_timeslot_lookup_anchor(),
          # u: erasure-root
          erasure_root: Types.hash(),
          # e: segment-root
          exports_root: Types.hash()
        }

  # Formula (121) v0.4.1
  # h
  defstruct work_package_hash: Hash.zero(),
            # l
            len: 0,
            # u
            erasure_root: Hash.zero(),
            # e
            exports_root: Hash.zero()

  defimpl Encodable do
    # Formula (305) v0.4.1
    def encode(%Block.Extrinsic.AvailabilitySpecification{} = availability) do
      Codec.Encoder.encode(availability.work_package_hash) <>
        Codec.Encoder.encode_le(availability.len, 4) <>
        Codec.Encoder.encode({availability.erasure_root, availability.exports_root})
    end
  end

  use JsonDecoder

  def json_mapping, do: %{work_package_hash: :hash}
end
