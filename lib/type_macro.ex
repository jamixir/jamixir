defmodule TypeMacro do
  defmacro def_bin_type(type_name, size_name) do
    quote bind_quoted: [type_name: type_name, size_name: size_name] do
      size_func = String.to_existing_atom(Atom.to_string(size_name))
      size_value = apply(Sizes, size_func, [])

      unless is_integer(size_value) do
        raise ArgumentError, "Size function must return an integer, got: #{inspect(size_value)}"
      end

      @type unquote(type_name)() :: <<_::unquote(size_value * 8)>>
    end
  end
end
