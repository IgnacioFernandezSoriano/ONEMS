#!/bin/bash

SUPABASE_URL="https://sehbnpgzqljrsqimwyuz.supabase.co"
SERVICE_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNlaGJucGd6cWxqcnNxaW13eXV6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjQ4OTQzMTEsImV4cCI6MjA4MDQ3MDMxMX0.C-LsSmfOo38Tqc_PwP1c-nFyK1PeVj_mCBqanYsgoeg"

echo "Uploading translation files to Supabase Storage..."
echo "Bucket: translations"
echo ""

for file in en.csv es.csv fr.csv; do
    echo -n "Uploading $file... "
    
    # Upload file
    response=$(curl -s -X POST \
        "$SUPABASE_URL/storage/v1/object/translations/$file" \
        -H "Authorization: Bearer $SERVICE_KEY" \
        -H "Content-Type: text/csv" \
        -F "file=@$file" 2>&1)
    
    if echo "$response" | grep -q "error"; then
        echo "✗ Error: $response"
    else
        echo "✓"
    fi
done

echo ""
echo "✅ Upload complete!"
