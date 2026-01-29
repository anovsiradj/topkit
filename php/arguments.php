<?php

$argumentsEchoExit ??= false;

$argv ??= [];
parse_str(implode('&', array_slice($argv, 1)), $arguments);

if($argumentsEchoExit) {
	echo var_export($arguments, true), PHP_EOL;
	exit;
}

return $arguments;
