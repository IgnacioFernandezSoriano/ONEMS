#!/usr/bin/env python3
"""
Generate synthetic RFID events for ONEMS diagnosis testing
Creates realistic journey data across the postal network
"""

import os
import random
from datetime import datetime, timedelta
from supabase import create_client, Client

# Supabase configuration
SUPABASE_URL = os.getenv('SUPABASE_URL', 'https://sehbnpgzqljrsqimwyuz.supabase.co')
SUPABASE_KEY = os.getenv('SUPABASE_KEY')

if not SUPABASE_KEY:
    print("ERROR: SUPABASE_KEY environment variable not set")
    exit(1)

supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

# Get DEMO2 account
account = supabase.table('accounts').select('id').eq('name', 'DEMO2').execute()
if not account.data:
    print("ERROR: DEMO2 account not found")
    exit(1)

ACCOUNT_ID = account.data[0]['id']
print(f"Using account: DEMO2 ({ACCOUNT_ID})")

# Get postal centers
centers = supabase.table('postal_centers').select('id, code, name').eq('account_id', ACCOUNT_ID).execute()
centers_map = {c['code']: c for c in centers.data}
print(f"Found {len(centers_map)} postal centers")

# Get readers
readers = supabase.table('readers').select('id, reader_id, postal_center_id, type').eq('account_id', ACCOUNT_ID).execute()
readers_by_center = {}
for r in readers.data:
    pc_id = r['postal_center_id']
    if pc_id not in readers_by_center:
        readers_by_center[pc_id] = {'entry': [], 'exit': []}
    if r['type'] == 'Entry':
        readers_by_center[pc_id]['entry'].append(r)
    elif r['type'] == 'Exit':
        readers_by_center[pc_id]['exit'].append(r)

print(f"Found {len(readers.data)} readers")

# Define realistic routes
ROUTES = [
    # East Coast routes (USPS)
    {
        'name': 'Baltimore → Philadelphia → Chicago',
        'path': ['BAL-LC', 'PHL-HUB', 'CHI-DC'],
        'carrier': 'USPS',
        'tags_per_day': 50,
        'operational_time_range': (15, 45),  # minutes
        'distribution_time_multiplier': 1.0
    },
    # Cross-country routes (FedEx)
    {
        'name': 'Philadelphia → Chicago → Denver → San Francisco',
        'path': ['PHL-HUB', 'CHI-DC', 'DEN-HUB', 'SFO-PC'],
        'carrier': 'FedEx',
        'tags_per_day': 30,
        'operational_time_range': (20, 40),
        'distribution_time_multiplier': 0.9  # Faster
    },
    # Reverse routes
    {
        'name': 'San Francisco → Denver → Chicago',
        'path': ['SFO-PC', 'DEN-HUB', 'CHI-DC'],
        'carrier': 'FedEx',
        'tags_per_day': 25,
        'operational_time_range': (20, 40),
        'distribution_time_multiplier': 0.9
    }
]

# Get SLAs for time estimation
slas = supabase.table('slas').select('*').eq('account_id', ACCOUNT_ID).execute()
slas_map = {}
for sla in slas.data:
    if sla['sla_type'] == 'operational':
        key = f"op_{sla['postal_center_id']}"
    else:
        key = f"dist_{sla['from_postal_center_id']}_{sla['to_postal_center_id']}"
    slas_map[key] = sla

def generate_tag_id():
    """Generate realistic tag ID"""
    return f"TAG{random.randint(100000, 999999)}"

