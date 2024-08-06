use std::env;

fn main() {
    // Get the existing DYLD_LIBRARY_PATH, if any.
    let existing_paths = env::var("DYLD_LIBRARY_PATH").unwrap_or_else(|_| "".to_string());

    // Construct the new path, appending to the existing one.
    let new_path = format!(
        "/usr/local/Cellar/erlang/26.2.5/lib/erlang/lib:{}",
        existing_paths
    );

    // Set the DYLD_LIBRARY_PATH
    println!("cargo:rustc-env=DYLD_LIBRARY_PATH={}", new_path);

    println!("cargo:rustc-link-search=native=/usr/local/Cellar/erlang/26.2.5/lib/erlang/lib");
    println!("cargo:rustc-link-lib=dylib=erl_interface");
    println!("cargo:rustc-link-lib=dylib=ei");
}
