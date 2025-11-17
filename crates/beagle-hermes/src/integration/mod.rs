pub mod word;
pub mod overleaf;
pub mod google_docs;

pub use google_docs::{GoogleDocsClient, GoogleDoc};
pub use overleaf::{OverleafClient, OverleafProject};
pub use word::{WordExporter, ManuscriptContent};

