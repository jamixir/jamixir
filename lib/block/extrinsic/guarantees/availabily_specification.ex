defmodule Block.Extrinsic.Guarantee.AvailabilitySpecification do
  @moduledoc """
  A module representing the availability specification for a work-package.
  Includes the work-package's hash, an auditable work bundle length, an erasure-root, and a segment-root.
  """

  @type t :: %__MODULE__{
          # h: hash of the work-package
          work_package_hash: Types.hash(),
          # l: auditable work bundle length
          bundle_length: non_neg_integer(),
          # u: erasure-root
          erasure_root: Types.hash(),
          # e: segment-root
          segment_root: Types.hash()
        }

  defstruct work_package_hash: <<0::256>>,
            bundle_length: 0,
            erasure_root: <<0::256>>,
            segment_root: <<0::256>>
end
