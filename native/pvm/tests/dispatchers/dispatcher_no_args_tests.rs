#[cfg(test)]
mod tests {
    use pvm::vm::dispatchers::no_args::dispatch_no_args;
    use pvm::vm::instructions::opcodes::*;
    use pvm::vm::InstructionResult;

    #[test]
    fn test_all_no_args_opcodes() {
        assert_eq!(dispatch_no_args(TRAP), InstructionResult::Panic);
        assert_eq!(dispatch_no_args(FALLTHROUGH), InstructionResult::Continue);
        assert_eq!(dispatch_no_args(ECALLI), InstructionResult::Panic);
    }
}
