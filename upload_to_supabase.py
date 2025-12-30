#!/usr/bin/env python3
"""
Upload translation CSV files to Supabase Storage
"""

import os
from supabase import create_client, Client

# Get Supabase credentials from environment
SUPABASE_URL = os.getenv('SUPABASE_URL')
SUPABASE_KEY = os.getenv('SUPABASE_SERVICE_ROLE_KEY') or os.getenv('SUPABASE_ANON_KEY')

if not SUPABASE_URL or not SUPABASE_KEY:
    print("❌ Error: SUPABASE_URL and SUPABASE_KEY environment variables required")
    print("   Please provide Supabase credentials")
    exit(1)

# Initialize Supabase client
supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

def upload_file(file_path, bucket='translations'):
    """Upload a file to Supabase Storage"""
    
    file_name = os.path.basename(file_path)
    
    print(f"Uploading {file_name}...", end='', flush=True)
    
    try:
        # Read file content
        with open(file_path, 'rb') as f:
            file_content = f.read()
        
        # Delete existing file if it exists
        try:
            supabase.storage.from_(bucket).remove([file_name])
        except:
            pass  # File might not exist
        
        # Upload new file
        result = supabase.storage.from_(bucket).upload(
            file_name,
            file_content,
            file_options={"content-type": "text/csv"}
        )
        
        print(" ✓")
        return True
        
    except Exception as e:
        print(f" ✗ Error: {e}")
        return False

def main():
    print("Uploading translation files to Supabase Storage...")
    print(f"Bucket: translations")
    print()
    
    files = ['en.csv', 'es.csv', 'fr.csv']
    
    success_count = 0
    for file_path in files:
        if os.path.exists(file_path):
            if upload_file(file_path):
                success_count += 1
        else:
            print(f"❌ File not found: {file_path}")
    
    print()
    print(f"✅ Upload complete: {success_count}/{len(files)} files uploaded")
    
    if success_count == len(files):
        print("🎉 All translations are now available in Supabase Storage!")
        print("   Users will see translations immediately after refresh")

if __name__ == '__main__':
    main()