def generate_events_for_route(route, start_date, days=7):
    """Generate events for a specific route over multiple days"""
    events = []
    tags_per_day = route['tags_per_day']
    path = route['path']
    
    for day in range(days):
        current_date = start_date + timedelta(days=day)
        
        # Generate tags for this day
        for _ in range(tags_per_day):
            tag_id = generate_tag_id()
            current_time = current_date + timedelta(
                hours=random.randint(6, 20),  # Business hours
                minutes=random.randint(0, 59)
            )
            
            # Generate events for each center in the path
            for i, center_code in enumerate(path):
                if center_code not in centers_map:
                    print(f"WARNING: Center {center_code} not found, skipping")
                    continue
                
                center = centers_map[center_code]
                center_id = center['id']
                
                # Check if center has readers
                if center_id not in readers_by_center:
                    print(f"WARNING: No readers for center {center_code}, skipping")
                    continue
                
                entry_readers = readers_by_center[center_id]['entry']
                exit_readers = readers_by_center[center_id]['exit']
                
                if not entry_readers or not exit_readers:
                    print(f"WARNING: Incomplete readers for {center_code}, skipping")
                    continue
                
                # Entry event
                entry_reader = random.choice(entry_readers)
                events.append({
                    'account_id': ACCOUNT_ID,
                    'event_id': f"{tag_id}_{entry_reader['reader_id']}_{int(current_time.timestamp())}",
                    'read_local_datetime': current_time.isoformat(),
                    'reader_id': entry_reader['reader_id'],
                    'tag_id': tag_id,
                    'is_processed': False
                })
                
                # Operational time (inside center)
                op_sla_key = f"op_{center_id}"
                if op_sla_key in slas_map:
                    expected_op_time = slas_map[op_sla_key]['expected_time_minutes']
                else:
                    expected_op_time = 30  # Default
                
                # Add some variance (80% to 120% of expected)
                op_time_min, op_time_max = route['operational_time_range']
                actual_op_time = random.randint(op_time_min, op_time_max)
                current_time += timedelta(minutes=actual_op_time)
                
                # Exit event
                exit_reader = random.choice(exit_readers)
                events.append({
                    'account_id': ACCOUNT_ID,
                    'event_id': f"{tag_id}_{exit_reader['reader_id']}_{int(current_time.timestamp())}",
                    'read_local_datetime': current_time.isoformat(),
                    'reader_id': exit_reader['reader_id'],
                    'tag_id': tag_id,
                    'is_processed': False
                })
                
                # Distribution time (to next center)
                if i < len(path) - 1:
                    next_center_code = path[i + 1]
                    if next_center_code in centers_map:
                        next_center_id = centers_map[next_center_code]['id']
                        dist_sla_key = f"dist_{center_id}_{next_center_id}"
                        
                        if dist_sla_key in slas_map:
                            expected_dist_time = slas_map[dist_sla_key]['expected_time_minutes']
                        else:
                            # Estimate based on distance
                            expected_dist_time = 360  # Default 6 hours
                        
                        # Apply multiplier and variance
                        actual_dist_time = int(expected_dist_time * route['distribution_time_multiplier'] * random.uniform(0.85, 1.15))
                        current_time += timedelta(minutes=actual_dist_time)
    
    return events

def insert_events_batch(events, batch_size=100):
    """Insert events in batches"""
    total = len(events)
    inserted = 0
    
    for i in range(0, total, batch_size):
        batch = events[i:i+batch_size]
        try:
            supabase.table('rfid_events_raw').insert(batch).execute()
            inserted += len(batch)
            print(f"Inserted {inserted}/{total} events...")
        except Exception as e:
            print(f"ERROR inserting batch: {e}")
    
    return inserted

def main():
    print("=" * 60)
    print("ONEMS Synthetic Event Generator")
    print("=" * 60)
    
    # Generate events for the past 7 days
    start_date = datetime.now() - timedelta(days=7)
    all_events = []
    
    for route in ROUTES:
        print(f"\nGenerating events for route: {route['name']}")
        events = generate_events_for_route(route, start_date, days=7)
        all_events.extend(events)
        print(f"  Generated {len(events)} events")
    
    print(f"\nTotal events generated: {len(all_events)}")
    print("\nInserting events into database...")
    
    inserted = insert_events_batch(all_events)
    
    print(f"\n✅ Successfully inserted {inserted} events")
    print("\nNext steps:")
    print("1. Run consolidation: SELECT consolidate_rfid_events();")
    print("2. Run reconstruction: SELECT reconstruct_journeys();")
    print("3. Run assembly: SELECT assemble_complete_journeys();")

if __name__ == '__main__':
    main()
