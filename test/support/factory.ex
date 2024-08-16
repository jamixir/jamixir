# test/support/factory.ex
defmodule Jamixir.Factory do
  use ExMachina

  alias Block.Extrinsic.Guarantee.{WorkResult, AvailabilitySpecification, WorkReport}

  def work_report_factory do
    %WorkReport{
      specification: build(:availability),
      refinement_context: %RefinementContext{},
      core_index: 1
    }

    %WorkReport{
       specification: build(:availability),
       refinement_context: build(:refinement_context),
       core_index: 1,
       authorizer_hash: <<2::256>>,
       output: <<3>>,
       work_results: build_list(2, :work_result)
     }
  end

  def availability_factory do
    %Block.Extrinsic.Availability{
      work_package_hash: <<1::256>>,
      work_bundle_length: 2,
      erasure_root: <<3::256>>,
      segment_root: <<4::256>>
    }
  end

  def refinement_context_factory do
    %RefinementContext{
       anchor: <<1::256>>,
       posterior_state_root: <<2::256>>,
       posterior_beefy_root: <<3::256>>,
       lookup_anchor: <<4::256>>,
       timeslot: 5,
       prerequisite: <<6::256>>
     }
  end

  def work_result_factory do
    %WorkResult{
       service_index: 0,
       code_hash: <<1::256>>,
       payload_hash: <<2::256>>,
       gas_prioritization_ratio: 3,
       output_or_error: {:ok, <<4>>}
     }
  end
end
