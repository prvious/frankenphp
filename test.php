<?php

declare(strict_types=1);

const NODE_MAJOR_VERSION = 26;
const PNPM_MAJOR_VERSION = 11;

// These were inherited from the official PHP ZTS image before source builds.
const BASELINE_EXTENSIONS = ['ctype', 'curl', 'dom', 'fileinfo', 'filter', 'iconv', 'json', 'mbstring', 'openssl', 'PDO', 'pdo_sqlite', 'Phar', 'posix', 'readline', 'session', 'SimpleXML', 'sodium', 'SPL', 'sqlite3', 'tokenizer', 'xmlreader', 'xmlwriter', 'zlib', 'Zend OPcache'];

const PRODUCTION_EXTENSIONS = [...BASELINE_EXTENSIONS, 'mysqli', 'pdo_mysql', 'pgsql', 'pdo_pgsql', 'bcmath', 'gd', 'imagick', 'imap', 'pcntl', 'zip', 'intl', 'exif', 'ftp', 'xml', 'pdo_sqlsrv', 'sqlsrv', 'sockets'];

const DEV_ONLY_EXTENSIONS = ['xdebug'];

const DEV_EXTENSIONS = [
    ...PRODUCTION_EXTENSIONS,
    ...DEV_ONLY_EXTENSIONS,
];

const PRODUCTION_BINARIES = ['php', 'frankenphp', 'composer', 'node', 'pnpm', 'psql', 'mysql', 'supervisord', 'jpegoptim', 'optipng', 'pngquant', 'gifsicle', 'ffmpeg', 'svgo', 'avifenc', 'zsh'];

const DEV_ONLY_BINARIES = ['gh', 'eza', 'htop', 'nano', 'fzf', 'zoxide', 'starship', 'opencode'];

const DEV_BINARIES = [
    ...PRODUCTION_BINARIES,
    ...DEV_ONLY_BINARIES,
];

const PRODUCTION_BINARY_CHECKS = [
    'composer' => 'composer --version',
    'psql' => 'psql --version',
    'mysql' => 'mysql --version',
    'supervisord' => 'supervisord --version',
    'jpegoptim' => 'jpegoptim --version',
    'optipng' => 'optipng -version',
    'pngquant' => 'pngquant --version',
    'gifsicle' => 'gifsicle --version',
    'svgo' => 'svgo --version',
    'avifenc' => 'avifenc --version',
    'zsh' => 'zsh --version',
];

const DEV_ONLY_BINARY_CHECKS = [
    'gh' => 'gh --version',
    'eza' => 'eza --version',
    'htop' => 'htop --version',
    'nano' => 'nano --version',
    'fzf' => 'fzf --version',
    'zoxide' => 'zoxide --version',
    'starship' => 'starship --version',
    'opencode' => 'opencode --version',
];

class Colors
{
    // Control codes
    public const RESET = "\033[0m";
    public const BOLD = "\033[1m";
    public const DIM = "\033[2m";

    // Standard colors
    public const RED = "\033[31m";
    public const GREEN = "\033[32m";
    public const YELLOW = "\033[33m";
    public const BLUE = "\033[34m";
    public const MAGENTA = "\033[35m";
    public const CYAN = "\033[36m";
    public const WHITE = "\033[37m";

    // Bright colors
    public const BRIGHT_RED = "\033[91m";
    public const BRIGHT_GREEN = "\033[92m";
    public const BRIGHT_YELLOW = "\033[93m";
    public const BRIGHT_BLUE = "\033[94m";
    public const BRIGHT_MAGENTA = "\033[95m";
    public const BRIGHT_CYAN = "\033[96m";

    // Background colors
    public const BG_RED = "\033[41m";
    public const BG_GREEN = "\033[42m";
}

class Runner
{
    private array $missingExtensions = [];
    private array $missingBinaries = [];
    private array $missingSanity = [];

    public function __construct(public string $environment = 'production', private int $failures = 0) {}

    public function printHeader(string $emoji, string $title): void
    {
        $envText = paint("[{$this->environment}]", Colors::BOLD . Colors::MAGENTA);
        $header = paint("\n{$emoji} {$title}...", Colors::BOLD . Colors::BRIGHT_BLUE);

        echo "{$envText} {$header}\n";
    }

