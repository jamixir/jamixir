defmodule StateConfig do
  alias System.State.ValidatorStatistics

  @validator_statistics Application.compile_env(
                          :jamixir,
                          :validator_statistics,
                          ValidatorStatistics
                        )
  def validator_statistics, do: @validator_statistics
end
