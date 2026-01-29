<?php
// Define the directory containing images
$image_dir = 'images/';
$output_file = 'index.html';

// Get all image files from the directory
$files = glob($image_dir . '*.{jpg,jpeg,png,gif}', GLOB_BRACE);

if (empty($files)) {
    echo "No images found in the '$image_dir' directory.\n";
    exit;
}

// Start generating HTML content
$html = '<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>PHP CLI Image Gallery</title>
    <style>
        .gallery { display: flex; flex-wrap: wrap; gap: 10px; }
        .gallery img { width: 150px; height: 150px; object-fit: cover; border: 1px solid #ccc; }
    </style>
</head>
<body>
    <h1>My Image Gallery</h1>
    <div class="gallery">';

// Loop through files and add image tags
foreach ($files as $file) {
    $html .= '<img src="' . htmlspecialchars($file) . '" alt="' . htmlspecialchars(basename($file)) . '">';
}

// Close HTML tags
$html .= '</div></body></html>';

// Save the HTML content to a file
file_put_contents($output_file, $html);

echo "Gallery HTML file generated successfully: $output_file\n";
