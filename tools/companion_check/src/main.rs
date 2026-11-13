use std::{env, fs, path::PathBuf, process::ExitCode};

#[allow(dead_code)]
mod characters {
    include!(concat!(env!("OUT_DIR"), "/characters.rs"));
}

fn kind(folder: &PathBuf) -> Option<String> {
    let manifest: serde_json::Value = serde_json::from_slice(&fs::read(folder.join("piece.json")).ok()?).ok()?;
    manifest.get("kind")?.as_str().map(str::to_string)
}

fn main() -> ExitCode {
    let Some(pieces) = env::args().nth(1) else {
        eprintln!("Usage: companion_check <folder of piece folders>");
        return ExitCode::FAILURE;
    };
    let mut folders: Vec<PathBuf> = fs::read_dir(&pieces).expect("the pieces folder can't be read").flatten().map(|entry| entry.path()).filter(|path| path.is_dir()).collect();
    folders.sort();
    let scratch = env::temp_dir().join(format!("studio-companion-check-{}", characters::new_id()));
    let (mut checked, mut refused) = (0, 0);
    for folder in folders {
        if kind(&folder).as_deref() != Some("character") {
            continue;
        }
        checked += 1;
        let name = folder.file_name().unwrap().to_string_lossy().into_owned();
        let token = characters::new_id();
        match characters::stage(&scratch, &folder, &token) {
            Ok(title) => println!("ok       {name} ({title})"),
            Err(reason) => {
                refused += 1;
                println!("REFUSED  {name}: {reason}");
            }
        }
        characters::discard(&scratch, &token);
    }
    let _ = fs::remove_dir_all(&scratch);
    println!("{} of {checked} characters pass Grove Companion's check", checked - refused);
    if checked == 0 || refused > 0 { ExitCode::FAILURE } else { ExitCode::SUCCESS }
}
