-- Create storage bucket for translation files
INSERT INTO storage.buckets (id, name, public)
VALUES ('translations', 'translations', true)
ON CONFLICT (id) DO NOTHING;

-- Allow authenticated users to read translation files
CREATE POLICY "Public read access for translations"
ON storage.objects FOR SELECT
USING (bucket_id = 'translations');

-- Allow superadmin to upload/update translation files
CREATE POLICY "Superadmin can upload translations"
ON storage.objects FOR INSERT
WITH CHECK (
  bucket_id = 'translations' 
  AND auth.uid() IN (
    SELECT id FROM profiles WHERE role = 'superadmin'
  )
);

CREATE POLICY "Superadmin can update translations"
ON storage.objects FOR UPDATE
USING (
  bucket_id = 'translations' 
  AND auth.uid() IN (
    SELECT id FROM profiles WHERE role = 'superadmin'
  )
);

CREATE POLICY "Superadmin can delete translations"
ON storage.objects FOR DELETE
USING (
  bucket_id = 'translations' 
  AND auth.uid() IN (
    SELECT id FROM profiles WHERE role = 'superadmin'
  )
);
