defmodule Block.Extrinsic.AvailabilitySpecification do
  @type t :: %__MODULE__{
          # h: hash of the work-package
          work_package_hash: Types.hash(),
          # l: auditable work bundle length
          work_bundle_length: Types.max_age_timeslot_lookup_anchor(),
          # u: erasure-root
          erasure_root: Types.hash(),
          # e: segment-root
          segment_root: Types.hash()
        }

  # Formula (122) v0.3.4
  # h
  defstruct work_package_hash: <<0::256>>,
            # l
            work_bundle_length: 0,
            # u
            erasure_root: <<0::256>>,
            # e
            segment_root: <<0::256>>

  defimpl Encodable do
    # Formula (284) v0.3.4
    def encode(%Block.Extrinsic.AvailabilitySpecification{} = availability) do
      Codec.Encoder.encode(availability.work_package_hash) <>
        Codec.Encoder.encode_le(availability.work_bundle_length, 4) <>
        Codec.Encoder.encode({availability.erasure_root, availability.segment_root})
    end
  end
end
