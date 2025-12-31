#!/usr/bin/env python3
import csv
import os
from openai import OpenAI

client = OpenAI()

# Read English menu translations
with open('menu_translations_en.csv', 'r', encoding='utf-8') as f:
    reader = csv.DictReader(f)
    menu_items = list(reader)

print(f"Loaded {len(menu_items)} menu translations")

# Translate to Spanish, French, and Arabic
for target_lang, lang_name in [('es', 'Spanish'), ('fr', 'French'), ('ar', 'Arabic')]:
    print(f"\nTranslating to {lang_name}...")
    
    translations = []
    
    # Translate in batches of 10
    batch_size = 10
    for i in range(0, len(menu_items), batch_size):
        batch = menu_items[i:i+batch_size]
        
        # Prepare batch for translation
        texts_to_translate = [item['translation'] for item in batch]
        
        prompt = f"""Translate the following UI menu items to {lang_name}.
Maintain professional tone and technical terminology.
Return ONLY the translations, one per line, in the same order.

Texts to translate:
{chr(10).join(f"{idx+1}. {text}" for idx, text in enumerate(texts_to_translate))}"""
        
        response = client.chat.completions.create(
            model="gpt-4.1-mini",
            messages=[{"role": "user", "content": prompt}],
            temperature=0.3
        )
        
        translated_lines = response.choices[0].message.content.strip().split('\n')
        
        # Clean up numbering if present
        cleaned_translations = []
        for line in translated_lines:
            # Remove leading numbers like "1. ", "2. ", etc.
            cleaned = line.strip()
            if cleaned and cleaned[0].isdigit():
                # Find the first non-digit, non-dot, non-space character
                for j, char in enumerate(cleaned):
                    if char not in '0123456789. ':
                        cleaned = cleaned[j:]
                        break
            cleaned_translations.append(cleaned)
        
        for item, translation in zip(batch, cleaned_translations):
            translations.append({
                'key': item['key'],
                'translation': translation
            })
        
        print(f"  Batch {i//batch_size + 1}/{(len(menu_items) + batch_size - 1)//batch_size} done")
    
    # Write to file
    output_file = f'menu_translations_{target_lang}.csv'
    with open(output_file, 'w', encoding='utf-8', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=['key', 'translation'])
        writer.writeheader()
        writer.writerows(translations)
    
    print(f"✓ Saved {output_file}")

print("\n✓ All menu translations completed!")
