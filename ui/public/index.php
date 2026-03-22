<?php
declare(strict_types=1);

require dirname(__DIR__) . '/lib/bootstrap.php';

$scriptName = (string)($_SERVER['AETHERPANEL_SCRIPT_PATH'] ?? ($_SERVER['SCRIPT_NAME'] ?? '/aetherpanel/ui/public/index.php'));
$requestPath = parse_url((string)($_SERVER['REQUEST_URI'] ?? ''), PHP_URL_PATH);
if (!is_string($requestPath) || $requestPath === '') {
    $requestPath = '';
}
$serverPort = trim((string)($_SERVER['SERVER_PORT'] ?? ''));
$scriptPath = $requestPath !== '' ? $requestPath : ($scriptName !== '' ? $scriptName : '/');
$assetBase = trim((string)($_SERVER['AETHERPANEL_ASSET_PREFIX'] ?? ''));
if ($serverPort === '8844') {
    $scriptPath = '/';
    $assetBase = '';
} elseif ($assetBase === '') {
    if ($scriptPath === '/' || $scriptPath === '') {
        $assetBase = '';
    } else {
        $assetBase = rtrim(str_replace('\\', '/', dirname($scriptPath)), '/');
    }
}
$assetPrefix = $assetBase !== '' ? $assetBase : '';

$saveState = $_GET['saved'] ?? '';
$saveMessage = '';
$saveError = '';
$generatedPassword = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $action = trim((string)($_POST['action'] ?? ''));
    $stepId = trim((string)($_POST['step_id'] ?? ''));
    if ($action === 'set-step' && $stepId !== '') {
        $done = trim((string)($_POST['done'] ?? '0')) === '1';
        if (aetherpanel_set_onboarding_step_state($stepId, $done)) {
            header('Location: ' . $scriptPath . '?saved=' . ($done ? 'done' : 'undone') . '#setup');
            exit;
        }
        $saveError = 'Could not save the onboarding state yet.';
    } elseif ($action === 'create-user') {
        $result = aetherpanel_add_local_user(
            (string)($_POST['username'] ?? ''),
            (string)($_POST['display_name'] ?? ''),
            array_map('strval', (array)($_POST['roles'] ?? [])),
            (string)($_POST['password'] ?? '')
        );

        if (!empty($result['ok'])) {
            $saveMessage = (string)($result['message'] ?? 'Local operator created.');
            $generatedPassword = (string)($result['password'] ?? '');
        } else {
            $saveError = (string)($result['message'] ?? 'Could not create the local operator yet.');
        }
    } elseif ($action === 'save-ai') {
        $existingAi = aetherpanel_load_ai_config();
        $existingOllama = (array)($existingAi['ollama_cloud'] ?? []);
        $apiKeyInput = trim((string)($_POST['ollama_api_key'] ?? ''));
        $apiKey = $apiKeyInput !== '' ? $apiKeyInput : (string)($existingOllama['api_key'] ?? '');
        $result = aetherpanel_save_ollama_cloud_settings(
            trim((string)($_POST['ollama_enabled'] ?? '0')) === '1',
            $apiKey,
            (string)($_POST['ollama_model'] ?? ''),
            (string)($_POST['ollama_base_url'] ?? '')
        );

        if (!empty($result['ok'])) {
            $saveMessage = (string)($result['message'] ?? 'Ollama Cloud settings saved.');
        } else {
            $saveError = (string)($result['message'] ?? 'Could not save the Ollama Cloud settings yet.');
        }
    } elseif ($action === 'save-control-db') {
        $existingControlDb = aetherpanel_load_control_db_config();
        $passwordInput = trim((string)($_POST['control_db_password'] ?? ''));
        $password = $passwordInput !== '' ? $passwordInput : (string)($existingControlDb['password'] ?? '');
        $result = aetherpanel_save_control_db_settings(
            trim((string)($_POST['control_db_enabled'] ?? '0')) === '1',
            (string)($_POST['control_db_driver'] ?? ''),
            (string)($_POST['control_db_host'] ?? ''),
            (string)($_POST['control_db_port'] ?? ''),
            (string)($_POST['control_db_database'] ?? ''),
            (string)($_POST['control_db_username'] ?? ''),
            $password,
            (string)($_POST['control_db_ssl_mode'] ?? ''),
            (string)($_POST['control_db_ca_path'] ?? '')
        );

        if (!empty($result['ok'])) {
            $saveMessage = (string)($result['message'] ?? 'Control database settings saved.');
        } else {
            $saveError = (string)($result['message'] ?? 'Could not save the control database settings yet.');
        }
    } elseif ($action === 'test-control-db') {
        $existingControlDb = aetherpanel_load_control_db_config();
        $passwordInput = trim((string)($_POST['control_db_password'] ?? ''));
        $password = $passwordInput !== '' ? $passwordInput : (string)($existingControlDb['password'] ?? '');
        $saveResult = aetherpanel_save_control_db_settings(
            trim((string)($_POST['control_db_enabled'] ?? '0')) === '1',
            (string)($_POST['control_db_driver'] ?? ''),
            (string)($_POST['control_db_host'] ?? ''),
            (string)($_POST['control_db_port'] ?? ''),
            (string)($_POST['control_db_database'] ?? ''),
            (string)($_POST['control_db_username'] ?? ''),
            $password,
            (string)($_POST['control_db_ssl_mode'] ?? ''),
            (string)($_POST['control_db_ca_path'] ?? '')
        );

        if (empty($saveResult['ok'])) {
            $saveError = (string)($saveResult['message'] ?? 'Could not save the control database settings before testing.');
        } else {
            $controlDb = aetherpanel_load_control_db_config();
            $testResult = aetherpanel_test_control_db_connection($controlDb);
            if (!empty($testResult['ok'])) {
                $saveMessage = (string)($testResult['message'] ?? 'External control database connection succeeded.');
            } else {
                $saveError = (string)($testResult['message'] ?? 'External control database connection failed.');
            }
        }
    }
}

