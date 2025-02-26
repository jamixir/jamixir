defmodule Services.Fibonacci do
  import PVM.Utils.AddInstruction
  import PVM.Instructions

  def program do
    # Base fibonacci program
    base = [0,0,33,
      51,8,1,51,9,1,40,3,0,149,119,255,81,7,12,100,
      138,200,152,8,100,169,40,243,100,135,51,8,51,9,1,50,0,
      73,147,82,213,0]

    # Add instruction to set register 7 to 9 at the start
    insert_instruction(base, 2, [to_byte(:load_imm), 7, 9], [1,0,0])
  end
end
