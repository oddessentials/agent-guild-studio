use std::{env, fs, path::PathBuf};

fn main() {
    println!("cargo:rerun-if-env-changed=COMPANION_CHARACTERS_RS");
    let source = env::var("COMPANION_CHARACTERS_RS").expect("Set COMPANION_CHARACTERS_RS to Grove Companion's src-tauri/src/characters.rs.");
    println!("cargo:rerun-if-changed={source}");
    let text = fs::read_to_string(&source).unwrap_or_else(|err| panic!("{source}: {err}"));
    let items: String = text.lines().filter(|line| !line.starts_with("//!")).map(|line| format!("{line}\n")).collect();
    fs::write(PathBuf::from(env::var("OUT_DIR").unwrap()).join("characters.rs"), items).unwrap();
}
