use std::sync::{Mutex, PoisonError};

use tokio::task::AbortHandle;

// Owns a background task: replacing or dropping it aborts the task, so its lifetime
// follows the owner instead of waiting for the task to notice it is no longer needed.
#[derive(Default)]
pub(crate) struct OwnedTask(Mutex<Option<AbortHandle>>);

impl OwnedTask {
    pub(crate) fn replace(&self, task: AbortHandle) {
        let previous = self
            .0
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .replace(task);
        if let Some(previous) = previous {
            previous.abort();
        }
    }
}

impl Drop for OwnedTask {
    fn drop(&mut self) {
        let task = self
            .0
            .get_mut()
            .unwrap_or_else(PoisonError::into_inner)
            .take();
        if let Some(task) = task {
            task.abort();
        }
    }
}

#[cfg(test)]
mod tests {
    use std::future::pending;

    use super::*;

    #[tokio::test]
    async fn dropping_the_owner_aborts_the_task() {
        let task = tokio::spawn(pending::<()>());
        let owner = OwnedTask::default();
        owner.replace(task.abort_handle());

        drop(owner);

        assert!(task.await.expect_err("task was aborted").is_cancelled());
    }

    #[tokio::test]
    async fn replacing_the_task_aborts_the_previous_one() {
        let first = tokio::spawn(pending::<()>());
        let second = tokio::spawn(pending::<()>());
        let owner = OwnedTask::default();
        owner.replace(first.abort_handle());

        owner.replace(second.abort_handle());

        assert!(first.await.expect_err("task was aborted").is_cancelled());
        assert!(!second.is_finished());
    }
}
