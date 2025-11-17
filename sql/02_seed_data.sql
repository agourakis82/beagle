-- BEAGLE v2.0 - Seed Data
-- Initial test records

INSERT INTO papers (title, authors, abstract, doi, journal, publication_date)
VALUES 
    ('BEAGLE Test Paper', ARRAY['Demetrios Chiuratto'], 'Test abstract for system validation', '10.0000/test.001', 'Test Journal', '2025-11-16')
ON CONFLICT (doi) DO NOTHING;