    public function check(string $name, bool $passed, ?string $hint = null): void
    {
        if ($passed) {
            $statusText = paint("[OK]", Colors::BOLD . Colors::BRIGHT_GREEN);
            $nameText = paint($name, Colors::CYAN);
            echo "{$statusText} {$nameText}\n";
            return;
        }

        $statusText = paint("[FAIL]", Colors::BOLD . Colors::BRIGHT_RED);
        $nameText = paint($name, Colors::YELLOW);
        $hintText = $hint ? paint(" - {$hint}", Colors::DIM . Colors::WHITE) : "";
        echo "{$statusText} {$nameText}{$hintText}\n";

        $this->failures++;

        if (str_starts_with($name, 'extension:')) {
            $this->missingExtensions[] = substr($name, 10);
        } elseif (str_starts_with($name, 'binary:')) {
            $this->missingBinaries[] = substr($name, 7);
        } else {
            $this->missingSanity[] = $name;
        }
    }

    public function commandExists(string $command): bool
    {
        $output = @shell_exec('command -v ' . escapeshellarg($command) . ' 2>/dev/null');

        if ($output === null) {
            $output = @shell_exec('which ' . escapeshellarg($command) . ' 2>/dev/null');
        }

        return is_string($output) && trim($output) !== '';
    }

    public function commandSucceeds(string $command): bool
    {
        $output = [];
        $exitCode = 1;

        @exec("{$command} >/dev/null 2>&1", $output, $exitCode);

        return $exitCode === 0;
    }

    public function finish(): never
    {
        if ($this->failures > 0) {
            echo "\n";

            if (!empty($this->missingExtensions)) {
                $extList = paint(implode(', ', $this->missingExtensions), Colors::YELLOW);
                echo paint("Missing extensions: ", Colors::BOLD . Colors::RED) . "[{$extList}]\n";
            }

            if (!empty($this->missingBinaries)) {
                $binList = paint(implode(', ', $this->missingBinaries), Colors::YELLOW);
                echo paint("Missing binaries: ", Colors::BOLD . Colors::RED) . "[{$binList}]\n";
            }

            if (!empty($this->missingSanity)) {
                $sanityList = paint(implode(', ', $this->missingSanity), Colors::YELLOW);
                echo paint("Failed sanity checks: ", Colors::BOLD . Colors::RED) . "[{$sanityList}]\n";
            }

            $message = "❌ Total failures: {$this->failures}";
            echo "\n" . paint($message, Colors::BOLD . Colors::BG_RED . Colors::WHITE) . "\n";
            exit(1);
        }

        echo "\n" . paint("🎉 All checks passed!", Colors::BOLD . Colors::BRIGHT_GREEN) . "\n";
        exit(0);
    }
}

function paint(string $text, string $color): string
{
    if (!posix_isatty(STDOUT) && getenv('FORCE_COLOR') !== '1') {
        return $text;
    }

    return $color . $text . Colors::RESET;
}

function extensions(Runner $runner): void
{
    $runner->printHeader("🔍", "Checking PHP Extensions");

    $extensions = $runner->environment === 'dev' ? DEV_EXTENSIONS : PRODUCTION_EXTENSIONS;

    foreach ($extensions as $extension) {
        $runner->check("extension:{$extension}", extension_loaded($extension));
    }

    if ($runner->environment === 'production') {
        foreach (DEV_ONLY_EXTENSIONS as $extension) {
            $runner->check(
                "forbidden extension:{$extension}",
                !extension_loaded($extension),
                'must not be present in production'
            );
        }
    }
}

function binaries(Runner $runner): void
{
    $runner->printHeader("🛠️", "Checking CLI Tools & Binaries");

    $binaries = $runner->environment === 'dev' ? DEV_BINARIES : PRODUCTION_BINARIES;

    foreach ($binaries as $binary) {
        $runner->check("binary:{$binary}", $runner->commandExists($binary));
    }

    $binaryChecks = $runner->environment === 'dev'
        ? [...PRODUCTION_BINARY_CHECKS, ...DEV_ONLY_BINARY_CHECKS]
        : PRODUCTION_BINARY_CHECKS;

    foreach ($binaryChecks as $binary => $command) {
        $runner->check(
            "binary executable:{$binary}",
            $runner->commandSucceeds($command),
            "command failed: {$command}"
        );
    }

    if ($runner->environment === 'production') {
        foreach (DEV_ONLY_BINARIES as $binary) {
            $runner->check(
                "forbidden binary:{$binary}",
                !$runner->commandExists($binary),
                'must not be present in production'
            );
        }
    }
}

