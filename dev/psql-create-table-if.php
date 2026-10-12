<?php
/*
	https://stackoverflow.com/a/3004080
*/

declare(strict_types=1);

require __DIR__ . '/psql-main.php';

$params = [];

var_dump(get_defined_vars());

$reading = fopen('myfile', 'r');
$writing = fopen('myfile.tmp', 'w');
$replaced = false;

while (!feof($reading)) {
	$line = fgets($reading);
	if (stristr($line, 'certain word')) {
		$line = "replacement line!\n";
		$replaced = true;
	}
	fputs($writing, $line);
}
fclose($reading);
fclose($writing);
// might as well not overwrite the file if we didn't replace anything
if ($replaced) {
	rename('myfile.tmp', 'myfile');
} else {
	unlink('myfile.tmp');
}
