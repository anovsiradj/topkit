<?php

declare(strict_types=1);

$prefix = getcwd();
$suffix = end($argv);
$file = realpath($prefix . DIRECTORY_SEPARATOR . $suffix);
if ($file === false) {
	echo sprintf('file %s tidak ditemukan!', $suffix), PHP_EOL;
	exit(1);
}
