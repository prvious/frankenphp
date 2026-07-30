<?php

declare(strict_types=1);

const NODE_MAJOR_VERSION = 26;
const PNPM_MAJOR_VERSION = 11;

const PRODUCTION_EXTENSIONS = ['mysqli', 'pdo_mysql', 'pgsql', 'pdo_pgsql', 'bcmath', 'gd', 'imagick', 'imap', 'pcntl', 'zip', 'intl', 'exif', 'ftp', 'xml', 'pdo_sqlsrv', 'sqlsrv', 'sockets'];

const DEV_ONLY_EXTENSIONS = ['xdebug'];

const DEV_EXTENSIONS = [
    ...PRODUCTION_EXTENSIONS,
    ...DEV_ONLY_EXTENSIONS,
];

const PRODUCTION_BINARIES = ['php', 'composer', 'node', 'pnpm', 'psql', 'mysql', 'supervisord', 'jpegoptim', 'optipng', 'pngquant', 'gifsicle', 'ffmpeg', 'svgo', 'avifenc', 'zsh'];

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

    $runner->finish();
}

go();
