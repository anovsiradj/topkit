<?php

function flat_v0($input)
{
	$output = [];
	array_walk_recursive($input, function ($x) use (&$output) { $output[] = $x; });
	return $output;
}
function flat_v1($input)
{
	$output = [];
	array_walk_recursive($input, fn($e) => ($output[] = $e));
	return $output;
}

$sample = [
	'A',
	[1 => 'B'],
	[2 => [3 => 'C']],
];

echo json_encode(flat_v0($sample), JSON_PRETTY_PRINT), PHP_EOL;
echo json_encode(flat_v1($sample), JSON_PRETTY_PRINT), PHP_EOL;
