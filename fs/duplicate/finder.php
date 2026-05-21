<?php

function findDuplicateFiles($dir) {
    $filesByHash = [];
    $duplicates = [];

    // Use RecursiveDirectoryIterator for handling subdirectories efficiently
    $iterator = new RecursiveIteratorIterator(
        new RecursiveDirectoryIterator($dir)
    );

    foreach ($iterator as $file) {
        // Skip directories and system files (. and ..)
        if ($file->isDir() || $file->getFilename() === '.' || $file->getFilename() === '..') {
            continue;
        }

        $filePath = $file->getRealPath();
        // Calculate MD5 hash of the file content
        $hash = md5_file($filePath);

        // Group files by their hash
        $filesByHash[$hash][] = $filePath;
    }

    // Filter for hashes that have more than one entry
    foreach ($filesByHash as $hash => $files) {
        if (count($files) > 1) {
            $duplicates[$hash] = $files;
        }
    }

    return $duplicates;
}

$cwd = getcwd();


// Specify the directory to scan
$directoryToScan = $cwd; // Scans the current directory and its subdirectories

$duplicateGroups = findDuplicateFiles($directoryToScan);

if (!empty($duplicateGroups)) {
    echo "Found duplicate file groups:\n";
    foreach ($duplicateGroups as $hash => $files) {
        echo "--- Hash: $hash ---\n";
        foreach ($files as $file) {
            echo " - $file\n";
        }
    }
} else {
    echo "No duplicate files found in the specified directory.\n";
}
