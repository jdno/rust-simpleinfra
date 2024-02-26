use std::path::{Path, PathBuf};

use anyhow::Error;
use clap::Parser;
use walkdir::WalkDir;

/// Clean up unused projects
///
/// This CLI finds all projects that users have checked out on the dev-desktops and deletes
/// temporary files if the project has not been modified in a certain number of days.
///
/// Specifically, the CLI will look for checkouts of `rust-lang/rust` and delete the `build`
/// directory. And it will find unused crates and delete the `target` directory.
#[derive(Parser)]
struct Cli {
    /// The root directory to search for projects
    #[arg(short, long = "root-directory", default_value = "/home")]
    root_directory: PathBuf,

    /// The maximum age of a project in days
    ///
    /// The CLI will only clean projects that have not been updated in the last `max-age` days.
    #[arg(short, long = "max-age", default_value_t = 60)]
    max_age: u32,

    /// Perform a dry run without cleaning any files
    ///
    /// When this flag is set, the CLI will only print the directories that would be removed.
    #[arg(long = "dry-run", default_value_t = false)]
    dry_run: bool,
}

fn main() -> Result<(), Error> {
    let cli = Cli::parse();

    let all_artifact_directories = find_artifact_directories(&cli.root_directory)?;

    Ok(())
}

fn find_artifact_directories(root_directory: &Path) -> Result<Vec<PathBuf>, Error> {
    WalkDir::new(root_directory)
        .into_iter()
        .filter_entry(|entry| is_rust_checkout(entry.path()) || is_cargo_crate(entry.path()))
        .map(|entry| entry.map(|e| e.into_path()).map_err(|e| e.into()))
        .collect()
}

fn is_rust_checkout(path: &Path) -> bool {
    path.join("x.py").is_file() && path.join("build").is_dir()
}

fn is_cargo_crate(path: &Path) -> bool {
    path.join("Cargo.toml").is_file() && path.join("target").is_dir()
}

#[cfg(test)]
mod tests {
    use std::fs::{create_dir, create_dir_all, File};

    use tempfile::TempDir;

    use super::*;

    fn cargo_crate(parent: Option<&Path>) -> TempDir {
        let krate = parent
            .map(TempDir::new_in)
            .unwrap_or_else(TempDir::new)
            .expect("failed to create temporary crate");

        File::create(krate.path().join("Cargo.toml")).expect("failed to create fake Cargo.toml");
        create_dir(krate.path().join("target")).expect("failed to create fake target directory");

        krate
    }

    fn rust_checkout(parent: Option<&Path>) -> TempDir {
        let checkout = parent
            .map(TempDir::new_in)
            .unwrap_or_else(TempDir::new)
            .expect("failed to create temporary checkout");

        File::create(checkout.path().join("x.py")).expect("failed to create fake x.py");
        create_dir(checkout.path().join("build")).expect("failed to create fake build directory");

        checkout
    }

    #[test]
    fn find_artifact_directories_in_root() {
        let rust_checkout = rust_checkout(None);

        let artifact_directories = find_artifact_directories(rust_checkout.path())
            .expect("failed to find artifact directories");

        assert_eq!(artifact_directories, vec![rust_checkout.path()]);
    }

    #[test]
    fn find_artifact_directories_recursively() {
        let root_directory = TempDir::new().expect("failed to create temporary directory");

        let rust_checkout = rust_checkout(Some(root_directory.path()));
        let cargo_crate = cargo_crate(Some(root_directory.path()));

        let other = root_directory.path().join("other").join("build");
        create_dir_all(other).expect("failed to create fake directory");

        let artifact_directories = find_artifact_directories(root_directory.path())
            .expect("failed to find artifact directories");

        assert_eq!(
            artifact_directories,
            vec![rust_checkout.path(), cargo_crate.path()]
        );
    }

    #[test]
    fn is_rust_checkout_returns_true_for_rust_checkout() {
        let checkout = rust_checkout(None);

        assert!(is_rust_checkout(checkout.path()));
    }

    #[test]
    fn is_rust_checkout_returns_false_for_cargo_crate() {
        let root_directory = cargo_crate(None);

        assert!(!is_rust_checkout(root_directory.path()));
    }

    #[test]
    fn is_rust_checkout_returns_false_for_random_directory() {
        let root_directory = TempDir::new().expect("failed to create temporary directory");

        // Create a fake build directory but no x.py
        create_dir(root_directory.path().join("build"))
            .expect("failed to create fake build directory");

        assert!(!is_rust_checkout(root_directory.path()));
    }

    #[test]
    fn is_cargo_crate_returns_true_for_cargo_crate() {
        let root_directory = cargo_crate(None);

        assert!(is_cargo_crate(root_directory.path()));
    }

    #[test]
    fn is_cargo_crate_returns_false_for_rust_checkout() {
        let root_directory = rust_checkout(None);

        assert!(!is_cargo_crate(root_directory.path()));
    }

    #[test]
    fn is_cargo_crate_returns_false_for_random_directory() {
        let root_directory = TempDir::new().expect("failed to create temporary directory");

        // Create Cargo.toml but no target directory
        File::create(root_directory.path().join("Cargo.toml"))
            .expect("failed to create fake Cargo.toml");

        assert!(!is_cargo_crate(root_directory.path()));
    }
}
