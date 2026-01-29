<?php

if (isset($arguments['list'])) {
	$files = glob("{$folder}/{*,*/*,*/*/*}", GLOB_BRACE);
	$files = array_filter($files, fn($file) => (is_file($file) * is_readable($file)));

	$index = 0;
	$files = array_map(function ($file) use (&$index) {
		$index++;

		$path = realpath($file);
		$name = basename($path);

		// SLOW
		// $mime = explode('/', mime_content_type($file));
		// $mime = current($mime);
		$mime = null;
		if (preg_match('/\.(png|jpe?g|webp)$/', $name) === 1) {
			$mime = 'image';
		}
		if (preg_match('/(mp4|webm)$/', $name) === 1) {
			$mime = 'video';
		}
		if (empty($mime)) {
			return null;
		}

		// SLOW
		// $size = filesize($path); 
		$size = strlen($path);

		$url = http_build_query(['file' => $path]);
		$url = "?{$url}";

		return [
			'id' => $index,
			'url' => $url,
			'name' => $name,
			'type' => $mime,
			'size' => $size,
		];
	}, $files);
	$files = array_filter($files);

	// var_dump($files);
	header('Content-Type: text/json');
	echo json_encode(array_values($files));
	exit;
}

if (isset($arguments['file'])) {
	$file = $arguments['file'];
	$public_name = basename($file);

	// Ensure the file exists and is readable
	if (!file_exists($file) || !is_readable($file)) {
		header("HTTP/1.1 404 Not Found");
		exit;
	}

	// Get the file's MIME type
	$finfo = finfo_open(FILEINFO_MIME_TYPE);
	$mime_type = finfo_file($finfo, $file);
	finfo_close($finfo);

	// Set the appropriate headers
	header("Content-Type: $mime_type");
	header("Content-Disposition: inline; filename=\"$public_name\"");
	header("Content-Length: " . filesize($file));
	header("Content-Transfer-Encoding: binary");
	header("Cache-Control: must-revalidate, post-check=0, pre-check=0");
	header("Pragma: public");

	// Output the file content
	readfile($file);
	exit;
}
