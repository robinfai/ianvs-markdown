fn main() {
    println!("cargo:rerun-if-env-changed=MERMAN_LIB_DIR");
    let directory = std::env::var("MERMAN_LIB_DIR").expect("MERMAN_LIB_DIR is required");
    println!("cargo:rustc-link-search=native={directory}");
    println!("cargo:rustc-link-lib=dylib=merman_ffi");
    // Used by Rust test executables; the extension supplies its own bundle rpath.
    println!("cargo:rustc-link-arg=-Wl,-rpath,{directory}");
}
