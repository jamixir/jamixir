defmodule Jamixir.Meta do
  def app_version, do: Mix.Project.config()[:app_version]
  def jam_version, do: Mix.Project.config()[:jam_version]
  def name, do: Mix.Project.config()[:name]
end