/** Verify both SAPIs, not just the PHP CLI used to run this test. */
function sourceRuntime(Runner $runner): void
{
    $runner->printHeader("🔨", "Checking Source-built Runtime");

    $expectedPhp = getenv('EXPECTED_PHP_VERSION') ?: getenv('PHP_VERSION') ?: '';
    $expectedFrankenphp = ltrim(getenv('EXPECTED_FRANKENPHP_VERSION') ?: getenv('FRANKENPHP_VERSION') ?: '', 'v');
    $runner->check('PHP release metadata', preg_match('/^8\.[0-9]+\.[0-9]+$/D', $expectedPhp) === 1);
    $runner->check('PHP CLI exact release', PHP_VERSION === $expectedPhp, "expected {$expectedPhp}, got " . PHP_VERSION);
    $runner->check('PHP CLI thread safety', PHP_ZTS === true);
    $runner->check('FrankenPHP release metadata', preg_match('/^[0-9]+\.[0-9]+\.[0-9]+$/D', $expectedFrankenphp) === 1);

    $version = trim(@shell_exec('frankenphp version 2>&1') ?? '');
    $runner->check(
        'FrankenPHP exact release',
        $expectedFrankenphp !== '' && preg_match('/\bFrankenPHP v?' . preg_quote($expectedFrankenphp, '/') . '(?:\s|$)/', $version) === 1,
        "expected {$expectedFrankenphp}, got {$version}"
    );

    // Reserve a local ephemeral port instead of assuming a port is unused.
    $socket = @stream_socket_server('tcp://127.0.0.1:0', $errorCode, $errorMessage);
    $runner->check('HTTP smoke-test port', is_resource($socket), $errorMessage);
    if (!is_resource($socket)) {
        return;
    }
    $address = stream_socket_get_name($socket, false);
    fclose($socket);

    $directory = sys_get_temp_dir() . '/frankenphp-smoke-' . bin2hex(random_bytes(8));
    mkdir($directory, 0700);
    $process = null;
    try {
        file_put_contents($directory . '/index.php', '<?php header("Content-Type: application/json"); echo json_encode(["version" => PHP_VERSION, "zts" => PHP_ZTS, "sapi" => PHP_SAPI, "extensions" => array_merge(get_loaded_extensions(), get_loaded_extensions(true))]);');
        file_put_contents($directory . '/Caddyfile', "{\n    admin off\n    auto_https off\n    frankenphp {\n        num_threads 2\n    }\n}\nhttp://{$address} {\n    root * {$directory}\n    php_server\n}\n");
        $process = proc_open(
            ['frankenphp', 'run', '--config', $directory . '/Caddyfile', '--adapter', 'caddyfile'],
            [0 => ['file', '/dev/null', 'r'], 1 => ['file', $directory . '/server.log', 'a'], 2 => ['file', $directory . '/server.log', 'a']],
            $pipes
        );
        $runner->check('FrankenPHP starts as runtime user', is_resource($process));
        if (!is_resource($process)) {
            return;
        }

        $response = false;
        $context = stream_context_create(['http' => ['timeout' => 1]]);
        $deadline = microtime(true) + 20;
        do {
            $response = @file_get_contents("http://{$address}/index.php", false, $context);
            if ($response !== false || !proc_get_status($process)['running']) {
                break;
            }
            usleep(100000);
        } while (microtime(true) < $deadline);

        $payload = is_string($response) ? json_decode($response, true) : null;
        $runner->check('FrankenPHP serves PHP over HTTP', is_array($payload), (string) file_get_contents($directory . '/server.log'));
        if (!is_array($payload)) {
            return;
        }
        $runner->check('embedded PHP exact release', ($payload['version'] ?? null) === $expectedPhp);
        $runner->check('embedded PHP thread safety', ($payload['zts'] ?? null) === true);
        $runner->check('embedded PHP SAPI', ($payload['sapi'] ?? null) === 'frankenphp');
        $loaded = array_map('strtolower', $payload['extensions'] ?? []);
        $required = $runner->environment === 'dev' ? DEV_EXTENSIONS : PRODUCTION_EXTENSIONS;
        foreach ($required as $extension) {
            $runner->check("embedded extension:{$extension}", in_array(strtolower($extension), $loaded, true));
        }
        if ($runner->environment === 'production') {
            $runner->check('embedded PHP has no Xdebug', !in_array('xdebug', $loaded, true));
        }
    } finally {
        if (is_resource($process)) {
            proc_terminate($process);
            $deadline = microtime(true) + 3;
            while (proc_get_status($process)['running'] && microtime(true) < $deadline) {
                usleep(100000);
            }
            if (proc_get_status($process)['running']) {
                proc_terminate($process, 9);
            }
            proc_close($process);
        }
        foreach (glob($directory . '/*') as $file) {
            unlink($file);
        }
        rmdir($directory);
    }
}

