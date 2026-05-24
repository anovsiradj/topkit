<?php

/**
 * Local Server Gallery
 * 
 * Usage:
 * php --server 0.0.0.0:2205 /topkit/gallery.php
 * 
 * Root folder must be specified via web interface using the root input field.
 * For debugging, defaults to D:\group if it exists.
 */

require __DIR__ . '/../vendor/autoload.php';

// Serve static files from gallery directory
$file = __DIR__ . '/gallery' . $_SERVER['SCRIPT_NAME'];
if (is_file($file) && is_readable($file)) {
	$mime = match (true) {
		str_ends_with($file, '.html') => 'text/html',
		str_ends_with($file, '.css') => 'text/css',
		str_ends_with($file, '.js') => 'text/javascript',
		default => 'text/plain',
	};
	header("Content-Type: {$mime}");
	readfile($file);
	exit;
}

// Get query parameters
$arguments = $_GET;

// Determine root folder - only from web interface GET parameter
$root = null;

// For debugging: use D:\group if it exists
$debugRoot = 'D:\group';
if (is_dir($debugRoot) && is_readable($debugRoot)) {
	$root = realpath($debugRoot);
}

// Override with GET parameter if provided and valid
if (isset($_GET['root']) && is_dir($_GET['root'])) {
	$root = realpath($_GET['root']);
}

// If no valid root found, set to empty string
if ($root === null) {
	$root = '';
}

$arguments['root'] = $root;

require __DIR__ . '/gallery/api.php';

require __DIR__ . '/gallery/web.php';
