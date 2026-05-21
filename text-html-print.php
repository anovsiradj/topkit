<?php

// $root = __DIR__ . '/sigap-forge/jeemce';
// $root = 'D:\Projects\JSProjects\sigap-front/pages';
// $root = 'D:\Projects\SIGAP_KLHK\sigap-admin\_mod\modules/administrator';
$files = glob($root . '{,/**,/**/**,/**/**/**}/*', GLOB_BRACE | GLOB_NOCHECK);
$files = array_filter($files, fn($file) => is_file($file) && !is_dir($file));

// var_dump($files);
// die;

// dd($files);

?>

<?php foreach ($files as $file) {
	$name = str_replace($root, '', $file);
	$name = trim($name, '/');
?>

	<div style="font-weight: bold; font-family: monospace; border-bottom: 1px solid black;">
		<?= $name ?>
	</div>

	<div style="margin-bottom: 10px;">
		<?= highlight_file($file, true) ?>
	</div>
<?php } ?>