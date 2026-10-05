use std::{
    fs, io,
    path::{Path, PathBuf},
};

// Every store lives under a fixed subdirectory so that removing stores never touches
// anything else inside the directory received from Dart.
const STORES_DIR_NAME: &str = "stores";

pub(crate) struct Store {
    pub(crate) id: String,
    pub(crate) path: PathBuf,
}

pub(crate) fn create_store(data_dir: &Path) -> io::Result<Store> {
    let id = format!("{:032x}", rand::random::<u128>());
    let path = stores_dir(data_dir).join(&id);
    fs::create_dir_all(&path)?;
    Ok(Store { id, path })
}

pub(crate) fn existing_store(data_dir: &Path, id: &str) -> Option<PathBuf> {
    store_path(data_dir, id).filter(|path| path.is_dir())
}

pub(crate) fn remove_store(data_dir: &Path, id: &str) -> io::Result<()> {
    match store_path(data_dir, id) {
        Some(path) => remove_dir_if_exists(&path),
        None => Ok(()),
    }
}

pub(crate) fn remove_other_stores(data_dir: &Path, keep_id: &str) -> io::Result<()> {
    let entries = match fs::read_dir(stores_dir(data_dir)) {
        Ok(entries) => entries,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(()),
        Err(error) => return Err(error),
    };
    for entry in entries {
        let entry = entry?;
        if entry.file_name() == keep_id {
            continue;
        }
        if entry.file_type()?.is_dir() {
            remove_dir_if_exists(&entry.path())?;
        } else {
            fs::remove_file(entry.path())?;
        }
    }
    Ok(())
}

pub(crate) fn remove_all_stores(data_dir: &Path) -> io::Result<()> {
    remove_dir_if_exists(&stores_dir(data_dir))
}

fn stores_dir(data_dir: &Path) -> PathBuf {
    data_dir.join(STORES_DIR_NAME)
}

// The id comes back from Dart storage, so it must not be able to point outside the
// stores directory.
fn store_path(data_dir: &Path, id: &str) -> Option<PathBuf> {
    let valid = !id.is_empty() && id.chars().all(|c| c.is_ascii_alphanumeric());
    valid.then(|| stores_dir(data_dir).join(id))
}

fn remove_dir_if_exists(path: &Path) -> io::Result<()> {
    match fs::remove_dir_all(path) {
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

    fn is_empty_dir(path: &Path) -> bool {
        fs::read_dir(path).expect("read directory").next().is_none()
    }

    #[test]
    fn creates_empty_stores_with_distinct_ids() {
        let dir = data_dir();

        let first = create_store(dir.path()).expect("first store");
        let second = create_store(dir.path()).expect("second store");

        assert_ne!(first.id, second.id);
        assert!(is_empty_dir(&first.path));
        assert!(is_empty_dir(&second.path));
    }

    #[test]
    fn finds_an_existing_store_by_id() {
        let dir = data_dir();
        let store = create_store(dir.path()).expect("store");

        assert_eq!(existing_store(dir.path(), &store.id), Some(store.path));
        assert_eq!(existing_store(dir.path(), "0123abcd"), None);
    }

    #[test]
    fn rejects_ids_that_leave_the_stores_directory() {
        let dir = data_dir();
        let outside = dir.path().join("outside");
        fs::create_dir_all(&outside).expect("outside directory");
        create_store(dir.path()).expect("store");

        for id in ["", "..", "../outside", "a/b", "a\\b"] {
            assert_eq!(existing_store(dir.path(), id), None);
            remove_store(dir.path(), id).expect("remove is a no-op");
        }

        assert!(outside.is_dir());
        assert!(stores_dir(dir.path()).is_dir());
    }

    #[test]
    fn removes_only_the_given_store() {
        let dir = data_dir();
        let kept = create_store(dir.path()).expect("kept store");
        let removed = create_store(dir.path()).expect("removed store");

        remove_store(dir.path(), &removed.id).expect("remove store");

        assert!(kept.path.is_dir());
        assert!(!removed.path.exists());
    }

    #[test]
    fn removes_other_stores_and_keeps_the_given_one() {
        let dir = data_dir();
        let old = create_store(dir.path()).expect("old store");
        fs::write(old.path.join("state.sqlite3"), b"old").expect("old file");
        let current = create_store(dir.path()).expect("current store");

        remove_other_stores(dir.path(), &current.id).expect("remove other stores");

        assert!(!old.path.exists());
        assert!(current.path.is_dir());
    }

    #[test]
    fn removing_all_stores_keeps_other_files_in_data_dir() {
        let dir = data_dir();
        let sibling = dir.path().join("other.txt");
        fs::write(&sibling, b"keep").expect("sibling file");
        create_store(dir.path()).expect("store");

        remove_all_stores(dir.path()).expect("remove all stores");

        assert!(!stores_dir(dir.path()).exists());
        assert!(sibling.exists());
    }

    #[test]
    fn removal_succeeds_when_nothing_exists() {
        let dir = data_dir();

        assert!(remove_store(dir.path(), "0123abcd").is_ok());
        assert!(remove_other_stores(dir.path(), "0123abcd").is_ok());
        assert!(remove_all_stores(dir.path()).is_ok());
    }
}
