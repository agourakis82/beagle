use std::collections::VecDeque;

#[derive(Debug, Clone)]
pub struct Chunk {
    pub index: u32,
    pub text: String,
}

fn finalize_chunk(chunks: &mut Vec<Chunk>, index: &mut u32, buffer: &mut Vec<String>) {
    if buffer.is_empty() {
        return;
    }
    let text = buffer.join("\n");
    chunks.push(Chunk {
        index: *index,
        text,
    });
    *index += 1;
}

pub fn chunk_lines(text: &str, chunk_size: usize, overlap_chars: usize) -> Vec<Chunk> {
    let mut chunks = Vec::new();
    let mut index = 0u32;

    let mut buffer: Vec<String> = Vec::new();
    let mut buffer_len = 0usize;
    let mut overlap: VecDeque<String> = VecDeque::new();
    let mut overlap_len = 0usize;

    for line in text.lines() {
        let line_len = line.len() + 1;
        if buffer_len + line_len > chunk_size && !buffer.is_empty() {
            finalize_chunk(&mut chunks, &mut index, &mut buffer);

            // rebuild buffer from overlap
            buffer = overlap.iter().cloned().collect();
            buffer_len = overlap_len;
        }

        buffer.push(line.to_string());
        buffer_len += line_len;

        // maintain overlap deque
        overlap.push_back(line.to_string());
        overlap_len += line_len;
        while overlap_len > overlap_chars && !overlap.is_empty() {
            let removed = overlap.pop_front().unwrap();
            overlap_len = overlap_len.saturating_sub(removed.len() + 1);
        }
    }

    if !buffer.is_empty() {
        finalize_chunk(&mut chunks, &mut index, &mut buffer);
    }

    chunks
}

pub fn chunk_paragraphs(text: &str, chunk_size: usize, overlap_chars: usize) -> Vec<Chunk> {
    let mut chunks = Vec::new();
    let mut index = 0u32;

    let paragraphs = text
        .split("\n\n")
        .map(|p| p.trim())
        .filter(|p| !p.is_empty());

    let mut buffer: Vec<String> = Vec::new();
    let mut buffer_len = 0usize;
    let mut overlap: VecDeque<String> = VecDeque::new();
    let mut overlap_len = 0usize;

    for para in paragraphs {
        let para_len = para.len() + 2;
        if buffer_len + para_len > chunk_size && !buffer.is_empty() {
            let text = buffer.join("\n\n");
            chunks.push(Chunk { index, text });
            index += 1;

            buffer = overlap.iter().cloned().collect();
            buffer_len = overlap_len;
        }

        buffer.push(para.to_string());
        buffer_len += para_len;

        overlap.push_back(para.to_string());
        overlap_len += para_len;
        while overlap_len > overlap_chars && !overlap.is_empty() {
            let removed = overlap.pop_front().unwrap();
            overlap_len = overlap_len.saturating_sub(removed.len() + 2);
        }
    }

    if !buffer.is_empty() {
        let text = buffer.join("\n\n");
        chunks.push(Chunk { index, text });
    }

    chunks
}