$branding = aetherpanel_load_branding();
$accessModel = aetherpanel_load_access_model();
$node = aetherpanel_node_context();
$currentUser = aetherpanel_current_user($accessModel);
$currentRoles = aetherpanel_roles_for_user($currentUser, $accessModel);
$permissions = aetherpanel_permission_list($currentRoles);
$aiConfig = aetherpanel_load_ai_config();
$ollamaCloud = (array)($aiConfig['ollama_cloud'] ?? []);
$controlDb = aetherpanel_load_control_db_config();
$controlDbStatus = aetherpanel_load_control_db_status();
$onboarding = aetherpanel_load_onboarding($node, $branding, $accessModel);
$onboardingProgress = aetherpanel_onboarding_progress($onboarding);

$organizationName = (string)($branding['organization_name'] ?? 'Net30 Hosting');
$brandColor = (string)($branding['brand_color'] ?? '#F8931F');
$secondaryColor = (string)($branding['secondary_color'] ?? '#111111');
$fontFamily = (string)($branding['font_family'] ?? 'Noto Sans');
$borderRadius = max(10, min(30, (int)($branding['border_radius'] ?? 18)));
$publicDomains = array_values(array_filter(array_map('strval', (array)($branding['public_domains'] ?? []))));
$primaryRole = $currentRoles[0]['label'] ?? 'Role assignment needed';
$loginImage = trim((string)($branding['login_page_image'] ?? ''));
$compactMarkText = trim((string)($branding['compact_mark_text'] ?? 'N30')) ?: 'N30';
$controllerUrlDisplay = trim((string)($node['controller_url'] ?? '')) !== ''
    ? trim((string)$node['controller_url'])
    : 'Pending until the control API is ready';
