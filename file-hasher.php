<?php
// $argumentsEchoExit = true;
$arguments = require __DIR__ . '/php/arguments.php';
$fileHasherAlgos ??= hash_algos();

if (empty($arguments)) {
	echo <<<'TXT'
		usage:
		php file-hasher.php {option}={value}

		options:
			file={file}: path to file to hash
			hash={hash}: algorithm to use for hashing
			list: list available hash algorithms
	TXT, PHP_EOL;
	exit;
}

if (isset($arguments['list'])) {
	echo implode(PHP_EOL, $fileHasherAlgos), PHP_EOL;
	exit;
}

if (isset($arguments['hash']) && !in_array($arguments['hash'], $fileHasherAlgos)) {
	echo "unknown hash: {$arguments['hash']}", PHP_EOL;
	exit;
}
if (isset($arguments['file']) && !is_file($arguments['file'])) {
	echo "unknown file: {$arguments['file']}", PHP_EOL;
	exit;
}
if (isset($arguments['file']) && isset($arguments['hash'])) {
	$fileHasherResult = hash_file($arguments['hash'], $arguments['file']);
	echo $fileHasherResult, PHP_EOL;
	exit;
}
