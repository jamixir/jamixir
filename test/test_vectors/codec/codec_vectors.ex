defmodule CodecVectors do
  alias Block.Extrinsic
  alias Block.Extrinsic.{Disputes, Guarantee, TicketProof}
  alias Block.Extrinsic.{Assurance, Guarantee.WorkResult, Preimage, WorkItem, WorkPackage}
  alias Block.Extrinsic.Guarantee.WorkReport
  alias Block.Header

  @tests [
    {"assurances_extrinsic", Assurance},
    {"block", Block},
    {"disputes_extrinsic", Disputes},
    {"extrinsic", Extrinsic},
    {"guarantees_extrinsic", Guarantee},
    {"header_0", Header},
    {"header_1", Header},
    {"preimages_extrinsic", Preimage},
    {"refine_context", RefinementContext},
    {"tickets_extrinsic", TicketProof},
    {"work_item", WorkItem},
    {"work_package", WorkPackage},
    {"work_report", WorkReport},
    {"work_result_0", WorkResult},
    {"work_result_1", WorkResult}
  ]

  def tests, do: @tests

  def files_to_test do
    for({file_name, _} <- @tests, do: file_name)
  end
end
