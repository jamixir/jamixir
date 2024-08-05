defmodule Authorization.Auth do
  @moduledoc """
  Authorization
  α -> authorization requirements
  Chapter 8 of the graypaper
  Support Ethereum and Polkadot data, it doesnt care, agnostch
  """

  # Authorizer returns a boolean
  @type authorizer :: (any() -> boolean())
  # uthorization can be any pieze of data
  @type authorization :: any()

  @type t :: %__MODULE__{
          work_package: list(),
          services: list(),
          authorization_requirements: list(AuthorizationRequirement.t()),
          authorization_queue: list(),
          authorizer: authorizer(),
          authorization: authorization()
        }

  defstruct [
    :work_package,
    :services,
    # α: Authorization requirement for work done on the core
    :authorization_requirements,
    # φ: Queue which fills the authorization requirement
    :authorization_queue,
    :authorizer,
    :authorization
  ]

  def authorize(_param1, _param2) do
    # TODO
    # Accept work package and output true or false
    # code
  end

  def add_to_pool(_param1, _param2) do
    # TODO
    # code
  end

  def add_to_queue(_param1, _param2) do
    # TODO
    # code
    IO.puts(:jam)
  end
end
