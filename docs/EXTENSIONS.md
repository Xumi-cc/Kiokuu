# KioKuu Extension System

Extensions allow users to add custom music sources to KioKuu. Extensions are JSON configuration files that define how to fetch and download music from various APIs.

## Overview

The extension system uses a **declarative JSON format** - no coding required! You define API endpoints and response mappings, and KioKuu handles the rest.

## Quick Start

1. Go to **Settings → Extensions**
2. Click **"Download Sample"** to get a template
3. Edit the JSON file for your source
4. Click **"Import"** to add it to the app

## Extension Structure

```json
{
  "id": "example-source",
  "name": "Example Music Source",
  "description": "Downloads music from example.com",
  "version": "1.0.0",
  "author": "Your Name",
  "type": "downloader",
  
  "domains": ["example.com", "api.example.com"],
  "updateUrl": "https://example.com/extension.json",
  
  "headers": {
    "User-Agent": "KioKuu/1.0"
  },
  
  "download": { ... }
}
```

### Required Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Unique identifier (lowercase, dashes) |
| `name` | string | Display name |
| `version` | string | Semantic version (e.g., "1.0.0") |
| `domains` | string[] | Supported domain names |

### Optional Fields

| Field | Type | Description |
|-------|------|-------------|
| `description` | string | Brief description |
| `author` | string | Author name |
| `updateUrl` | string | URL to fetch latest version for auto-updates |
| `homepage` | string | URL for more info |
| `icon` | string | URL to extension icon |
| `type` | string | "scraper", "downloader", or "full" |
| `headers` | object | Default HTTP headers |

## Download Configuration

The `download` section defines how to get download URLs.

### Basic JSON API

```json
"download": {
  "url": "https://api.example.com/download/{id}",
  "method": "GET",
  "responseType": "json",
  "urlPath": "data.download_url"
}
```

### With Headers

```json
"download": {
  "url": "https://api.example.com/download/{id}",
  "headers": {
    "Authorization": "Bearer TOKEN",
    "Accept": "application/json"
  },
  "responseType": "json",
  "urlPath": "url"
}
```

### URL Template Variables

| Variable | Description |
|----------|-------------|
| `{id}` | Track ID |
| `{isrc}` | ISRC code (if available) |

## Advanced Features

### Mirror Rotation

For APIs with multiple mirrors/servers:

```json
"download": {
  "mirrors": ["api1.example.com", "api2.example.com", "api3.example.com"],
  "url": "https://{mirror}/download/{id}",
  "responseType": "json",
  "urlPath": "url"
}
```

### Dynamic Mirrors from URL

Fetch mirrors from a remote source:

```json
"download": {
  "mirrorsUrl": "https://example.com/mirrors.json",
  "mirrorsPath": "servers.active",
  "url": "https://{mirror}/download/{id}",
  "responseType": "json",
  "urlPath": "url"
}
```

### Manifest Decoding

For APIs that return Base64-encoded JSON:

```json
"download": {
  "url": "https://api.example.com/manifest/{id}",
  "responseType": "json",
  "manifestDecode": {
    "path": "data.manifest",
    "encoding": "base64",
    "format": "json"
  },
  "urlPath": "streams.0.url"
}
```

### Async Polling

For APIs that return a task ID and require polling:

```json
"download": {
  "url": "https://api.example.com/submit",
  "method": "POST",
  "body": {
    "track_id": "{id}"
  },
  "responseType": "json",
  "polling": {
    "taskIdPath": "task_id",
    "statusUrl": "https://api.example.com/status/{taskId}",
    "statusPath": "status",
    "completedValue": "done",
    "resultPath": "result.url",
    "interval": 2000,
    "maxAttempts": 30
  }
}
```

### Audio Metadata Extraction

Extract quality info from API response:

```json
"download": {
  "url": "https://api.example.com/download/{id}",
  "responseType": "json",
  "urlPath": "url",
  "metadata": {
    "format": "format",
    "codec": "codec",
    "bitDepth": "bit_depth",
    "sampleRate": "sample_rate",
    "quality": "quality_label"
  }
}
```

## Update System

Extensions can auto-update when you provide an `updateUrl`:

```json
{
  "id": "my-extension",
  "name": "My Extension",
  "version": "1.0.0",
  "updateUrl": "https://example.com/my-extension.json",
  ...
}
```

When you release a new version:
1. Update the `version` field in your hosted JSON
2. Users click "Check Updates" in the app
3. A warning indicator appears if updates are available
4. Users click "Update" to get the latest version

## Examples

### Simple JSON API

```json
{
  "id": "simple-api",
  "name": "Simple API",
  "version": "1.0.0",
  "author": "Developer",
  "domains": ["api.example.com"],
  
  "download": {
    "url": "https://api.example.com/track/{id}",
    "responseType": "json",
    "urlPath": "download_url"
  }
}
```

### Multi-Mirror API

```json
{
  "id": "mirror-api",
  "name": "Mirror API",
  "version": "1.0.0",
  "author": "Developer",
  "domains": ["example.com"],
  
  "download": {
    "mirrorsUrl": "https://example.com/api/mirrors",
    "mirrorsPath": "mirrors",
    "url": "https://{mirror}/dl/{id}",
    "responseType": "json",
    "urlPath": "data.url",
    "metadata": {
      "format": "data.format",
      "quality": "data.quality"
    }
  }
}
```

### Async Polling API

```json
{
  "id": "async-api",
  "name": "Async API",
  "version": "1.0.0",
  "author": "Developer",
  "domains": ["slowapi.example.com"],
  
  "download": {
    "url": "https://slowapi.example.com/request",
    "method": "POST",
    "body": {
      "id": "{id}",
      "format": "flac"
    },
    "responseType": "json",
    "polling": {
      "taskIdPath": "job_id",
      "statusUrl": "https://slowapi.example.com/status/{taskId}",
      "statusPath": "state",
      "completedValue": "completed",
      "resultPath": "download_link",
      "interval": 3000,
      "maxAttempts": 20
    }
  }
}
```

## Testing Extensions

1. Import your extension via **Settings → Extensions → Import**
2. Go to the upload screen and enter a track URL
3. Your extension should appear as an available source
4. Check if the download URL is fetched correctly

## Troubleshooting

### "No extensions installed"
- Import an extension JSON file first

### "Failed to get download URL"
- Check your API endpoint URL
- Verify the `urlPath` matches the JSON response structure
- Try the API in a browser or Postman first

### "HTTP 403 / 401"
- The API may require authentication
- Add appropriate headers in the `headers` section

### "Mirror not responding"
- If using mirrors, some may be down
- The app will automatically try the next mirror

### "Invalid JSON"
- Validate your JSON at https://jsonlint.com/
- Check for trailing commas (not allowed in JSON)
- Use `_comment` fields for documentation (they're ignored)

## Security Notes

- Extensions can only make HTTP requests
- Extensions cannot access local files or other app data
- All network requests go through the app's HTTP client

## Sharing Extensions

Extensions are just JSON files - share them however you like:
- GitHub gists
- Pastebin
- Discord servers
- Direct file sharing

**Remember:** You are responsible for the extensions you use. Only import extensions from sources you trust.
