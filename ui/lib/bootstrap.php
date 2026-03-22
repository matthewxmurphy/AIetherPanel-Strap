<?php
declare(strict_types=1);

function aetherpanel_base_path(): string
{
    return dirname(__DIR__);
}

function aetherpanel_config_path(): string
{
    $override = trim((string)(getenv('AETHERPANEL_ETC') ?: ''));
    if ($override !== '') {
        return rtrim($override, '/');
    }
    return '/etc/aetherpanel';
}

function aetherpanel_node_env_path(): string
{
    return aetherpanel_config_path() . '/node.env';
}

function aetherpanel_node_env(): array
{
    static $env;

    if (is_array($env)) {
        return $env;
    }

    $env = aetherpanel_parse_env_file(aetherpanel_node_env_path());
    return $env;
}

function aetherpanel_state_path(): string
{
    $override = trim((string)(getenv('AETHERPANEL_VAR') ?: ''));
    if ($override === '') {
        $override = trim((string)(aetherpanel_node_env()['PANEL_VAR'] ?? ''));
    }

    if ($override !== '') {
        return rtrim($override, '/');
    }

    return '/var/lib/aetherpanel';
}

function aetherpanel_state_dir(): string
{
    return aetherpanel_state_path() . '/state';
}

function aetherpanel_state_file(string $filename): string
{
    return aetherpanel_state_dir() . '/' . ltrim($filename, '/');
}

function aetherpanel_config_file(string $filename): string
{
    return aetherpanel_config_path() . '/' . ltrim($filename, '/');
}

function aetherpanel_read_json_from_paths(array $paths, array $fallback = []): array
{
    foreach ($paths as $path) {
        $candidate = trim((string)$path);
        if ($candidate === '') {
            continue;
        }

        if (is_file($candidate)) {
            return aetherpanel_read_json($candidate, $fallback);
        }
    }

    return $fallback;
}

function aetherpanel_mutable_json_path(string $filename): string
{
    $statePath = aetherpanel_state_file($filename);
    if (is_file($statePath) || is_dir(dirname($statePath))) {
        return $statePath;
    }

    return aetherpanel_config_file($filename);
}

function aetherpanel_htpasswd_path(): string
{
    return aetherpanel_config_file('users.htpasswd');
}

