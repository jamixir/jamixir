defmodule PVM.Constants do
  # Apendix B.1
  defmacro __using__(_) do
    quote do
      @none 4_294_967_296 - 1
      @what 4_294_967_296 - 2
      @oob 4_294_967_296 - 3
      @who 4_294_967_296 - 4
      @full 4_294_967_296 - 5
      @core 4_294_967_296 - 6
      @cash 4_294_967_296 - 7
      @low 4_294_967_296 - 8
      @high 4_294_967_296 - 9
      @huh 4_294_967_296 - 10
      @ok 0

      @gas 0
    end
  end
end
