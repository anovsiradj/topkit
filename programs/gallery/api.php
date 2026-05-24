<?php

/**
 * Gallery API Handler
 * Supports: list, file, rename, delete operations
 */

// Supported media types
$SUPPORTED_TYPES = [
	'image' => ['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp'],
	'video' => ['mp4', 'webm', 'avi', 'mov', 'mkv']
];

/**
 * Helper: Detect media type
 */
function getMediaType($filename) {
	global $SUPPORTED_TYPES;
	$ext = strtolower(pathinfo($filename, PATHINFO_EXTENSION));
	foreach ($SUPPORTED_TYPES as $type => $exts) {
		if (in_array($ext, $exts)) return $type;
	}
	return null;
}

/**
 * Helper: Extract labels from file path
 * Example: images/nature/mountains/photo.jpg → ['images', 'nature', 'mountains']
 */
function getLabels($filepath, $baseFolder) {
	// Handle empty base folder
	if (empty($baseFolder) || !is_dir($baseFolder)) {
		return [];
	}
	
	$basePath = realpath($baseFolder);
	$fileDir = realpath(dirname($filepath));
	
	// If file is not within base folder, return empty labels
	if (strpos($fileDir, $basePath) !== 0) {
		return [];
	}
	
	$relative = str_replace($basePath . DIRECTORY_SEPARATOR, '', $fileDir);
	if ($relative === '.') return [];
	$parts = array_filter(explode(DIRECTORY_SEPARATOR, $relative));
	return array_values($parts);
}

/**
 * LIST: Get all media files with metadata
 */
if (isset($arguments['list'])) {
	// Handle empty root - return empty list
	if (empty($root) || !is_dir($root) || !is_readable($root)) {
		header('Content-Type: application/json');
		echo json_encode([
			'success' => true,
			'data' => [],
			'total' => 0,
			'message' => 'No valid root folder specified. Please enter a directory path.',
		]);
		exit;
	}

	$files = glob("{$root}/{*,*/*,*/*/*}", GLOB_BRACE);
	$files = array_filter($files, fn($file) => is_file($file) && is_readable($file));

	$index = 0;
	$files = array_map(function ($file) use (&$index, $root) {
		$type = getMediaType($file);
		if (!$type) return null;

		$index++;
		$path = realpath($file);
		$name = basename($path);
		$size = filesize($path);
		$stat = stat($path);
		$labels = getLabels($path, $root);

		$url = http_build_query(['file' => $path]);

		return [
			'id' => $index,
			'path' => $path,
			'name' => $name,
			'type' => $type,
			'size' => $size,
			'url' => "?{$url}",
			'labels' => $labels,
			'created_at' => $stat['ctime'] * 1000,      // milliseconds for JS
			'modified_at' => $stat['mtime'] * 1000,
		];
	}, $files);
	$files = array_filter($files);

	header('Content-Type: application/json');
	echo json_encode([
		'success' => true,
		'data' => array_values($files),
		'total' => count($files),
	]);
	exit;
}

/**
 * FILE: Serve media file
 */
if (isset($arguments['file'])) {
	$file = $arguments['file'];
	$public_name = basename($file);

	if (!file_exists($file) || !is_readable($file)) {
		header("HTTP/1.1 404 Not Found");
		echo json_encode(['success' => false, 'error' => 'File not found']);
		exit;
	}

	$type = getMediaType($file);
	if (!$type) {
		header("HTTP/1.1 403 Forbidden");
		echo json_encode(['success' => false, 'error' => 'Unsupported file type']);
		exit;
	}

	$finfo = finfo_open(FILEINFO_MIME_TYPE);
	$mime_type = finfo_file($finfo, $file);
	finfo_close($finfo);

	header("Content-Type: $mime_type");
	header("Content-Disposition: inline; filename=\"$public_name\"");
	header("Content-Length: " . filesize($file));
	header("Cache-Control: public, max-age=3600");

	readfile($file);
	exit;
}

/**
 * RENAME: Rename a file (preserves extension)
 */
if (isset($arguments['rename'])) {
	$oldPath = $arguments['rename'];
	$newName = $arguments['newname'] ?? null;

	if (!$newName) {
		header("HTTP/1.1 400 Bad Request");
		echo json_encode(['success' => false, 'error' => 'Missing newname parameter']);
		exit;
	}

	if (!file_exists($oldPath) || !is_writable(dirname($oldPath))) {
		header("HTTP/1.1 403 Forbidden");
		echo json_encode(['success' => false, 'error' => 'Cannot write to file']);
		exit;
	}

	// Extract base name and extension
	$oldName = basename($oldPath);
	$ext = pathinfo($oldName, PATHINFO_EXTENSION);
	$newBaseName = pathinfo($newName, PATHINFO_FILENAME);
	$finalName = $newBaseName . ($ext ? '.' . $ext : '');
	
	$newPath = dirname($oldPath) . DIRECTORY_SEPARATOR . $finalName;

	if (rename($oldPath, $newPath)) {
		header('Content-Type: application/json');
		echo json_encode([
			'success' => true,
			'oldPath' => $oldPath,
			'newPath' => $newPath,
			'newName' => $finalName,
		]);
	} else {
		header("HTTP/1.1 500 Internal Server Error");
		echo json_encode(['success' => false, 'error' => 'Rename failed']);
	}
	exit;
}

/**
 * DELETE: Delete a file
 */
if (isset($arguments['delete'])) {
	$path = $arguments['delete'];

	if (!file_exists($path) || !is_writable(dirname($path))) {
		header("HTTP/1.1 403 Forbidden");
		echo json_encode(['success' => false, 'error' => 'Cannot delete file']);
		exit;
	}

	if (unlink($path)) {
		header('Content-Type: application/json');
		echo json_encode([
			'success' => true,
			'deleted' => $path,
			'message' => 'File deleted successfully'
		]);
	} else {
		header("HTTP/1.1 500 Internal Server Error");
		echo json_encode(['success' => false, 'error' => 'Delete failed']);
	}
	exit;
}

/**
 * CHECKDIR: Check if a directory exists and is accessible
 */
if (isset($arguments['checkdir'])) {
	$path = $arguments['path'] ?? '';
	
	header('Content-Type: application/json');
	echo json_encode([
		'success' => true,
		'exists' => is_dir($path) && is_readable($path),
		'path' => $path,
	]);
	exit;
}