function aetherpanel_parse_env_file(string $path): array
{
    if (!is_file($path)) {
        return [];
    }

    $values = [];
    $lines = file($path, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
    if (!is_array($lines)) {
        return [];
    }

    foreach ($lines as $line) {
        $line = trim((string)$line);
        if ($line === '' || str_starts_with($line, '#') || !str_contains($line, '=')) {
            continue;
        }
        [$key, $value] = explode('=', $line, 2);
        $values[trim((string)$key)] = trim((string)$value);
    }

    return $values;
}

function aetherpanel_read_json(string $path, array $fallback = []): array
{
    if (!is_file($path)) {
        return $fallback;
    }

    $decoded = json_decode((string)file_get_contents($path), true);
    return is_array($decoded) ? $decoded : $fallback;
}

function aetherpanel_write_json(string $path, array $payload): bool
{
    $dir = dirname($path);
    if (!is_dir($dir) || (!is_writable($dir) && !is_writable($path))) {
        return false;
    }

    $encoded = json_encode($payload, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);
    if (!is_string($encoded) || $encoded === '') {
        return false;
    }

    $written = file_put_contents($path, $encoded . PHP_EOL) !== false;
    if ($written) {
        @chmod($path, 0660);
    }

    return $written;
}

function aetherpanel_default_branding(): array
{
    return [
        'project_name' => 'AetherPanel',
        'business_end' => 'AI Control Host',
        'owner' => 'Matthew Murphy',
        'organization_name' => 'Net30 Hosting',
        'support_url' => 'https://www.net30hosting.com/support',
        'ecommerce_url' => 'https://www.net30hosting.com',
        'billing_url' => 'https://billing.net30hosting.com',
        'system_email_from' => 'hello@net30hosting.com',
        'create_account_url' => 'https://www.net30hosting.com',
        'logout_destination_url' => 'https://www.net30hosting.com',
        'brand_color' => '#F8931F',
        'secondary_color' => '#111111',
        'font_family' => 'Noto Sans',
        'border_radius' => 18,
        'default_dark_mode' => true,
        'login_page_image' => '',
        'logo_light' => '',
        'logo_dark' => '',
        'logo_compact' => '',
        'favicon' => '',
        'inverse_icon' => '',
        'compact_mark_text' => 'N30',
        'public_domains' => [
            'www.net30hosting.com',
            'www.matthewxmurphy.com',
        ],
    ];
}

function aetherpanel_load_branding(): array
{
    $branding = aetherpanel_read_json_from_paths([
        aetherpanel_state_file('branding.json'),
        aetherpanel_config_file('branding.json'),
    ], []);
    return array_replace(aetherpanel_default_branding(), $branding);
}

function aetherpanel_default_access_model(): array
{
    return [
        'roles' => [
            [
                'id' => 'platform_admin',
                'label' => 'Platform Admin',
                'description' => 'Full control of branding, roles, nodes, migrations, and firewall posture.',
                'permissions' => [
                    'edit branding',
                    'manage users',
                    'manage roles',
                    'manage nodes',
                    'manage firewall posture',
                    'approve migrations',
                    'view billing summaries',
                ],
            ],
            [
                'id' => 'fleet_operator',
                'label' => 'Fleet Operator',
                'description' => 'Can manage nodes, vhosts, certificates, and migrations.',
                'permissions' => [
                    'manage nodes',
                    'manage vhosts',
                    'apply certificates',
                    'start migrations',
                ],
            ],
            [
                'id' => 'web_operator',
                'label' => 'Web Operator',
                'description' => 'Can manage sites, PHP packages, and jailed SFTP users.',
                'permissions' => [
                    'create vhosts',
                    'edit php packages',
                    'manage jailed sftp users',
                    'view vhost telemetry',
                ],
            ],
            [
                'id' => 'mail_operator',
                'label' => 'Mail Operator',
                'description' => 'Can manage outbound email posture and mail-role changes.',
                'permissions' => [
                    'manage outbound mail posture',
                    'move mail role',
                    'view mail host assignments',
                ],
            ],
            [
                'id' => 'dns_operator',
                'label' => 'DNS Operator',
                'description' => 'Can manage DNS role placement and DNS changes.',
                'permissions' => [
                    'manage dns role assignments',
                    'move dns role',
                    'view dns host assignments',
                ],
            ],
            [
                'id' => 'billing_viewer',
                'label' => 'Billing Viewer',
                'description' => 'Read-only access to bandwidth, disk, and billing summaries.',
                'permissions' => [
                    'view disk summaries',
                    'view bandwidth summaries',
                    'view billing summaries',
                ],
            ],
        ],
        'users' => [
            [
                'username' => 'admin',
                'display_name' => 'Bootstrap Admin',
                'roles' => ['platform_admin'],
            ],
        ],
    ];
}

function aetherpanel_load_access_model(): array
{
    $model = aetherpanel_read_json_from_paths([
        aetherpanel_state_file('users.json'),
        aetherpanel_config_file('users.json'),
    ], []);
    $defaults = aetherpanel_default_access_model();

    if (!isset($model['roles']) || !is_array($model['roles'])) {
        $model['roles'] = $defaults['roles'];
    }
    if (!isset($model['users']) || !is_array($model['users'])) {
        $model['users'] = $defaults['users'];
    }

    return $model;
}

function aetherpanel_access_model_path(): string
{
    return aetherpanel_mutable_json_path('users.json');
}

function aetherpanel_save_access_model(array $model): bool
{
    return aetherpanel_write_json(aetherpanel_access_model_path(), $model);
}

function aetherpanel_node_context(): array
{
    $env = aetherpanel_node_env();
    return [
        'node_name' => $env['NODE_NAME'] ?? php_uname('n'),
        'roles' => array_values(array_filter(array_map('trim', explode(',', (string)($env['ROLES'] ?? 'controller,web,database'))))),
        'controller_url' => $env['CONTROLLER_URL'] ?? '',
        'controller_api_url' => $env['CONTROLLER_API_URL'] ?? '',
        'join_key_present' => trim((string)($env['JOIN_KEY'] ?? '')) !== '',
        'public_hostname' => $env['PUBLIC_HOSTNAME'] ?? '',
        'tailscale_ip' => $env['TAILSCALE_IP'] ?? '',
        'panel_port' => $env['PANEL_PORT'] ?? '8844',
        'version' => $env['AETHERPANEL_VERSION'] ?? '0.1.0',
    ];
}

function aetherpanel_current_username(): string
{
    $candidates = [
        $_SERVER['REMOTE_USER'] ?? '',
        $_SERVER['PHP_AUTH_USER'] ?? '',
    ];

    foreach ($candidates as $candidate) {
        $value = trim((string)$candidate);
        if ($value !== '') {
            return $value;
        }
    }

    return 'unknown';
}

function aetherpanel_current_user(array $accessModel): array
{
    $username = aetherpanel_current_username();
    foreach ($accessModel['users'] as $user) {
        if (!is_array($user)) {
            continue;
        }
        if (strcasecmp((string)($user['username'] ?? ''), $username) === 0) {
            return $user + ['username' => $username];
        }
    }

    return [
        'username' => $username,
        'display_name' => 'Unassigned User',
        'roles' => [],
    ];
}

function aetherpanel_roles_for_user(array $user, array $accessModel): array
{
    $wanted = array_map('strval', (array)($user['roles'] ?? []));
    $roles = [];
    foreach ($accessModel['roles'] as $role) {
        if (!is_array($role)) {
            continue;
        }
        $id = (string)($role['id'] ?? '');
        if ($id !== '' && in_array($id, $wanted, true)) {
            $roles[] = $role;
        }
    }
    return $roles;
}

function aetherpanel_permission_list(array $roles): array
{
    $permissions = [];
    foreach ($roles as $role) {
        foreach ((array)($role['permissions'] ?? []) as $permission) {
            $label = trim((string)$permission);
            if ($label !== '') {
                $permissions[$label] = true;
            }
        }
    }
    $labels = array_keys($permissions);
    sort($labels, SORT_NATURAL | SORT_FLAG_CASE);
    return $labels;
}

function aetherpanel_mask_secret(string $value): string
{
    $value = trim($value);
    if ($value === '') {
        return 'Not set';
    }
    if (strlen($value) <= 8) {
        return str_repeat('*', strlen($value));
    }
    return substr($value, 0, 4) . str_repeat('*', max(4, strlen($value) - 8)) . substr($value, -4);
}

function aetherpanel_default_ai_config(): array
{
    return [
        'ollama_cloud' => [
            'enabled' => false,
            'base_url' => 'https://ollama.com/v1',
            'api_key' => '',
            'model' => 'nemotron-3-super:cloud',
        ],
    ];
}

function aetherpanel_ai_config_path(): string
{
    return aetherpanel_mutable_json_path('ai.json');
}

function aetherpanel_load_ai_config(): array
{
    $config = aetherpanel_read_json(aetherpanel_ai_config_path(), []);
    return array_replace_recursive(aetherpanel_default_ai_config(), $config);
}

function aetherpanel_save_ai_config(array $config): bool
{
    return aetherpanel_write_json(aetherpanel_ai_config_path(), $config);
}

function aetherpanel_save_ollama_cloud_settings(bool $enabled, string $apiKey, string $model, string $baseUrl = ''): array
{
    $apiKey = trim($apiKey);
    $model = trim($model);
    $baseUrl = trim($baseUrl);

    if ($model === '') {
        return ['ok' => false, 'message' => 'Model is required for the Ollama Cloud lane.'];
    }
    if ($enabled && $apiKey === '') {
        return ['ok' => false, 'message' => 'Paste the Ollama Cloud key before enabling this lane.'];
    }
    if ($baseUrl === '') {
        $baseUrl = 'https://ollama.com/v1';
    }

    $config = aetherpanel_load_ai_config();
    $config['ollama_cloud'] = [
        'enabled' => $enabled,
        'base_url' => $baseUrl,
        'api_key' => $apiKey,
        'model' => $model,
    ];

    if (!aetherpanel_save_ai_config($config)) {
        return ['ok' => false, 'message' => 'Could not save the Ollama Cloud settings on this node yet.'];
    }

    return [
        'ok' => true,
        'message' => $enabled
            ? 'Ollama Cloud is enabled for this node.'
            : 'Ollama Cloud settings saved, but the lane is disabled.',
    ];
}

function aetherpanel_default_control_db_config(): array
{
    return [
        'enabled' => false,
        'driver' => 'mysql',
        'host' => '',
        'port' => '',
        'database' => '',
        'username' => '',
        'password' => '',
        'ssl_mode' => 'preferred',
        'ca_path' => '',
    ];
}

function aetherpanel_control_db_config_path(): string
{
    return aetherpanel_mutable_json_path('control-db.json');
}

function aetherpanel_control_db_status_path(): string
{
    return aetherpanel_mutable_json_path('control-db-status.json');
}

function aetherpanel_control_db_env_path(): string
{
    return aetherpanel_state_file('controller-db.env');
}

function aetherpanel_load_control_db_config(): array
{
    $config = aetherpanel_read_json(aetherpanel_control_db_config_path(), []);
    return array_replace(aetherpanel_default_control_db_config(), $config);
}

function aetherpanel_save_control_db_config(array $config): bool
{
    return aetherpanel_write_json(aetherpanel_control_db_config_path(), $config);
}

function aetherpanel_load_control_db_status(): array
{
    return aetherpanel_read_json(aetherpanel_control_db_status_path(), [
        'checked_at' => null,
        'ok' => false,
        'message' => 'Control database lane is still pending on this server.',
        'latency_ms' => null,
        'driver' => null,
        'server_version' => null,
        'details' => [],
    ]);
}

function aetherpanel_save_control_db_status(array $status): bool
{
    return aetherpanel_write_json(aetherpanel_control_db_status_path(), $status);
}

function aetherpanel_default_db_port(string $driver): string
{
    return $driver === 'pgsql' ? '5432' : '3306';
}

function aetherpanel_control_db_runtime_driver(string $driver): string
{
    return $driver === 'mariadb' ? 'mysql' : $driver;
}

function aetherpanel_write_control_db_env_file(array $config): bool
{
    $path = aetherpanel_control_db_env_path();
    $dir = dirname($path);
    if (!is_dir($dir) || (!is_writable($dir) && !is_writable($path))) {
        return false;
    }

    $written = file_put_contents($path, aetherpanel_control_db_env_snippet($config) . PHP_EOL) !== false;
    if ($written) {
        @chmod($path, 0660);
    }

    return $written;
}

function aetherpanel_save_control_db_settings(
    bool $enabled,
    string $driver,
    string $host,
    string $port,
    string $database,
    string $username,
    string $password,
    string $sslMode,
    string $caPath = ''
): array {
    $driver = trim($driver);
    $host = trim($host);
    $port = trim($port);
    $database = trim($database);
    $username = trim($username);
    $password = trim($password);
    $sslMode = trim($sslMode);
    $caPath = trim($caPath);

    if (!in_array($driver, ['mysql', 'mariadb', 'pgsql'], true)) {
        return ['ok' => false, 'message' => 'Choose mysql, mariadb, or pgsql for the control database lane.'];
    }

    if ($port === '') {
        $port = aetherpanel_default_db_port($driver);
    }

    if (!preg_match('/^\d{2,5}$/', $port)) {
        return ['ok' => false, 'message' => 'Control database port must be numeric.'];
    }

    if ($enabled) {
        foreach ([
            'host' => $host,
            'database' => $database,
            'username' => $username,
        ] as $field => $value) {
            if ($value === '') {
                return ['ok' => false, 'message' => sprintf('Control database %s is required before enabling this lane.', $field)];
            }
        }
    }

    if ($sslMode === '') {
        $sslMode = 'preferred';
    }

    $config = [
        'enabled' => $enabled,
        'driver' => $driver,
        'host' => $host,
        'port' => $port,
        'database' => $database,
        'username' => $username,
        'password' => $password,
        'ssl_mode' => $sslMode,
        'ca_path' => $caPath,
    ];

    if (!aetherpanel_save_control_db_config($config)) {
        return ['ok' => false, 'message' => 'Could not save the control database settings on this server yet.'];
    }

    aetherpanel_write_control_db_env_file($config);
    aetherpanel_save_control_db_status([
        'checked_at' => null,
        'ok' => false,
        'message' => $enabled
            ? 'Configuration changed. Run a connection test before trusting this control database lane.'
            : 'Control database lane is disabled on this server.',
        'latency_ms' => null,
        'driver' => $driver,
        'server_version' => null,
        'details' => [],
    ]);

    return [
        'ok' => true,
        'message' => $enabled
            ? 'Control database settings saved for this server.'
            : 'Control database settings saved, but the lane is disabled.',
    ];
}

function aetherpanel_test_control_db_connection(array $config): array
{
    $driver = trim((string)($config['driver'] ?? 'mysql'));
    $runtimeDriver = aetherpanel_control_db_runtime_driver($driver);
    $host = trim((string)($config['host'] ?? ''));
    $port = trim((string)($config['port'] ?? ''));
    $database = trim((string)($config['database'] ?? ''));
    $username = trim((string)($config['username'] ?? ''));
    $password = (string)($config['password'] ?? '');
    $sslMode = trim((string)($config['ssl_mode'] ?? ''));
    $caPath = trim((string)($config['ca_path'] ?? ''));

    if (empty($config['enabled'])) {
        return ['ok' => false, 'message' => 'Enable the control database lane before testing it.'];
    }

    foreach ([
        'host' => $host,
        'database' => $database,
        'username' => $username,
    ] as $field => $value) {
        if ($value === '') {
            return ['ok' => false, 'message' => sprintf('Control database %s is required before testing.', $field)];
        }
    }

    if ($port === '') {
        $port = aetherpanel_default_db_port($driver);
    }

    $startedAt = microtime(true);
    $status = [
        'checked_at' => gmdate('c'),
        'ok' => false,
        'message' => '',
        'latency_ms' => null,
        'driver' => $driver,
        'server_version' => null,
        'details' => [
            'host' => $host,
            'port' => $port,
            'database' => $database,
            'ssl_mode' => $sslMode !== '' ? $sslMode : null,
            'ca_path' => $caPath !== '' ? $caPath : null,
        ],
    ];

    try {
        if ($runtimeDriver === 'pgsql') {
            if (!extension_loaded('pdo_pgsql')) {
                throw new RuntimeException('pdo_pgsql is not installed on this server yet.');
            }

            $dsn = sprintf(
                'pgsql:host=%s;port=%s;dbname=%s%s',
                $host,
                $port,
                $database,
                $sslMode !== '' ? ';sslmode=' . $sslMode : ''
            );

            $pdo = new PDO($dsn, $username, $password, [
                PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
                PDO::ATTR_TIMEOUT => 5,
            ]);
            $version = $pdo->getAttribute(PDO::ATTR_SERVER_VERSION);
            $pdo = null;
        } else {
            if (!function_exists('mysqli_init')) {
                throw new RuntimeException('mysqli is not installed on this server yet.');
            }

            $mysqli = mysqli_init();
            if (!$mysqli instanceof mysqli) {
                throw new RuntimeException('Could not initialize mysqli for the control database test.');
            }

            mysqli_options($mysqli, MYSQLI_OPT_CONNECT_TIMEOUT, 5);
            if ($caPath !== '') {
                mysqli_ssl_set($mysqli, null, null, $caPath, null, null);
            }

            $flags = 0;
            if ($sslMode !== '' && strtolower($sslMode) !== 'disable') {
                $flags |= MYSQLI_CLIENT_SSL;
            }

            if (!@mysqli_real_connect($mysqli, $host, $username, $password, $database, (int)$port, null, $flags)) {
                throw new RuntimeException(mysqli_connect_error() ?: 'MySQL/MariaDB connection failed.');
            }

            $version = mysqli_get_server_info($mysqli);
            mysqli_close($mysqli);
        }

        $status['ok'] = true;
        $status['server_version'] = $version;
        $status['latency_ms'] = (int)round((microtime(true) - $startedAt) * 1000);
        $status['message'] = sprintf(
            'Connected to the external %s control database in %d ms.',
            $driver,
            (int)$status['latency_ms']
        );
    } catch (Throwable $exception) {
        $status['ok'] = false;
        $status['latency_ms'] = (int)round((microtime(true) - $startedAt) * 1000);
        $status['message'] = $exception->getMessage();
    }

    aetherpanel_save_control_db_status($status);
    return [
        'ok' => $status['ok'],
        'message' => $status['message'],
        'status' => $status,
    ];
}

function aetherpanel_control_db_env_snippet(array $config): string
{
    if (empty($config['enabled'])) {
        return "# External control database is still pending on this server.\n"
            . '# Save and test the real managed database details when they exist.';
    }

    $lines = [
        'DB_CONNECTION=' . ($config['driver'] ?? 'mysql'),
        'DB_HOST=' . ($config['host'] ?? ''),
        'DB_PORT=' . ($config['port'] ?? ''),
        'DB_DATABASE=' . ($config['database'] ?? ''),
        'DB_USERNAME=' . ($config['username'] ?? ''),
        'DB_PASSWORD=' . ($config['password'] ?? ''),
    ];

    $driver = (string)($config['driver'] ?? 'mysql');
    $sslMode = trim((string)($config['ssl_mode'] ?? ''));
    $caPath = trim((string)($config['ca_path'] ?? ''));

    if ($driver === 'pgsql') {
        $lines[] = 'DB_SSLMODE=' . ($sslMode !== '' ? $sslMode : 'prefer');
    } elseif ($caPath !== '') {
        $lines[] = 'MYSQL_ATTR_SSL_CA=' . $caPath;
    }

    return implode(PHP_EOL, $lines);
}

function aetherpanel_login_endpoint(array $node): string
{
    $ip = trim((string)($node['tailscale_ip'] ?? ''));
    $port = trim((string)($node['panel_port'] ?? '8844'));
    if ($ip === '') {
        return 'Tailscale bind pending';
    }
    return sprintf('http://%s:%s', $ip, $port);
}

function aetherpanel_bool_label(bool $value): string
{
    return $value ? 'Enabled' : 'Disabled';
}

function aetherpanel_default_onboarding(): array
{
    return [
        'title' => 'Your account setup',
        'subtitle' => 'Finish the first fleet steps before handing real websites and customers to AetherPanel.',
        'items' => [
            [
                'id' => 'register_controller_identity',
                'title' => 'Register controller identity',
                'summary' => 'When the control API is live, attach this server to the controller identity and redeem its join/license key.',
                'done' => false,
            ],
            [
                'id' => 'add_first_node',
                'title' => 'Add first node',
                'summary' => 'Track the first hybrid controller/app/database node in fleet inventory.',
                'done' => false,
            ],
            [
                'id' => 'confirm_tailscale_bind',
                'title' => 'Confirm Tailscale bind',
                'summary' => 'Keep the panel on this server reachable only over the tailnet.',
                'done' => false,
            ],
            [
                'id' => 'lock_ssh_to_known_ips',
                'title' => 'Lock SSH to known IPs',
                'summary' => 'Restrict port 22 to Tailscale and approved known IP lanes.',
                'done' => false,
            ],
            [
                'id' => 'set_default_web_stack',
                'title' => 'Set default web stack',
                'summary' => 'Use Apache, PHP 8.5, website-local database access, Let’s Encrypt, msmtp, and jailed SFTP as the baseline.',
                'done' => false,
            ],
            [
                'id' => 'connect_control_database',
                'title' => 'Connect control database',
                'summary' => 'When the free control database exists, point panel state, sessions, cache, jobs, and fleet inventory at it.',
                'done' => false,
            ],
            [
                'id' => 'set_backup_target',
                'title' => 'Set backup target',
                'summary' => 'Point backups at Wasabi and verify restore posture.',
                'done' => false,
            ],
            [
                'id' => 'add_first_role_user',
                'title' => 'Add first role user',
                'summary' => 'Create the first operator beyond the bootstrap admin account.',
                'done' => false,
            ],
            [
                'id' => 'add_first_hosting_package',
                'title' => 'Add first hosting package',
                'summary' => 'Create the default package for shared and dedicated site placement.',
                'done' => false,
            ],
            [
                'id' => 'import_existing_sites',
                'title' => 'Import existing sites',
                'summary' => 'Start bringing current website inventory and external panel state into AetherPanel.',
                'done' => false,
            ],
        ],
    ];
}

function aetherpanel_onboarding_path(): string
{
    return aetherpanel_mutable_json_path('onboarding.json');
}

function aetherpanel_onboarding_flag_map(): array
{
    return [
        'lock_ssh_to_known_ips' => 'ssh_known_ip_lock',
        'connect_control_database' => 'control_database_ready',
        'set_backup_target' => 'backup_target_ready',
        'add_first_hosting_package' => 'hosting_package_ready',
        'import_existing_sites' => 'import_ready',
    ];
}

function aetherpanel_is_persisted_onboarding_step(string $stepId): bool
{
    return array_key_exists($stepId, aetherpanel_onboarding_flag_map());
}

function aetherpanel_set_onboarding_step_state(string $stepId, bool $done): bool
{
    $map = aetherpanel_onboarding_flag_map();
    $path = aetherpanel_onboarding_path();
    $config = aetherpanel_read_json($path, aetherpanel_default_onboarding());

    if (isset($map[$stepId])) {
        $config[$map[$stepId]] = $done;
    } else {
        $overrides = is_array($config['manual_overrides'] ?? null) ? $config['manual_overrides'] : [];
        $overrides[$stepId] = $done;
        $config['manual_overrides'] = $overrides;
    }

    if (isset($config['items']) && is_array($config['items'])) {
        foreach ($config['items'] as &$item) {
            if (!is_array($item)) {
                continue;
            }
            if (($item['id'] ?? '') === $stepId) {
                $item['done'] = $done;
                break;
            }
        }
        unset($item);
    }

    return aetherpanel_write_json($path, $config);
}

function aetherpanel_load_onboarding(array $node, array $branding, array $accessModel): array
{
    $seed = aetherpanel_default_onboarding();
    $config = aetherpanel_read_json(aetherpanel_onboarding_path(), []);
    $title = (string)($config['title'] ?? $seed['title']);
    $subtitle = (string)($config['subtitle'] ?? $seed['subtitle']);
    $items = is_array($config['items'] ?? null) ? $config['items'] : $seed['items'];
    $overrides = is_array($config['manual_overrides'] ?? null) ? $config['manual_overrides'] : [];

    $knownUsers = array_values(array_filter((array)($accessModel['users'] ?? []), static fn ($user): bool => is_array($user)));
    $hasExtraUser = count($knownUsers) > 1;
    $hasController = trim((string)($node['controller_url'] ?? '')) !== ''
        || trim((string)($node['controller_api_url'] ?? '')) !== ''
        || !empty($node['join_key_present']);
    $hasTailnet = trim((string)($node['tailscale_ip'] ?? '')) !== '';
    $hasWebRole = in_array('web', array_map('strval', (array)($node['roles'] ?? [])), true);
    $hasBranding = trim((string)($branding['organization_name'] ?? '')) !== '' && trim((string)($branding['system_email_from'] ?? '')) !== '';
    $controlDb = aetherpanel_load_control_db_config();
    $controlDbStatus = aetherpanel_load_control_db_status();
    $hasControlDb = !empty($controlDb['enabled'])
        && trim((string)($controlDb['host'] ?? '')) !== ''
        && trim((string)($controlDb['database'] ?? '')) !== ''
        && trim((string)($controlDb['username'] ?? '')) !== ''
        && !empty($controlDbStatus['ok']);

    $computed = [
        'register_controller_identity' => $hasController && $hasBranding,
        'add_first_node' => trim((string)($node['node_name'] ?? '')) !== '',
        'confirm_tailscale_bind' => $hasTailnet,
        'lock_ssh_to_known_ips' => (bool)($config['ssh_known_ip_lock'] ?? false),
        'set_default_web_stack' => $hasWebRole,
        'connect_control_database' => $hasControlDb,
        'set_backup_target' => (bool)($config['backup_target_ready'] ?? false),
        'add_first_role_user' => $hasExtraUser,
        'add_first_hosting_package' => (bool)($config['hosting_package_ready'] ?? false),
        'import_existing_sites' => (bool)($config['import_ready'] ?? false),
    ];

    $resolved = [];
    foreach ($items as $item) {
        if (!is_array($item)) {
            continue;
        }
        $id = trim((string)($item['id'] ?? ''));
        if ($id === '') {
            continue;
        }
        $resolved[] = [
            'id' => $id,
            'title' => (string)($item['title'] ?? $id),
            'summary' => (string)($item['summary'] ?? ''),
            'done' => array_key_exists($id, $computed)
                ? $computed[$id]
                : (array_key_exists($id, $overrides) ? (bool)$overrides[$id] : (bool)($item['done'] ?? false)),
            'persisted' => aetherpanel_is_persisted_onboarding_step($id),
        ];
    }

    return [
        'title' => $title,
        'subtitle' => $subtitle,
        'items' => $resolved,
    ];
}

function aetherpanel_onboarding_progress(array $onboarding): array
{
    $items = array_values(array_filter((array)($onboarding['items'] ?? []), static fn ($item): bool => is_array($item)));
    $total = count($items);
    $done = 0;
    foreach ($items as $item) {
        if (!empty($item['done'])) {
            $done++;
        }
    }

    return [
        'done' => $done,
        'total' => $total,
        'pending' => max(0, $total - $done),
    ];
}

function aetherpanel_username_is_valid(string $username): bool
{
    return (bool)preg_match('/^[A-Za-z0-9][A-Za-z0-9._-]{1,31}$/', $username);
}

function aetherpanel_random_password(int $length = 24): string
{
    $bytes = bin2hex(random_bytes((int)max(8, ceil($length / 2))));
    return substr($bytes, 0, $length);
}

function aetherpanel_role_ids(array $accessModel): array
{
    $ids = [];
    foreach ((array)($accessModel['roles'] ?? []) as $role) {
        if (!is_array($role)) {
            continue;
        }

        $id = trim((string)($role['id'] ?? ''));
        if ($id !== '') {
            $ids[$id] = true;
        }
    }

    return array_keys($ids);
}

function aetherpanel_write_htpasswd_entry(string $username, string $password): bool
{
    $path = aetherpanel_htpasswd_path();
    $dir = dirname($path);
    if ((!is_file($path) || !is_writable($path)) && !is_writable($dir)) {
        return false;
    }

    $lines = [];
    if (is_file($path)) {
        $existing = file($path, FILE_IGNORE_NEW_LINES);
        if (is_array($existing)) {
            foreach ($existing as $line) {
                $line = trim((string)$line);
                if ($line === '' || !str_contains($line, ':')) {
                    continue;
                }

                [$existingUser] = explode(':', $line, 2);
                if (strcasecmp(trim((string)$existingUser), $username) !== 0) {
                    $lines[] = $line;
                }
            }
        }
    }

    $hash = password_hash($password, PASSWORD_BCRYPT);
    if (!is_string($hash) || $hash === '') {
        return false;
    }

    $lines[] = $username . ':' . $hash;
    $payload = implode(PHP_EOL, $lines) . PHP_EOL;

    return file_put_contents($path, $payload) !== false;
}

function aetherpanel_add_local_user(string $username, string $displayName, array $roleIds, string $password = ''): array
{
    $username = trim($username);
    $displayName = trim($displayName);
    $roleIds = array_values(array_unique(array_filter(array_map('trim', $roleIds))));

    if (!aetherpanel_username_is_valid($username)) {
        return ['ok' => false, 'message' => 'Use a simple username with letters, numbers, dot, dash, or underscore.'];
    }

    if ($displayName === '') {
        return ['ok' => false, 'message' => 'Display name is required.'];
    }

    $accessModel = aetherpanel_load_access_model();
    $validRoleIds = aetherpanel_role_ids($accessModel);
    $selectedRoles = array_values(array_intersect($roleIds, $validRoleIds));

    if ($selectedRoles === []) {
        return ['ok' => false, 'message' => 'Choose at least one role for the new user.'];
    }

    foreach ((array)($accessModel['users'] ?? []) as $user) {
        if (!is_array($user)) {
            continue;
        }

        if (strcasecmp((string)($user['username'] ?? ''), $username) === 0) {
            return ['ok' => false, 'message' => 'That username already exists on this server panel.'];
        }
    }

    $plainPassword = trim($password) !== '' ? trim($password) : aetherpanel_random_password();

    if (!aetherpanel_write_htpasswd_entry($username, $plainPassword)) {
        return ['ok' => false, 'message' => 'Could not update the server panel password file yet.'];
    }

    $accessModel['users'][] = [
        'username' => $username,
        'display_name' => $displayName,
        'roles' => $selectedRoles,
    ];

    usort($accessModel['users'], static function (array $left, array $right): int {
        return strcasecmp((string)($left['username'] ?? ''), (string)($right['username'] ?? ''));
    });

    if (!aetherpanel_save_access_model($accessModel)) {
        return ['ok' => false, 'message' => 'The user password was written, but the role assignment file could not be saved.'];
    }

    return [
        'ok' => true,
        'message' => 'Local operator created.',
        'password' => $plainPassword,
        'username' => $username,
    ];
}
