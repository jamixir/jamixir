rustler::atoms! {
    ok,
    error,
    panic,

    // memory errors
    out_of_bounds,
    memory_already_present,
    memory_empty,
    memory_in_use,
    mutex_poisoned,
    fault,
    memory_not_available,

    // VM errors
    no_vm_context,
    send_failed,
    invalid_instruction,
    invalid_access,
    stack_overflow,
    stack_underflow,
    heap_overflow,

    // VM results
    halt,
    out_of_gas,
    waiting,
    ecall,
}
