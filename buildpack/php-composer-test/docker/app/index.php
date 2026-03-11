<?php
require __DIR__ . '/vendor/autoload.php';

use Monolog\Logger;
use Monolog\Handler\StreamHandler;

$log = new Logger('e2e-test');
$log->pushHandler(new StreamHandler('php://stdout', Logger::INFO));
$log->info('Composer proxy E2E test — build succeeded!');

echo "Composer proxy E2E test — build succeeded!\n";
echo "  monolog version: " . \Composer\InstalledVersions::getVersion('monolog/monolog') . "\n";
