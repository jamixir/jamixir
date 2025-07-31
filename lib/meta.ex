defmodule Jamixir.Meta do
  @app_version Mix.Project.config()[:app_version]
  @jam_version Mix.Project.config()[:jam_version]
  @name Mix.Project.config()[:name]

  def app_version, do: @app_version
  def jam_version, do: @jam_version
  def name, do: @name
end
