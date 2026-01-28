#!/usr/bin/env python3
"""
Script to insert DEMO2 seed data into Supabase
Run this after executing the UP migration
"""

from supabase import create_client
import json
import sys
import os

# Configuration
SUPABASE_URL = "https://sehbnpgzqljrsqimwyuz.supabase.co"
SUPABASE_KEY = os.environ.get('SUPABASE_SERVICE_ROLE_KEY', '')

if not SUPABASE_KEY:
    print("❌ Error: SUPABASE_SERVICE_ROLE_KEY environment variable not set")
    print("   Set it with: export SUPABASE_SERVICE_ROLE_KEY='your-key'")
    sys.exit(1)

# Path to seed data file
SEED_DATA_FILE = os.path.join(os.path.dirname(__file__), '../seed_data/demo2_seed_data.json')

if not os.path.exists(SEED_DATA_FILE):
    print(f"❌ Error: Seed data file not found: {SEED_DATA_FILE}")
    sys.exit(1)

# Create Supabase client
supabase = create_client(SUPABASE_URL, SUPABASE_KEY)

print("=" * 80)
print("INSERTING DEMO2 SEED DATA INTO SUPABASE")
print("=" * 80)

# Read seed data
with open(SEED_DATA_FILE, 'r') as f:
    seed_data = json.load(f)

print(f"\nLoaded seed data from: {SEED_DATA_FILE}")
print(f"Tables to insert: {len(seed_data)}\n")

# Insert data
success_count = 0
error_count = 0

for table_name, records in seed_data.items():
    print(f"📦 {table_name}: {len(records)} records", end=" ... ")
    
    try:
        result = supabase.table('demo2_seed_data').upsert({
            'table_name': table_name,
            'data': records,
            'record_count': len(records)
        }, on_conflict='table_name').execute()
        
        if result.data:
            print("✅ OK")
            success_count += 1
        else:
            print("❌ FAILED")
            error_count += 1
    except Exception as e:
        print(f"❌ ERROR: {str(e)}")
        error_count += 1

print("\n" + "=" * 80)
print(f"SUMMARY: {success_count} succeeded, {error_count} failed")
print("=" * 80)

if error_count == 0:
    print("\n✅ All seed data inserted successfully!")
    print("\nNext steps:")
    print("1. Test the new function: SELECT admin_reset_and_seed_demo2();")
    print("2. Update frontend to call the new function")
    print("3. Deploy to Netlify")
    sys.exit(0)
else:
    print("\n⚠️  Some errors occurred. Please check the output above.")
    sys.exit(1)
