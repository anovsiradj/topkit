<?php

/**
 * usage1:
 * cd /gallery/folder && php --server 0.0.0.0:2205 /topkit/gallery.php
 * 
 * usage2:
 * php --server 0.0.0.0:2205 /topkit/gallery.php "folder=/gallery/folder"
 */

$arguments = require __DIR__ . '/../php/arguments.php';
$arguments = array_merge($arguments, $_GET);

$folder = getcwd();
$arguments['folder'] ??= $folder;
$folder = $arguments['folder'];

require __DIR__ . '/gallery/api.php';

require __DIR__ . '/gallery/web.php';
