<?php

$pwd = 'pass';
if (isset($argv) && array_key_exists(1, $argv)) {
	$pwd = $argv[1];
}

$pwd_options['cost'] = rand(4,12);

$pwd_result = password_hash($pwd, PASSWORD_BCRYPT, $pwd_options);

echo PHP_EOL, $pwd, PHP_EOL, $pwd_result, PHP_EOL, PHP_EOL;
