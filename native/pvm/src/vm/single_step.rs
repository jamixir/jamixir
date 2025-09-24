use crate::core::consts::GAS_COST;
use crate::vm::types::StepResult;
use crate::vm::Vm;

impl Vm {
    pub fn single_step_run(&mut self) -> StepResult {
        if self.state.pc >= self.context.program.len() {
            return StepResult::Panic;
        }

        let opcode = self.context.program[self.state.pc];
        let prev_counter = self.state.pc;

        let exit_reason = self.execute_instruction(opcode);

        self.state.consume_gas(GAS_COST);

        let next_counter = self.next_counter(&exit_reason, prev_counter);

        let exit_reason_ = exit_reason.into();
        self.state.pc = next_counter;

        exit_reason_
    }
}