function sanity(Runner $runner): void
{
    $runner->printHeader("✅", "Running Sanity Checks");

    $modules = @shell_exec('php -m 2>/dev/null');
    $runner->check('php-cli works', is_string($modules) && trim($modules) !== '');

    $nodeVersion = trim(@shell_exec('node --version 2>/dev/null') ?? '');
    $runner->check(
        'node major version',
        str_starts_with($nodeVersion, 'v' . NODE_MAJOR_VERSION . '.'),
        'expected v' . NODE_MAJOR_VERSION . ".x, got {$nodeVersion}"
    );

    $pnpmVersion = trim(@shell_exec('pnpm --version 2>/dev/null') ?? '');
    $runner->check(
        'pnpm major version',
        str_starts_with($pnpmVersion, PNPM_MAJOR_VERSION . '.'),
        'expected ' . PNPM_MAJOR_VERSION . ".x, got {$pnpmVersion}"
    );

    $home = getenv('HOME') ?: '/home/deploy';
    $pnpmStorePath = trim(@shell_exec('pnpm store path 2>/dev/null') ?? '');
    $expectedPath = "{$home}/.pnpm-store";
    $runner->check(
        'pnpm store path',
        str_starts_with($pnpmStorePath, $expectedPath),
        "expected {$expectedPath}, got {$pnpmStorePath}"
    );

    $psyshPath = "{$home}/.config/psysh";
    $runner->check(
        'psysh config directory',
        is_dir($psyshPath) && is_writable($psyshPath),
        "expected writable directory {$psyshPath}"
    );

    $appProbe = @tempnam('/app', 'frankenphp-test-');
    $runner->check(
        'app directory writable',
        is_string($appProbe),
        'expected the runtime user to write to /app'
    );

    if (is_string($appProbe)) {
        @unlink($appProbe);
    }
}

/**
 * The production PHP defaults from conf.d/10-production.ini, as the prod
 * stage's environment sets them.
 */
const PRODUCTION_INI = [
    'opcache.enable' => '1',
    'opcache.memory_consumption' => '256',
    'opcache.interned_strings_buffer' => '32',
    'opcache.max_accelerated_files' => '32531',
    'opcache.validate_timestamps' => '0',
    'realpath_cache_ttl' => '600',
    'session.upload_progress.enabled' => '0',
];

function productionSettings(Runner $runner): void
{
    $runner->printHeader("⚙️", "Checking Production PHP Settings");

    foreach (PRODUCTION_INI as $setting => $expected) {
        $actual = (string) ini_get($setting);
        $runner->check("ini:{$setting}", $actual === $expected, "expected {$expected}, got {$actual}");
    }

    $runner->check('ini:expose_php', !ini_get('expose_php'), 'expected Off');

    // An app tunes a default by setting the variable on its container.
    $override = trim(@shell_exec('PHP_OPCACHE_MEMORY_CONSUMPTION=384 php -r ' . escapeshellarg('echo ini_get("opcache.memory_consumption");') . ' 2>/dev/null') ?? '');
    $runner->check('ini overridable by environment', $override === '384', "expected 384, got {$override}");

    // The runtime user serves on port 80, which takes this file capability.
    $capabilities = (string) @shell_exec('getcap /usr/local/bin/frankenphp 2>/dev/null');
    $runner->check('frankenphp may bind port 80', str_contains($capabilities, 'cap_net_bind_service'), "got: {$capabilities}");
}

function go(): never
{
    global $argv;

    $environment = $argv[1] ?? getenv('ENV') ?? 'production';

    if (!in_array($environment, ['production', 'dev'], true)) {
        echo "Usage: php test.php [production|dev]\n";
        echo "Or set ENV environment variable\n";
        exit(1);
    }

    $runner = new Runner($environment);

    extensions($runner);
    binaries($runner);
    sanity($runner);
    sourceRuntime($runner);

    if ($environment === 'production') {
        productionSettings($runner);
    }

    $runner->finish();
}

go();
