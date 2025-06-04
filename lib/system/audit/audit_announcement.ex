defmodule System.Audit.AuditAnnouncement do
  @type t :: %__MODULE__{
          tranche: non_neg_integer(),
          announcements: list({non_neg_integer(), Types.hash()}),
          header_hash: Types.hash(),
          signature: Types.signature(),
          evidence: Types.bandersnatch_signature() | list(NoShow.t())
        }

  defstruct tranche: 0,
            announcements: [],
            header_hash: nil,
            signature: nil,
            evidence: nil
end
