#!/usr/bin/env python3
"""
Extract translatable strings from React/TypeScript application
Generates CSV template for external translation
"""

import os
import re
import csv
from pathlib import Path
from collections import defaultdict

# Patterns to extract strings
PATTERNS = [
    # JSX text content: <tag>Text</tag>
    (r'>\s*([A-Z][^<>{}\n]{3,80})\s*<', 'jsx_text'),
    # String literals in common places
    (r'title=["\']([^"\']+)["\']', 'title_attr'),
    (r'placeholder=["\']([^"\']+)["\']', 'placeholder'),
    (r'label=["\']([^"\']+)["\']', 'label'),
    (r'text=["\']([^"\']+)["\']', 'text_prop'),
    # Button/link text
    (r'<button[^>]*>\s*([A-Z][^<>{}]{2,40})\s*</button>', 'button'),
    (r'className="[^"]*button[^"]*"[^>]*>\s*([A-Z][^<>{}]{2,40})\s*<', 'button_class'),
]

# Strings to ignore (technical terms, variable names, etc.)
IGNORE_PATTERNS = [
    r'^[A-Z_]+$',  # ALL_CAPS constants
    r'^\d+$',  # Numbers only
    r'^[a-z_]+$',  # snake_case variables
    r'.*\{.*\}.*',  # Contains template variables
    r'^(true|false|null|undefined)$',  # JS keywords
    r'.*\$\{.*\}.*',  # Template literals
    r'^(px|rem|em|%|vh|vw)$',  # CSS units
]

# Common words that appear frequently (extract once)
COMMON_TRANSLATIONS = {
    'Save': 'common.save',
    'Cancel': 'common.cancel',
    'Delete': 'common.delete',
    'Edit': 'common.edit',
    'Add': 'common.add',
    'Close': 'common.close',
    'Confirm': 'common.confirm',
    'Loading': 'common.loading',
    'Error': 'common.error',
    'Success': 'common.success',
    'Search': 'common.search',
    'Filter': 'common.filter',
    'Export': 'common.export',
    'Import': 'common.import',
    'Refresh': 'common.refresh',
    'Actions': 'common.actions',
    'Status': 'common.status',
    'Total': 'common.total',
    'Active': 'common.active',
    'Inactive': 'common.inactive',
    'Yes': 'common.yes',
    'No': 'common.no',
    'Submit': 'common.submit',
    'Reset': 'common.reset',
    'Back': 'common.back',
    'Next': 'common.next',
    'Previous': 'common.previous',
    'Continue': 'common.continue',
    'Finish': 'common.finish',
    'Select': 'common.select',
    'Clear': 'common.clear',
    'Apply': 'common.apply',
    'Remove': 'common.remove',
    'Update': 'common.update',
    'Create': 'common.create',
    'View': 'common.view',
    'Download': 'common.download',
    'Upload': 'common.upload',
}

def should_ignore(text):
    """Check if text should be ignored"""
    if not text or len(text) < 3:
        return True
    for pattern in IGNORE_PATTERNS:
        if re.match(pattern, text):
            return True
    return False

def extract_from_file(filepath):
    """Extract translatable strings from a single file"""
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
    except:
        return []
    
    found = []
    
    for pattern, context in PATTERNS:
        matches = re.finditer(pattern, content, re.MULTILINE)
        for match in matches:
            text = match.group(1).strip()
            if not should_ignore(text):
                found.append((text, context))
    
    return found

def generate_key(text, module, context):
    """Generate a translation key from text and context"""
    # Check if it's a common word
    if text in COMMON_TRANSLATIONS:
        return COMMON_TRANSLATIONS[text]
    
    # Generate key from text
    key_text = text.lower()
    key_text = re.sub(r'[^a-z0-9]+', '_', key_text)
    key_text = key_text.strip('_')
    
    # Limit length
    if len(key_text) > 50:
        key_text = key_text[:50]
    
    return f"{module}.{key_text}"

def get_module_from_path(filepath):
    """Extract module name from file path"""
    parts = Path(filepath).parts
    
    if 'pages' in parts:
        idx = parts.index('pages')
        if idx + 1 < len(parts):
            module = parts[idx + 1]
            if module.endswith('.tsx'):
                module = Path(module).stem
            return module.lower().replace(' ', '_')
    
    if 'components' in parts:
        idx = parts.index('components')
        if idx + 1 < len(parts):
            module = parts[idx + 1]
            return module.lower().replace('-', '_')
    
    return 'common'

def main():
    src_dir = Path('src')
    translations = {}
    
    print("Scanning application files...")
    
    # Scan all TSX files
    tsx_files = list(src_dir.glob('**/*.tsx'))
    print(f"Found {len(tsx_files)} files to scan")
    
    for filepath in tsx_files:
        module = get_module_from_path(str(filepath))
        screen = filepath.stem
        
        strings = extract_from_file(filepath)
        
        for text, context in strings:
            key = generate_key(text, module, context)
            
            # Avoid duplicates
            if key not in translations:
                translations[key] = {
                    'key': key,
                    'en': text,
                    'es': '',
                    'fr': '',
                    'ar': '',
                    'context': context,
                    'screen': screen
                }
    
    print(f"Extracted {len(translations)} unique strings")
    
    # Write to CSV
    output_file = 'translations_template.csv'
    with open(output_file, 'w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=['key', 'en', 'es', 'fr', 'ar', 'context', 'screen'])
        writer.writeheader()
        
        # Sort by key
        for key in sorted(translations.keys()):
            writer.writerow(translations[key])
    
    print(f"✅ CSV template generated: {output_file}")
    print(f"   Total translations: {len(translations)}")
    print(f"   Ready for external translation")

if __name__ == '__main__':
    main()
