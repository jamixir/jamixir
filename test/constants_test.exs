defmodule ConstantsTest do
  use ExUnit.Case

  test "check constants correct values" do
    assert Constants.audit_footprint() == 4488
    assert Constants.max_work_package_size() == 13_791_360
  end
end
