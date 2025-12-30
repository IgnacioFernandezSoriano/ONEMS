#!/usr/bin/env python3
"""
Translate all strings in translations_template.csv to ES, FR, and AR
using OpenAI API for high-quality translations
"""

import csv
import os
from openai import OpenAI

# Initialize OpenAI client (API key from environment)
client = OpenAI()

def translate_batch(texts, target_lang, source_lang='en'):
    """Translate a batch of texts to target language"""
    
    lang_names = {
        'es': 'Spanish',
        'fr': 'French',
        'ar': 'Arabic'
    }
    
    # Create prompt for batch translation
    prompt = f"""Translate the following English texts to {lang_names[target_lang]}.
Maintain technical terminology and context.
For UI elements, use standard {lang_names[target_lang]} conventions.
Return ONLY the translations, one per line, in the same order.

Texts to translate:
"""
    
    for i, text in enumerate(texts, 1):
        prompt += f"{i}. {text}\n"
    
    try:
        response = client.chat.completions.create(
            model="gpt-4.1-mini",
            messages=[
                {"role": "system", "content": f"You are a professional translator specializing in software localization. Translate English to {lang_names[target_lang]} maintaining technical accuracy and UI conventions."},
                {"role": "user", "content": prompt}
            ],
            temperature=0.3
        )
        
        # Parse response
        translations = response.choices[0].message.content.strip().split('\n')
        
        # Clean up translations (remove numbering if present)
        cleaned = []
        for trans in translations:
            # Remove leading numbers like "1. ", "2. ", etc.
            trans = trans.strip()
            if trans and trans[0].isdigit() and '. ' in trans:
                trans = trans.split('. ', 1)[1]
            cleaned.append(trans)
        
        return cleaned
    
    except Exception as e:
        print(f"Error translating batch: {e}")
        return [''] * len(texts)

def main():
    input_file = 'translations_template.csv'
    output_file = 'translations_complete_all.csv'
    
    print(f"Reading {input_file}...")
    
    # Read input CSV
    rows = []
    with open(input_file, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            rows.append(row)
    
    print(f"Found {len(rows)} strings to translate")
    
    # Translate in batches of 20 for efficiency
    batch_size = 20
    total_batches = (len(rows) + batch_size - 1) // batch_size
    
    for lang in ['es', 'fr', 'ar']:
        print(f"\nTranslating to {lang.upper()}...")
        
        for batch_idx in range(0, len(rows), batch_size):
            batch_num = batch_idx // batch_size + 1
            print(f"  Batch {batch_num}/{total_batches}...", end='', flush=True)
            
            batch_rows = rows[batch_idx:batch_idx + batch_size]
            texts = [row['en'] for row in batch_rows]
            
            translations = translate_batch(texts, lang)
            
            # Assign translations to rows
            for i, trans in enumerate(translations):
                if i < len(batch_rows):
                    batch_rows[i][lang] = trans
            
            print(" ✓")
    
    # Write output CSV
    print(f"\nWriting {output_file}...")
    with open(output_file, 'w', encoding='utf-8', newline='') as f:
        fieldnames = ['key', 'en', 'es', 'fr', 'ar']
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        
        writer.writeheader()
        for row in rows:
            writer.writerow({
                'key': row['key'],
                'en': row['en'],
                'es': row.get('es', ''),
                'fr': row.get('fr', ''),
                'ar': row.get('ar', '')
            })
    
    print(f"✅ Translation complete! Output: {output_file}")
    print(f"   Total strings: {len(rows)}")
    print(f"   Languages: EN, ES, FR, AR")

if __name__ == '__main__':
    main()
