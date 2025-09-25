use pvm_core::VmContext;
use std::collections::HashMap;
use std::sync::{
    atomic::{AtomicU64, Ordering},
    Arc, LazyLock, Mutex,
};

static NEXT_CTX_ID: AtomicU64 = AtomicU64::new(1);

static VM_CONTEXTS: LazyLock<Mutex<HashMap<u64, Arc<VmContext>>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

pub fn generate_context_token() -> u64 {
    NEXT_CTX_ID.fetch_add(1, Ordering::Relaxed)
}

pub fn store_context(token: u64, context: Arc<VmContext>) {
    let mut contexts = VM_CONTEXTS.lock().unwrap();
    contexts.insert(token, context);
}

pub fn get_context(token: u64) -> Option<Arc<VmContext>> {
    let contexts = VM_CONTEXTS.lock().unwrap();
    contexts.get(&token).cloned()
}

pub fn remove_context(token: u64) {
    let mut contexts = VM_CONTEXTS.lock().unwrap();
    contexts.remove(&token);
}
