# AI Development Guidelines

# Local Server Gallery

A Gallery App inspired by Photos App on Windows 11

## Overview
A lightweight, self-contained gallery application for browsing images and videos on a local server. The app extracts labels from directory structure and provides filtering, sorting, and media viewing capabilities.

## Core Concepts

### Media Viewer
- Supports images (PNG, JPG, JPEG, WEBP, GIF, BMP) and videos (MP4, WEBM, AVI, MOV, MKV)
- Image zoom with drag-to-pan functionality when zoomed in
- Rotation controls (90° increments)
- Video playback with controls
- **Video autoplay**: Videos automatically start playing when opened
- **Video loop behavior**: 
  - In normal mode: videos autoplay and loop continuously
  - In slideshow mode: videos autoplay but don't loop, proceed to next file after ending
- File info modal showing properties (name, type, size, date, labels)
- Fullscreen slideshow with HTML5 Fullscreen API
- Auto-play slideshow (3-second delay for images, continue after video ends)

### Labels System
- **Flat labels** extracted from relative file paths
- Example: `images/nature/mountains/photo.jpg` → labels: `["images", "nature", "mountains"]`
- labels visualization as **Tags cloud** in sidebar
- labels sorted by file count (descending)
- display type filter as badge with items count
- display label filter as badge with items count
- Interactive filtering - click tags to filter files

### Grid Layout
- File cards showing thumbnail and filename
- File cards with hover effects and visual feedback
- Thumbnail display with lazy loading (`loading="lazy"`)

### Filtering & Sorting
- **Type filters**: All, type:image only, type:video only
- **Label filters**: Multiple label selection (AND logic)
- **Search**: File name search
- **Sorting**: By name, type, size, created date, modified date

### Keyboard Shortcuts
- `←/→` or `↑/↓` - Navigate between files in viewer
- `ESC` - Close media viewer
- `F2` - Rename current file
- `DEL` - Delete current file
- `+`/`-` - Zoom in/out (images only)
- `R` - Rotate image (90° clockwise)
- `I` - Show file info
- `?` - Toggle keyboard shortcuts hint
- `Space` - Play/Pause slideshow
- `F` - Toggle fullscreen mode

## API Endpoints

### GET `?list=/path/to/root/dir`
Returns JSON array of all media files with metadata:
- `id` - Sequential index
- `path` - Absolute file path
- `name` - File name
- `mime` - mime type
- `type` - "image" or "video"
- `size` - File size in bytes
- `url` - Direct file URL
- `labels` - Array of path-based labels
- `created_at` - in datetime
- `updated_at` - alias for `modified_at` in datetime

### GET `?file=/path/to/file`
Serves the media file with appropriate Content-Type header.

### POST `?rename=/path/to/file&newname=NewName`
Renames a file while preserving its extension.

### POST `?delete=/path/to/file`
Deletes a file from the filesystem.

## Usage

### Starting the Server
```bash
php --server 0.0.0.0:2205 /topkit/gallery.php
```

### Setting Root Folder
The root folder must be specified via the web interface:
1. Open the gallery in your browser
2. Enter a directory path in the root folder input field in the header
3. Click the change button or press Enter
4. The gallery will load files from the specified directory

### Features
1. **Browse** - Grid view of all media files
2. **Filter** - By type (image/video) and labels
3. **Search** - File name search
4. **Sort** - Multiple sorting options
5. **View** - Full-screen media viewer with controls
6. **Slideshow** - Auto-play slideshow with configurable timing
7. **Fullscreen** - HTML5 Fullscreen API support
8. **Manage** - Rename and delete files
9. **Keyboard** - Full keyboard navigation support

## Design Principles
- **Separate concerns**: HTML, CSS, and JavaScript in separate files
- **Desktop-focused**: Optimized for desktop use on local server
- **Performance**: Lazy loading, efficient filtering, minimal dependencies

## Dependencies
- Bootstrap v5
- Bootstrap Icons v1
- jQuery v4
- PHP v7 or latest

#### Usage:
1. Start server: `php --server 0.0.0.0:2205 /topkit/gallery.php`
2. Open gallery in browser
3. Enter directory path in root folder input field
4. Click change button or press Enter
5. Gallery checks directory and loads files if valid
