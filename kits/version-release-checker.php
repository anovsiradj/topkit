#!/usr/bin/env php
<?php

/**
* @version 20191030,20201207144845
*/

if (! defined('PHP_EOL')) define('PHP_EOL', '\r\n');
if (! defined('PHP_VERSION_ID')) {
	$version = explode('.', PHP_VERSION);
	define('PHP_VERSION_ID', ($version[0] * 10000 + $version[1] * 100 + $version[2]));
}
if (! function_exists('http_build_query')) {
	function http_build_query($array) {
		$i = 0;
		$string = '';
		foreach ($array as $k => $v) {
			if ($i > 0) $string .= '&';
			$string .= $k;
			if (! empty($v)) $string .= '='.urlencode($v);
			$i++;
		}
	}
}

function e() {
	echo implode('', func_get_args()), PHP_EOL;
}

$mine_version = PHP_VERSION;
$mine_version_semver = explode('.', $mine_version);
$mine_version_semver = array(
	'MAJOR' => $mine_version_semver[0],
	'MINOR' => $mine_version_semver[1],
	'PATCH' => $mine_version_semver[2],
);
$mine_version_id = PHP_VERSION_ID;

$href_prefix = 'https://www.php.net/releases/index.php';
$href_params = array(
	// 'json' => PHP_EOL,
	// 'version' => $mine_version_semver['MAJOR'],
	'serialize' => PHP_EOL,
);

$entrypoint = $href_prefix.'?'.http_build_query($href_params);
e(PHP_EOL, 'Fetching... ', $entrypoint, PHP_EOL);

$result = file_get_contents($entrypoint);
$result = unserialize($result);
$major_latest = $result[$mine_version_semver['MAJOR']];
$newest_latest = $result[max(array_keys($result))];

e("${mine_version} is your PHP version.");
e("${major_latest['version']} (${major_latest['date']}) is latest PHP with same major version as your.");
e("${newest_latest['version']} (${newest_latest['date']}) is newest PHP release.");
e();
