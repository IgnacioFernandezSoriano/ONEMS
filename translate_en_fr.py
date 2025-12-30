#!/usr/bin/env python3
"""
Translate all strings to French only (English already exists)
Then generate en.csv and fr.csv files
"""

import csv
import os
from openai import OpenAI

# Initialize OpenAI client
client = OpenAI()

def translate_batch(texts, target_lang='fr'):
    """Translate a batch of texts to French"""
    
    prompt = f"""Translate the following English texts to French.
Maintain technical terminology and context.
For UI elements, use standard French conventions.
Return ONLY the translations, one per line, in the same order.

Texts to translate:
"""
    
    for i, text in enumerate(texts, 1):
        prompt += f"{i}. {text}\n"
    
    try:
        response = client.chat.completions.create(
            model="gpt-4.1-mini",
            messages=[
                {"role": "system", "content": "You are a professional translator specializing in software localization. Translate English to French maintaining technical accuracy and UI conventions."},
                {"role": "user", "content": prompt}
            ],
            temperature=0.3
        )
        
        # Parse response
        translations = response.choices[0].message.content.strip().split('\n')
        
        # Clean up translations
        cleaned = []
        for trans in translations:
            trans = trans.strip()
            if trans and trans[0].isdigit() and '. ' in trans:
                trans = trans.split('. ', 1)[1]
            cleaned.append(trans)
        
        return cleaned
    
    except Exception as e:
        print(f"Error: {e}")
        return [''] * len(texts)

def main():
    input_file = 'translations_template.csv'
    
    print(f"Reading {input_file}...")
    
    # Read input CSV
    rows = []
    with open(input_file, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            rows.append(row)
    
    print(f"Found {len(rows)} strings")
    print(f"Translating to French...")
    
    # Translate in batches
    batch_size = 20
    total_batches = (len(rows) + batch_size - 1) // batch_size
    
    for batch_idx in range(0, len(rows), batch_size):
        batch_num = batch_idx // batch_size + 1
        print(f"  Batch {batch_num}/{total_batches}...", end='', flush=True)
        
        batch_rows = rows[batch_idx:batch_idx + batch_size]
        texts = [row['en'] for row in batch_rows]
        
        translations = translate_batch(texts)
        
        for i, trans in enumerate(translations):
            if i < len(batch_rows):
                batch_rows[i]['fr'] = trans
        
        print(" ✓")
    
    # Write en.csv
    print(f"\nGenerating en.csv...")
    with open('en.csv', 'w', encoding='utf-8', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['key', 'translation'])
        for row in rows:
            writer.writerow([row['key'], row['en']])
    
    # Write fr.csv
    print(f"Generating fr.csv...")
    with open('fr.csv', 'w', encoding='utf-8', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['key', 'translation'])
        for row in rows:
            writer.writerow([row['key'], row.get('fr', '')])
    
    print(f"\n✅ Complete!")
    print(f"   en.csv: {len(rows)} strings")
    print(f"   fr.csv: {len(rows)} strings")

if __name__ == '__main__':
    main()
