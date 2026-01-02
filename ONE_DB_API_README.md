# ONE DB REST API

## Overview

The ONE DB REST API provides programmatic access to your ONE DB data through a secure REST endpoint. Each account has its own API key for authentication and data isolation.

## Features

- ✅ **Secure Authentication**: API key-based authentication per account
- ✅ **Date Range Filtering**: Filter records by sent date range
- ✅ **Rate Limiting**: 10 requests per minute per account
- ✅ **Pagination**: Support for large datasets with limit/offset
- ✅ **Complete Data**: Returns all ONE DB fields
- ✅ **Usage Statistics**: Track API usage and monitor rate limits
- ✅ **Multi-language**: Documentation in English, Spanish, French, and Arabic

## Quick Start

### 1. Generate API Key

Navigate to **Reporting > ONE DB API** in the ONEMS interface and click "Generate API Key". Your API key will be displayed once and should be stored securely.

### 2. Make Your First Request

```bash
curl -X GET "https://your-domain.com/api/onedb/records?start_date=2024-01-01&end_date=2024-12-31&limit=100" \
  -H "Authorization: Bearer your_api_key_here" \
  -H "Content-Type: application/json"
```

## Authentication

All API requests must include your API key in the Authorization header:

```
Authorization: Bearer onedb_live_xxxxxxxxxxxxxxxxxxxxx
```

## Endpoint

### GET /api/onedb/records

Retrieve ONE DB records filtered by date range.

**Query Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `start_date` | string | Yes | Start date for filtering (YYYY-MM-DD) |
| `end_date` | string | Yes | End date for filtering (YYYY-MM-DD) |
| `limit` | integer | No | Maximum records to return (default: 100, max: 1000) |
| `offset` | integer | No | Number of records to skip (default: 0) |

**Response Format:**

```json
{
  "success": true,
  "data": [
    {
      "id": "uuid",
      "sent": "2024-06-15",
      "origin_city": "Madrid",
      "destination_city": "Barcelona",
      "carrier": "Carrier A",
      "product": "Express",
      "material": "Material X",
      "quantity": 100,
      // ... all other ONE DB fields
    }
  ],
  "pagination": {
    "total": 5420,
    "limit": 100,
    "offset": 0,
    "has_more": true
  },
  "meta": {
    "response_time_ms": 245,
    "rate_limit": {
      "limit": 10,
      "remaining": 9,
      "reset_at": "2024-01-01T12:01:00Z"
    }
  }
}
```

## Code Examples

### Python

```python
import requests

url = "https://your-domain.com/api/onedb/records"
headers = {
    "Authorization": "Bearer your_api_key_here",
    "Content-Type": "application/json"
}
params = {
    "start_date": "2024-01-01",
    "end_date": "2024-12-31",
    "limit": 100
}

response = requests.get(url, headers=headers, params=params)
data = response.json()

if data["success"]:
    print(f"Total records: {data['pagination']['total']}")
    for record in data["data"]:
        print(record)
else:
    print(f"Error: {data['error']}")
```

### JavaScript

```javascript
const url = new URL("https://your-domain.com/api/onedb/records");
url.searchParams.append("start_date", "2024-01-01");
url.searchParams.append("end_date", "2024-12-31");
url.searchParams.append("limit", "100");

const response = await fetch(url, {
  headers: {
    "Authorization": "Bearer your_api_key_here",
    "Content-Type": "application/json"
  }
});

const data = await response.json();

if (data.success) {
  console.log(`Total records: ${data.pagination.total}`);
  data.data.forEach(record => console.log(record));
} else {
  console.error(`Error: ${data.error}`);
}
```

## Rate Limiting

The API enforces a rate limit of **10 requests per minute** per account. 

When you exceed the rate limit, you'll receive a `429 Too Many Requests` response:

```json
{
  "success": false,
  "error": "Rate limit exceeded. Maximum 10 requests per minute.",
  "rate_limit": {
    "limit": 10,
    "remaining": 0,
    "reset_at": "2024-01-01T12:01:00Z"
  }
}
```

## HTTP Status Codes

| Code | Description |
|------|-------------|
| 200 | Success - Request completed successfully |
| 400 | Bad Request - Invalid parameters or date format |
| 401 | Unauthorized - Invalid or missing API key |
| 429 | Too Many Requests - Rate limit exceeded |
| 500 | Internal Server Error - Something went wrong on our end |

## Security Best Practices

1. **Keep your API key secure**: Never share it publicly or commit it to version control
2. **Use environment variables**: Store API keys in environment variables, not in code
3. **Regenerate if compromised**: If your API key is exposed, regenerate it immediately
4. **Monitor usage**: Regularly check your API usage statistics for unusual activity
5. **Use HTTPS**: Always use HTTPS for API requests to encrypt data in transit

## Database Setup

Before using the API, you need to run the database migration:

```sql
-- Run this in your Supabase SQL editor
-- File: supabase/migrations/20260101_create_api_keys.sql
```

This creates:
- `api_keys` table for storing API keys
- `api_usage_log` table for tracking usage and rate limiting
- Appropriate RLS policies for security

## Edge Function Deployment

Deploy the Edge Function to Supabase:

```bash
supabase functions deploy onedb-api
```

The function is located at: `supabase/functions/onedb-api/index.ts`

## Support

For issues or questions about the ONE DB API:
- Check the in-app documentation at **Reporting > ONE DB API**
- Review usage statistics to diagnose rate limiting issues
- Contact your system administrator for account-specific questions

## Changelog

### Version 1.0.0 (2026-01-01)
- Initial release
- API key authentication
- Date range filtering
- Rate limiting (10 req/min)
- Pagination support
- Multi-language documentation
