<?php

declare(strict_types=1);

const PRODUCTION_EXTENSIONS = ['mysqli', 'pdo_mysql', 'pgsql', 'pdo_pgsql', 'bcmath', 'gd', 'imagick', 'imap', 'pcntl', 'zip', 'intl', 'exif', 'ftp', 'xml', 'pdo_sqlsrv', 'sqlsrv', 'sockets'];

const PRODUCTION_ONLY_EXTENSIONS = [];

const DEV_ONLY_EXTENSIONS = ['xdebug'];

const DEV_EXTENSIONS = [
    ...PRODUCTION_EXTENSIONS,
    ...DEV_ONLY_EXTENSIONS,
];

const PRODUCTION_BINARIES = ['php', 'composer', 'node', 'npm', 'pnpm', 'jpegoptim', 'optipng', 'pngquant', 'gifsicle', 'ffmpeg', 'svgo', 'avifenc'];

const PRODUCTION_ONLY_BINARIES = [];

const DEV_ONLY_BINARIES = ['gh', 'htop', 'nano'];

const DEV_BINARIES = [
    ...PRODUCTION_BINARIES,
    ...DEV_ONLY_BINARIES,
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

    public function warn(string $message): void
    {
        $warnText = paint("[WARN]", Colors::BOLD . Colors::BRIGHT_YELLOW);
        $messageText = paint($message, Colors::MAGENTA);

        echo "{$warnText} {$messageText}\n";
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
            if (extension_loaded($extension)) {
                $runner->warn("extension:{$extension} present (unexpected in production)");
            }
        }
    } else {
        foreach (PRODUCTION_ONLY_EXTENSIONS as $extension) {
            if (extension_loaded($extension)) {
                $runner->warn("extension:{$extension} present (unexpected in dev)");
            }
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

    if ($runner->environment === 'production') {
        foreach (DEV_ONLY_BINARIES as $binary) {
            if ($runner->commandExists($binary)) {
                $runner->warn("binary:{$binary} present (unexpected in production)");
            }
        }
    } else {
        foreach (PRODUCTION_ONLY_BINARIES as $binary) {
            if ($runner->commandExists($binary)) {
                $runner->warn("binary:{$binary} present (unexpected in dev)");
            }
        }
    }
}

function sanity(Runner $runner): void
{
    $runner->printHeader("✅", "Running Sanity Checks");

    $modules = @shell_exec('php -m 2>/dev/null');
    $runner->check('php-cli works', is_string($modules) && trim($modules) !== '');
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
