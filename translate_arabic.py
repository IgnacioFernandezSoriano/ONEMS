#!/usr/bin/env python3
"""
Translate all strings to Arabic
"""

import csv
from openai import OpenAI

client = OpenAI()

def translate_batch(texts):
    """Translate a batch of texts to Arabic"""
    
    prompt = """Translate the following English texts to Modern Standard Arabic (العربية الفصحى).
Maintain technical terminology and context.
For UI elements, use standard Arabic conventions.
Return ONLY the translations, one per line, in the same order.

Texts to translate:
"""
    
    for i, text in enumerate(texts, 1):
        prompt += f"{i}. {text}\n"
    
    try:
        response = client.chat.completions.create(
            model="gpt-4.1-mini",
            messages=[
                {"role": "system", "content": "You are a professional translator specializing in software localization. Translate English to Modern Standard Arabic maintaining technical accuracy and UI conventions."},
                {"role": "user", "content": prompt}
            ],
            temperature=0.3
        )
        
        translations = response.choices[0].message.content.strip().split('\n')
        
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
    
    rows = []
    with open(input_file, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            rows.append(row)
    
    print(f"Found {len(rows)} strings")
    print(f"Translating to Arabic...")
    
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
                batch_rows[i]['ar'] = trans
        
        print(" ✓")
    
    print(f"\nGenerating ar.csv...")
    with open('ar.csv', 'w', encoding='utf-8', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['key', 'translation'])
        for row in rows:
            writer.writerow([row['key'], row.get('ar', '')])
    
    print(f"\n✅ Complete!")
    print(f"   ar.csv: {len(rows)} strings")

if __name__ == '__main__':
    main()
