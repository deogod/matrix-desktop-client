use std::{
    fs, io,
    path::{Path, PathBuf},
};

// The SDK store lives in a fixed subdirectory so that removing it never touches
// anything else inside the directory received from Dart.
const STORE_DIR_NAME: &str = "store";

pub(crate) fn store_path(data_dir: &Path) -> PathBuf {
    data_dir.join(STORE_DIR_NAME)
}

pub(crate) fn store_exists(data_dir: &Path) -> bool {
    store_path(data_dir).is_dir()
}

pub(crate) fn reset_store(data_dir: &Path) -> io::Result<PathBuf> {
    remove_store(data_dir)?;
    let path = store_path(data_dir);
    fs::create_dir_all(&path)?;
    Ok(path)
}

pub(crate) fn remove_store(data_dir: &Path) -> io::Result<()> {
    match fs::remove_dir_all(store_path(data_dir)) {
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
        result => result,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn data_dir() -> tempfile::TempDir {
        tempfile::tempdir().expect("temporary directory")
    }

    #[test]
    fn reset_creates_an_empty_store() {
        let dir = data_dir();
        let old_file = store_path(dir.path()).join("old.sqlite3");
        fs::create_dir_all(store_path(dir.path())).expect("create store");
        fs::write(&old_file, b"old").expect("write old file");

        let path = reset_store(dir.path()).expect("reset store");

        assert_eq!(path, store_path(dir.path()));
        assert!(path.is_dir());
        assert!(!old_file.exists());
    }

    #[test]
    fn reset_keeps_other_files_in_data_dir() {
        let dir = data_dir();
        let sibling = dir.path().join("other.txt");
        fs::write(&sibling, b"keep").expect("write sibling");

        reset_store(dir.path()).expect("reset store");

        assert!(sibling.exists());
    }

    #[test]
    fn remove_deletes_only_the_store() {
        let dir = data_dir();
        let sibling = dir.path().join("other.txt");
        fs::write(&sibling, b"keep").expect("write sibling");
        reset_store(dir.path()).expect("reset store");

        remove_store(dir.path()).expect("remove store");

        assert!(!store_exists(dir.path()));
        assert!(sibling.exists());
    }

    #[test]
    fn remove_succeeds_when_store_is_missing() {
        let dir = data_dir();
        assert!(remove_store(dir.path()).is_ok());
    }
}