$controllerApiDisplay = trim((string)($node['controller_api_url'] ?? '')) !== ''
    ? trim((string)$node['controller_api_url'])
    : 'Pending until the control API is ready';
$joinStatusDisplay = !empty($node['join_key_present'])
    ? 'Join/license key present'
    : 'Waiting for the API and license lane';
$controlDbEnvSnippet = aetherpanel_control_db_env_snippet($controlDb);

if ($saveState === 'done') {
    $saveMessage = 'Checklist step marked done.';
} elseif ($saveState === 'undone') {
    $saveMessage = 'Checklist step reopened.';
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title><?= htmlspecialchars((string)($branding['project_name'] ?? 'AIetherPanel')) ?></title>
  <link rel="stylesheet" href="<?= htmlspecialchars($assetPrefix . '/assets/aetherpanel.css') ?>">
  <style>
    :root {
      --ap-brand: <?= htmlspecialchars($brandColor) ?>;
      --ap-secondary: <?= htmlspecialchars($secondaryColor) ?>;
      --ap-font: "<?= htmlspecialchars($fontFamily) ?>", "Segoe UI", "Helvetica Neue", sans-serif;
      --ap-radius: <?= $borderRadius ?>px;
    }
  </style>
</head>
<body>
  <div class="ap-shell">
    <aside class="ap-icon-rail">
      <div class="ap-compact-brand" title="<?= htmlspecialchars($organizationName) ?>">
        <?php if (trim((string)($branding['logo_compact'] ?? '')) !== ''): ?>
          <img src="<?= htmlspecialchars((string)$branding['logo_compact']) ?>" alt="<?= htmlspecialchars($organizationName) ?> compact logo">
        <?php else: ?>
          <span><?= htmlspecialchars($compactMarkText) ?></span>
        <?php endif; ?>
      </div>
      <nav class="ap-icon-nav" aria-label="AIetherPanel sections">
        <a href="#setup" title="Setup">⌘</a>
        <a href="#organization" title="Branding">◫</a>
        <a href="#access" title="Access">◎</a>
        <a href="#roles" title="Roles">◆</a>
        <a href="#domains" title="Domains">◌</a>
      </nav>
    </aside>

    <aside class="ap-sidebar">
      <div class="ap-mark">
        <div class="ap-mark-label">AI Control Host</div>
        <div class="ap-mark-title"><?= htmlspecialchars($organizationName) ?></div>
        <div class="ap-mark-subtitle"><?= htmlspecialchars((string)($branding['project_name'] ?? 'AIetherPanel')) ?></div>
      </div>
      <nav class="ap-nav">
        <a href="#setup">Setup</a>
        <a href="#organization">Organization</a>
        <a href="#control-panel">Control Panel</a>
        <a href="#styling">Styling</a>
        <a href="#access">Access</a>
        <a href="#roles">Roles</a>
      </nav>
      <div class="ap-sidebar-note">
        Tailscale-first panel on this server for <?= htmlspecialchars((string)($branding['owner'] ?? 'Matthew Murphy')) ?>.
      </div>
    </aside>

    <main class="ap-main">
      <section class="ap-checklist" id="setup">
        <div class="ap-checklist-bar">
          <div class="ap-progress-ring">
            <div class="ap-progress-ring-inner"><?= (int)$onboardingProgress['done'] ?>/<?= (int)$onboardingProgress['total'] ?></div>
          </div>
          <div class="ap-checklist-copy">
            <div class="ap-eyebrow">Setup Checklist</div>
            <h2><?= htmlspecialchars((string)$onboarding['title']) ?></h2>
            <p><?= htmlspecialchars((string)$onboarding['subtitle']) ?></p>
          </div>
          <div class="ap-checklist-meta">
            <strong><?= (int)$onboardingProgress['pending'] ?></strong>
            <span>pending steps</span>
          </div>
        </div>
        <?php if ($saveMessage !== '' || $saveError !== ''): ?>
          <div class="ap-flash<?= $saveError !== '' ? ' is-error' : '' ?>">
            <?= htmlspecialchars($saveError !== '' ? $saveError : $saveMessage) ?>
          </div>
        <?php endif; ?>
        <?php if ($generatedPassword !== ''): ?>
          <div class="ap-flash ap-flash-password">
            Generated password for the new local operator: <strong><?= htmlspecialchars($generatedPassword) ?></strong>
          </div>
        <?php endif; ?>
        <div class="ap-checklist-items">
          <?php foreach ((array)$onboarding['items'] as $item): ?>
            <article class="ap-checklist-item<?= !empty($item['done']) ? ' is-done' : '' ?>">
              <div class="ap-check-status"><?= !empty($item['done']) ? '✓' : '•' ?></div>
              <div class="ap-check-body">
                <h3><?= htmlspecialchars((string)($item['title'] ?? 'Step')) ?></h3>
                <p><?= htmlspecialchars((string)($item['summary'] ?? '')) ?></p>
              </div>
              <div class="ap-check-actions">
                <div class="ap-check-state">
                  <?php if (!empty($item['persisted'])): ?>
                    <?= !empty($item['done']) ? 'Saved' : 'Needs action' ?>
                  <?php else: ?>
                    <?= !empty($item['done']) ? 'Detected' : 'Pending' ?>
                  <?php endif; ?>
                </div>
                <?php if (!empty($item['persisted'])): ?>
                  <form method="post" class="ap-check-form">
                    <input type="hidden" name="action" value="set-step">
                    <input type="hidden" name="step_id" value="<?= htmlspecialchars((string)$item['id']) ?>">
                    <input type="hidden" name="done" value="<?= !empty($item['done']) ? '0' : '1' ?>">
                    <button type="submit" class="ap-inline-button<?= !empty($item['done']) ? ' is-secondary' : '' ?>">
                      <?= !empty($item['done']) ? 'Reopen' : 'Mark done' ?>
                    </button>
                  </form>
                <?php endif; ?>
              </div>
            </article>
          <?php endforeach; ?>
        </div>
      </section>

      <section class="ap-hero">
        <div>
          <div class="ap-eyebrow">Branding First</div>
          <h1><?= htmlspecialchars($organizationName) ?></h1>
          <p>
            The first authenticated screen is the brand contract for <?= htmlspecialchars((string)($branding['business_end'] ?? 'AI Control Host')) ?>.
            This lighttpd surface should only exist on the tailnet. For now it uses local access on this server, then it can hand off to the license-backed controller flow when the API lane is live.
          </p>
        </div>
        <div class="ap-hero-cards">
          <article class="ap-mini-card">
            <span class="ap-mini-label">Bound Login</span>
            <strong><?= htmlspecialchars(aetherpanel_login_endpoint($node)) ?></strong>
            <small>Tailscale-only lighttpd gate</small>
          </article>
          <article class="ap-mini-card">
            <span class="ap-mini-label">Current User</span>
            <strong><?= htmlspecialchars((string)($currentUser['display_name'] ?? $currentUser['username'])) ?></strong>
            <small><?= htmlspecialchars($primaryRole) ?></small>
          </article>
        </div>
      </section>

      <section class="ap-grid">
        <article class="ap-card ap-card-wide" id="organization">
          <div class="ap-card-heading">
            <span class="ap-kicker">Organization</span>
            <h2>Customer-facing branding</h2>
          </div>
          <div class="ap-form-grid">
            <div>
              <label>Organization name</label>
              <div class="ap-field"><?= htmlspecialchars($organizationName) ?></div>
            </div>
            <div>
              <label>Support URL</label>
              <div class="ap-field"><?= htmlspecialchars((string)($branding['support_url'] ?? '')) ?></div>
            </div>
            <div>
              <label>eCommerce URL</label>
              <div class="ap-field"><?= htmlspecialchars((string)($branding['ecommerce_url'] ?? '')) ?></div>
            </div>
            <div>
              <label>System email from</label>
              <div class="ap-field"><?= htmlspecialchars((string)($branding['system_email_from'] ?? '')) ?></div>
            </div>
            <div>
              <label>Billing URL</label>
              <div class="ap-field"><?= htmlspecialchars((string)($branding['billing_url'] ?? '')) ?></div>
            </div>
            <div>
              <label>Create account URL</label>
              <div class="ap-field"><?= htmlspecialchars((string)($branding['create_account_url'] ?? '')) ?></div>
            </div>
          </div>
        </article>

        <article class="ap-card" id="control-panel">
          <div class="ap-card-heading">
            <span class="ap-kicker">Control Panel</span>
            <h2>Identity and posture</h2>
          </div>
          <ul class="ap-definition-list">
            <li><span>Dark mode default</span><strong><?= htmlspecialchars(aetherpanel_bool_label((bool)($branding['default_dark_mode'] ?? false))) ?></strong></li>
            <li><span>Logout destination</span><strong><?= htmlspecialchars((string)($branding['logout_destination_url'] ?? '')) ?></strong></li>
            <li><span>Node</span><strong><?= htmlspecialchars((string)$node['node_name']) ?></strong></li>
            <li><span>Node roles</span><strong><?= htmlspecialchars(implode(', ', (array)$node['roles'])) ?></strong></li>
            <li><span>Controller URL</span><strong><?= htmlspecialchars($controllerUrlDisplay) ?></strong></li>
            <li><span>Controller API</span><strong><?= htmlspecialchars($controllerApiDisplay) ?></strong></li>
            <li><span>Join / license lane</span><strong><?= htmlspecialchars($joinStatusDisplay) ?></strong></li>
            <li><span>Enhance bridge</span><strong>A / AAAA only</strong></li>
            <li><span>Website database posture</span><strong>Website-local only</strong></li>
            <li><span>Control database lane</span><strong><?= htmlspecialchars(!empty($controlDb['enabled']) ? 'External control DB' : 'Not enabled yet') ?></strong></li>
          </ul>
        </article>

        <article class="ap-card" id="styling">
          <div class="ap-card-heading">
            <span class="ap-kicker">Styling</span>
            <h2>Brand palette</h2>
          </div>
          <div class="ap-palette">
            <div class="ap-swatch">
              <span class="ap-swatch-color" style="background: <?= htmlspecialchars($brandColor) ?>"></span>
              <div>
                <label>Brand</label>
                <strong><?= htmlspecialchars($brandColor) ?></strong>
              </div>
            </div>
            <div class="ap-swatch">
              <span class="ap-swatch-color" style="background: <?= htmlspecialchars($secondaryColor) ?>"></span>
              <div>
                <label>Secondary</label>
                <strong><?= htmlspecialchars($secondaryColor) ?></strong>
              </div>
            </div>
          </div>
          <div class="ap-preview">
            <div class="ap-preview-button">Primary Action</div>
            <div class="ap-preview-button ap-preview-button-secondary">Secondary Action</div>
          </div>
        </article>

        <article class="ap-card ap-card-wide" id="access">
          <div class="ap-card-heading">
            <span class="ap-kicker">Access</span>
            <h2>Tailscale gate plus roles</h2>
          </div>
          <div class="ap-access-grid">
            <div class="ap-access-step">
              <div class="ap-access-index">1</div>
              <div>
                <h3>Tailnet reachability</h3>
                <p>lighttpd binds to the node Tailscale IP, not the public edge.</p>
              </div>
            </div>
            <div class="ap-access-step">
              <div class="ap-access-index">2</div>
              <div>
                <h3>Login and password</h3>
                <p>Basic auth is the first credential gate before AIetherPanel logic loads.</p>
              </div>
            </div>
            <div class="ap-access-step">
              <div class="ap-access-index">3</div>
              <div>
                <h3>User roles</h3>
                <p>The authenticated lighttpd username maps into AIetherPanel roles and permissions.</p>
              </div>
            </div>
          </div>
          <div class="ap-role-strip">
            <span class="ap-role-label">Signed in as</span>
            <strong><?= htmlspecialchars((string)$currentUser['username']) ?></strong>
            <?php foreach ($currentRoles as $role): ?>
              <span class="ap-role-chip"><?= htmlspecialchars((string)($role['label'] ?? $role['id'] ?? 'Role')) ?></span>
            <?php endforeach; ?>
            <?php if ($currentRoles === []): ?>
              <span class="ap-role-chip ap-role-chip-warning">Needs role assignment</span>
            <?php endif; ?>
          </div>
        </article>

        <article class="ap-card ap-card-wide" id="roles">
          <div class="ap-card-heading">
            <span class="ap-kicker">Roles</span>
            <h2>Immediate RBAC baseline</h2>
          </div>
          <div class="ap-role-grid">
            <?php foreach ((array)$accessModel['roles'] as $role): ?>
              <section class="ap-role-card">
                <h3><?= htmlspecialchars((string)($role['label'] ?? $role['id'] ?? 'Role')) ?></h3>
                <p><?= htmlspecialchars((string)($role['description'] ?? '')) ?></p>
                <ul>
                  <?php foreach ((array)($role['permissions'] ?? []) as $permission): ?>
                    <li><?= htmlspecialchars((string)$permission) ?></li>
                  <?php endforeach; ?>
                </ul>
              </section>
            <?php endforeach; ?>
          </div>
          <div class="ap-local-users-grid">
            <section class="ap-user-form-card">
              <h3>Add local operator</h3>
              <p>Create a lighttpd login and map it into AIetherPanel roles on this node.</p>
              <form method="post" class="ap-form-stack">
                <input type="hidden" name="action" value="create-user">
                <div>
                  <label for="ap-username">Username</label>
                  <input class="ap-input" id="ap-username" name="username" type="text" autocomplete="username" placeholder="fleet">
                </div>
                <div>
                  <label for="ap-display-name">Display name</label>
                  <input class="ap-input" id="ap-display-name" name="display_name" type="text" placeholder="Fleet Operator">
                </div>
                <div>
                  <label for="ap-password">Password</label>
                  <input class="ap-input" id="ap-password" name="password" type="text" autocomplete="new-password" placeholder="Leave blank to generate one">
                </div>
                <fieldset class="ap-checkbox-grid">
                  <legend>Role assignments</legend>
                  <?php foreach ((array)$accessModel['roles'] as $role): ?>
                    <label class="ap-checkbox">
                      <input type="checkbox" name="roles[]" value="<?= htmlspecialchars((string)($role['id'] ?? '')) ?>">
                      <span><?= htmlspecialchars((string)($role['label'] ?? $role['id'] ?? 'Role')) ?></span>
                    </label>
                  <?php endforeach; ?>
                </fieldset>
                <div class="ap-form-actions">
                  <button type="submit" class="ap-inline-button">Create operator</button>
                </div>
              </form>
            </section>
            <section class="ap-user-list-card">
              <h3>Local role users</h3>
              <div class="ap-user-list">
                <?php foreach ((array)$accessModel['users'] as $user): ?>
                  <article class="ap-user-list-item">
                    <div>
                      <strong><?= htmlspecialchars((string)($user['display_name'] ?? $user['username'] ?? 'User')) ?></strong>
                      <div class="ap-user-meta"><?= htmlspecialchars((string)($user['username'] ?? 'unknown')) ?></div>
                    </div>
                    <div class="ap-chip-list ap-chip-list-compact">
                      <?php foreach ((array)($user['roles'] ?? []) as $roleId): ?>
                        <span class="ap-chip ap-chip-muted"><?= htmlspecialchars((string)$roleId) ?></span>
                      <?php endforeach; ?>
                    </div>
                  </article>
                <?php endforeach; ?>
              </div>
            </section>
          </div>
          <div class="ap-callout">
            <strong>Current permission set</strong>
            <div class="ap-permissions">
              <?php foreach ($permissions as $permission): ?>
                <span><?= htmlspecialchars($permission) ?></span>
              <?php endforeach; ?>
              <?php if ($permissions === []): ?>
                <span>No effective permissions yet.</span>
              <?php endif; ?>
            </div>
          </div>
        </article>

        <article class="ap-card" id="domains">
          <div class="ap-card-heading">
            <span class="ap-kicker">Domains</span>
            <h2>Public identity</h2>
          </div>
          <div class="ap-chip-list">
            <?php foreach ($publicDomains as $domain): ?>
              <span class="ap-chip"><?= htmlspecialchars($domain) ?></span>
            <?php endforeach; ?>
          </div>
        </article>

        <article class="ap-card">
          <div class="ap-card-heading">
            <span class="ap-kicker">Database Access</span>
            <h2>Operator database posture</h2>
          </div>
          <div class="ap-db-client">
            <div class="ap-db-client-name">Sequel Ace</div>
            <p>Preferred operator database client from trusted machines. AIetherPanel should not grow a phpMyAdmin surface.</p>
            <div class="ap-role-chip">No phpMyAdmin lane</div>
          </div>
        </article>

        <article class="ap-card">
          <div class="ap-card-heading">
            <span class="ap-kicker">Control Database</span>
            <h2>External panel database</h2>
          </div>
          <form method="post" class="ap-form-stack">
            <label class="ap-checkbox">
              <input type="checkbox" name="control_db_enabled" value="1"<?= !empty($controlDb['enabled']) ? ' checked' : '' ?>>
              <span>Use the external control database for panel state on this server</span>
            </label>
            <div class="ap-form-grid">
              <div>
                <label for="ap-control-db-driver">Driver</label>
                <select class="ap-input" id="ap-control-db-driver" name="control_db_driver">
                  <?php foreach (['mysql', 'mariadb', 'pgsql'] as $driver): ?>
                    <option value="<?= htmlspecialchars($driver) ?>"<?= (($controlDb['driver'] ?? 'mysql') === $driver) ? ' selected' : '' ?>><?= htmlspecialchars($driver) ?></option>
                  <?php endforeach; ?>
                </select>
              </div>
              <div>
                <label for="ap-control-db-host">Host</label>
                <input class="ap-input" id="ap-control-db-host" name="control_db_host" type="text" value="<?= htmlspecialchars((string)($controlDb['host'] ?? '')) ?>">
              </div>
              <div>
                <label for="ap-control-db-port">Port</label>
                <input class="ap-input" id="ap-control-db-port" name="control_db_port" type="text" value="<?= htmlspecialchars((string)($controlDb['port'] ?? '')) ?>">
              </div>
              <div>
                <label for="ap-control-db-name">Database</label>
                <input class="ap-input" id="ap-control-db-name" name="control_db_database" type="text" value="<?= htmlspecialchars((string)($controlDb['database'] ?? '')) ?>">
              </div>
              <div>
                <label for="ap-control-db-username">Username</label>
                <input class="ap-input" id="ap-control-db-username" name="control_db_username" type="text" value="<?= htmlspecialchars((string)($controlDb['username'] ?? '')) ?>">
              </div>
              <div>
                <label for="ap-control-db-password">Paste new password</label>
                <input class="ap-input" id="ap-control-db-password" name="control_db_password" type="password" autocomplete="off" placeholder="Leave blank to keep the current saved password">
              </div>
              <div>
                <label for="ap-control-db-ssl-mode">SSL Mode</label>
                <input class="ap-input" id="ap-control-db-ssl-mode" name="control_db_ssl_mode" type="text" value="<?= htmlspecialchars((string)($controlDb['ssl_mode'] ?? 'preferred')) ?>">
              </div>
              <div>
                <label for="ap-control-db-ca-path">CA Path</label>
                <input class="ap-input" id="ap-control-db-ca-path" name="control_db_ca_path" type="text" value="<?= htmlspecialchars((string)($controlDb['ca_path'] ?? '')) ?>">
              </div>
            </div>
            <div class="ap-field">
              Saved password: <?= htmlspecialchars(aetherpanel_mask_secret((string)($controlDb['password'] ?? ''))) ?>
            </div>
            <div class="ap-callout<?= !empty($controlDbStatus['ok']) ? ' is-success' : ' is-warning' ?>">
              <strong>Connection status</strong>
              <div><?= htmlspecialchars((string)($controlDbStatus['message'] ?? 'Connection has not been tested yet.')) ?></div>
              <div class="ap-meta-line">
                <?php if (!empty($controlDbStatus['checked_at'])): ?>
                  <span>Last checked: <?= htmlspecialchars((string)$controlDbStatus['checked_at']) ?></span>
                <?php endif; ?>
                <?php if (!empty($controlDbStatus['server_version'])): ?>
                  <span>Server: <?= htmlspecialchars((string)$controlDbStatus['server_version']) ?></span>
                <?php endif; ?>
                <?php if (($controlDbStatus['latency_ms'] ?? null) !== null): ?>
                  <span>Latency: <?= htmlspecialchars((string)$controlDbStatus['latency_ms']) ?> ms</span>
                <?php endif; ?>
              </div>
            </div>
            <div class="ap-callout">
              <strong>Controller env snippet</strong>
              <pre class="ap-code-block"><?= htmlspecialchars($controlDbEnvSnippet) ?></pre>
            </div>
            <div class="ap-form-actions">
              <button type="submit" name="action" value="save-control-db" class="ap-inline-button ap-inline-button is-secondary">Save only</button>
              <button type="submit" name="action" value="test-control-db" class="ap-inline-button">Save and test</button>
            </div>
          </form>
        </article>

        <article class="ap-card">
          <div class="ap-card-heading">
            <span class="ap-kicker">AI</span>
            <h2>Ollama Cloud on this server</h2>
          </div>
          <form method="post" class="ap-form-stack">
            <input type="hidden" name="action" value="save-ai">
            <label class="ap-checkbox">
              <input type="checkbox" name="ollama_enabled" value="1"<?= !empty($ollamaCloud['enabled']) ? ' checked' : '' ?>>
              <span>Enable Ollama Cloud on this server</span>
            </label>
            <div>
              <label for="ap-ollama-model">Model</label>
              <input class="ap-input" id="ap-ollama-model" name="ollama_model" type="text" value="<?= htmlspecialchars((string)($ollamaCloud['model'] ?? 'nemotron-3-super:cloud')) ?>">
            </div>
            <div>
              <label for="ap-ollama-base-url">Base URL</label>
              <input class="ap-input" id="ap-ollama-base-url" name="ollama_base_url" type="text" value="<?= htmlspecialchars((string)($ollamaCloud['base_url'] ?? 'https://ollama.com/v1')) ?>">
            </div>
            <div>
              <label for="ap-ollama-api-key">Paste new Ollama key</label>
              <input class="ap-input" id="ap-ollama-api-key" name="ollama_api_key" type="password" autocomplete="off" placeholder="Leave blank to keep the current saved key">
            </div>
            <div class="ap-field">
              Saved key: <?= htmlspecialchars(aetherpanel_mask_secret((string)($ollamaCloud['api_key'] ?? ''))) ?>
            </div>
            <div class="ap-form-actions">
              <button type="submit" class="ap-inline-button">Save Ollama settings</button>
            </div>
          </form>
        </article>
      </section>
    </main>
  </div>
</body>
</html>
