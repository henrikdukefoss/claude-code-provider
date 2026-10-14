#!/usr/bin/env node
// ccp - point Claude Code at another Anthropic-compatible provider without model_not_found errors.
// Single file, no dependencies. Node 18+; `ccp check` also needs curl.
// https://github.com/henrikdukefoss/claude-code-provider  (MIT)
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const VERSION = '0.1.0';

// ---------------------------------------------------------------------------
// Presets. Every value comes from the vendor's own Claude Code / Anthropic-API page (see `source`).
// Model slots: main = ANTHROPIC_MODEL, opus/sonnet/haiku/fable = ANTHROPIC_DEFAULT_*_MODEL,
// subagent = CLAUDE_CODE_SUBAGENT_MODEL. A slot the vendor page leaves out gets `main` (or `haiku`).
// ---------------------------------------------------------------------------
const PRESETS = {
  anthropic: {
    name: 'Anthropic (default)',
    reset: true,
    source: 'https://code.claude.com/docs/en/model-config',
    note: 'Removes every override ccp manages, so Claude Code uses your Anthropic login or key and its own model defaults.',
  },
  deepseek: {
    name: 'DeepSeek',
    baseUrl: 'https://api.deepseek.com/anthropic',
    keyEnv: 'DEEPSEEK_API_KEY',
    models: { main: 'deepseek-flash[1m]', opus: 'deepseek-flash[1m]', sonnet: 'deepseek-flash[1m]', haiku: 'deepseek-flash', subagent: 'deepseek-flash' },
    extra: { CLAUDE_CODE_EFFORT_LEVEL: 'max' },
    source: 'https://api-docs.deepseek.com/guides/coding_agents',
  },
  kimi: {
    name: 'Moonshot AI (Kimi)',
    aliases: ['moonshot'],
    baseUrl: 'https://api.moonshot.ai/anthropic',
    keyEnv: 'MOONSHOT_API_KEY',
    models: { main: 'kimi-k3[1m]', opus: 'kimi-k3[1m]', sonnet: 'kimi-k3[1m]', haiku: 'kimi-k3', fable: 'kimi-k3[1m]', subagent: 'kimi-k3[1m]' },
    extra: { CLAUDE_CODE_AUTO_COMPACT_WINDOW: '1000000', CLAUDE_CODE_EFFORT_LEVEL: 'max' },
    source: 'https://platform.kimi.ai/docs/guide/claude-code-kimi',
    note: "Kimi's example puts kimi-k2.7-code in the Haiku slot, but that model rejects requests with thinking off and Claude Code's background calls send none, so this preset uses kimi-k3. Add --haiku kimi-k2.7-code to follow Kimi's example exactly.",
  },
  zai: {
    name: 'Z.ai (GLM Coding Plan)',
    aliases: ['glm', 'z.ai'],
    baseUrl: 'https://api.z.ai/api/anthropic',
    keyEnv: 'ZAI_API_KEY',
    models: { main: 'glm-5.3-flash[1m]', opus: 'glm-5.3-flash[1m]', sonnet: 'glm-5.3-flash[1m]', haiku: 'glm-5.3-flash[1m]' },
    extra: { API_TIMEOUT_MS: '3000000', CLAUDE_CODE_AUTO_COMPACT_WINDOW: '1000000' },
    source: 'https://docs.z.ai/devpack/latest-model',
  },
  minimax: {
    name: 'MiniMax',
    baseUrl: 'https://api.minimax.io/anthropic',
    keyEnv: 'MINIMAX_API_KEY',
    models: { main: 'MiniMax-M3.1-Flash-Preview[1m]', opus: 'MiniMax-M3.1-Flash-Preview[1m]', sonnet: 'MiniMax-M3.1-Flash-Preview[1m]', haiku: 'MiniMax-M3.1-Flash-Preview[1m]' },
    extra: { CLAUDE_CODE_AUTO_COMPACT_WINDOW: '524288' },
    source: 'https://platform.minimax.io/docs/m-plan/claude-code',
  },
  qwen: {
    name: 'Alibaba Model Studio (Qwen), pay-as-you-go, Singapore',
    aliases: ['alibaba', 'dashscope'],
    baseUrl: 'https://{WorkspaceId}.ap-southeast-1.maas.aliyuncs.com/apps/anthropic',
    keyEnv: 'DASHSCOPE_API_KEY',
    models: { main: 'qwen3.7-max', opus: 'qwen3.7-max', sonnet: 'qwen3.7-max', haiku: 'qwen3.6-flash', subagent: 'qwen3.7-max' },
    source: 'https://www.alibabacloud.com/help/en/model-studio/claude-code',
    note: 'Needs your Workspace ID: --workspace ID, or --base-url for the Beijing (cn-beijing) or Virginia (us-east-1) region. The key only works in the region where it was created.',
  },
  'qwen-coding': {
    name: 'Alibaba Model Studio (Qwen), Coding Plan',
    aliases: ['alibaba-coding'],
    baseUrl: 'https://coding-intl.dashscope.aliyuncs.com/apps/anthropic',
    keyEnv: 'DASHSCOPE_API_KEY',
    models: { main: 'qwen3.7-plus', opus: 'qwen3.7-plus', sonnet: 'qwen3.7-plus', haiku: 'qwen3.7-plus', subagent: 'qwen3.7-plus' },
    source: 'https://www.alibabacloud.com/help/en/model-studio/claude-code',
    note: 'Use the Coding Plan key, not a pay-as-you-go key.',
  },
  openrouter: {
    name: 'OpenRouter',
    baseUrl: 'https://openrouter.ai/api',
    keyEnv: 'OPENROUTER_API_KEY',
    models: {
      main: '~anthropic/claude-opus-latest[1m]', opus: '~anthropic/claude-opus-latest[1m]', sonnet: '~anthropic/claude-sonnet-latest[1m]',
      haiku: '~anthropic/claude-haiku-latest', fable: '~anthropic/claude-fable-latest[1m]', subagent: '~anthropic/claude-opus-latest[1m]',
    },
    source: 'https://openrouter.ai/docs/cookbook/coding-agents/claude-code-integration',
    note: 'Any OpenRouter model slug works with --model, e.g. --model deepseek/deepseek-v4-flash.',
  },
  litellm: {
    name: 'LiteLLM proxy (self-hosted)',
    baseUrl: 'http://localhost:4000',
    keyEnv: 'LITELLM_API_KEY',
    models: null, // names come from your proxy's config.yaml
    source: 'https://docs.litellm.ai/docs/tutorials/claude_responses_api',
    note: 'Pass --model with a model_name from your config.yaml (and --small-model for the Haiku slot if you have one). The key is your master key or a virtual key.',
  },
  standardcompute: {
    name: 'Standard Compute',
    aliases: ['sc'],
    baseUrl: 'https://api.stdcmpt.com',
    keyEnv: 'STANDARDCOMPUTE_API_KEY',
    models: { main: 'standardcompute', opus: 'standardcompute', sonnet: 'standardcompute', haiku: 'standardcompute', fable: 'standardcompute', subagent: 'standardcompute' },
    source: 'https://docs.standardcompute.com/api/messages',
    note: '`standardcompute` lets the gateway pick a model per request; pass --model with a catalog ID such as anthropic/claude-sonnet-5.5 to pin one.',
  },
};

// Env vars ccp writes and removes. Anything else in your settings is left alone.
const SLOT_VARS = {
  main: 'ANTHROPIC_MODEL',
  opus: 'ANTHROPIC_DEFAULT_OPUS_MODEL',
  sonnet: 'ANTHROPIC_DEFAULT_SONNET_MODEL',
  haiku: 'ANTHROPIC_DEFAULT_HAIKU_MODEL',
  fable: 'ANTHROPIC_DEFAULT_FABLE_MODEL',
  subagent: 'CLAUDE_CODE_SUBAGENT_MODEL',
};
const MANAGED = [
  'ANTHROPIC_BASE_URL', 'ANTHROPIC_AUTH_TOKEN', 'ANTHROPIC_API_KEY',
  ...Object.values(SLOT_VARS), 'ANTHROPIC_SMALL_FAST_MODEL',
  'API_TIMEOUT_MS', 'CLAUDE_CODE_AUTO_COMPACT_WINDOW', 'CLAUDE_CODE_EFFORT_LEVEL',
];
// What Claude Code requests when a slot is unset (observed with Claude Code 2.1.296 against a logging mock).
const BUILTIN = {
  main: 'claude-opus-5-5', opus: 'claude-opus-5-5', sonnet: 'claude-sonnet-5-5', haiku: 'claude-haiku-5-5',
  fable: 'claude-fable-5-1', subagent: '(inherits the main model)',
};

// ---------------------------------------------------------------------------
// small helpers
// ---------------------------------------------------------------------------
const isTTY = process.stdout.isTTY && !process.env.NO_COLOR;
const c = (code, s) => (isTTY ? `\x1b[${code}m${s}\x1b[0m` : s);
const ok = (s) => console.log(c('32', 'OK   ') + s);
const bad = (s) => console.log(c('31', 'FAIL ') + s);
const warn = (s) => console.log(c('33', 'WARN ') + s);
const info = (s) => console.log('     ' + s);
function die(msg, code = 2) { console.error('ccp: ' + msg); process.exit(code); }

function findPreset(name) {
  const n = String(name || '').toLowerCase();
  for (const [id, p] of Object.entries(PRESETS)) if (id === n || (p.aliases || []).includes(n)) return [id, p];
  return [null, null];
}

function claudeDir() { return process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude'); }
function userSettingsPath() { return path.join(claudeDir(), 'settings.json'); }
function defaultProfilePath() {
  const base = process.env.XDG_CONFIG_HOME || path.join(os.homedir(), '.config');
  return path.join(base, 'claude-code-provider', 'env.sh');
}
const tilde = (p) => (p.startsWith(os.homedir() + path.sep) ? '~' + p.slice(os.homedir().length) : p);

function readJson(file) {
  if (!fs.existsSync(file)) return null;
  const txt = fs.readFileSync(file, 'utf8');
  if (!txt.trim()) return {};
  try { return JSON.parse(txt); } catch (e) { die(`${tilde(file)} is not valid JSON (${e.message}). Fix it first; nothing was changed.`); }
}

function writeFileAtomic(file, text, mode) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const tmp = `${file}.ccp-tmp-${process.pid}`;
  fs.writeFileSync(tmp, text, { mode: mode || 0o600 });
  fs.renameSync(tmp, file);
  if (mode) fs.chmodSync(file, mode);
}

function stripOneM(model) { return String(model).replace(/\[1m\]$/i, ''); }
function hasExtraV1(url) { return /\/v1\/?$/.test(url); }

function parseArgs(argv) {
  const out = { _: [] };
  const flags = new Set(['all', 'no-key', 'defaults', 'dry-run', 'help', 'version', 'yes']);
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '-h') { out.help = true; continue; }
    if (a.startsWith('--')) {
      let [k, v] = a.slice(2).split(/=(.*)/s);
      if (flags.has(k)) { out[k] = true; continue; }
      if (v === undefined) {
        const next = argv[i + 1];
        if (k === 'profile' && (next === undefined || next.startsWith('--'))) v = '';
        else { v = argv[++i]; if (v === undefined) die(`--${k} needs a value`); }
      }
      out[k] = v;
    } else out._.push(a);
  }
  return out;
}

// Hidden prompt: nothing is echoed.
function promptHidden(question) {
  return new Promise((resolve) => {
    const stdin = process.stdin;
    if (!stdin.isTTY) return resolve('');
    process.stderr.write(question);
    let buf = '';
    stdin.setRawMode(true);
    stdin.resume();
    stdin.setEncoding('utf8');
    const onData = (ch) => {
      for (const k of ch) {
        if (k === '\r' || k === '\n' || k === '\u0004') {
          stdin.setRawMode(false); stdin.pause(); stdin.removeListener('data', onData);
          process.stderr.write('\n');
          return resolve(buf);
        } else if (k === '\u0003') {
          stdin.setRawMode(false); process.stderr.write('\n'); process.exit(130);
        } else if (k === '\u007f' || k === '\b') buf = buf.slice(0, -1);
        else buf += k;
      }
    };
    stdin.on('data', onData);
  });
}

// ---------------------------------------------------------------------------
// ccp use
// ---------------------------------------------------------------------------
function buildConfig(args) {
  const presetName = args._[1];
  let id = null, p = null;
  if (presetName) {
    [id, p] = findPreset(presetName);
    if (!p) die(`unknown preset "${presetName}". Run \`ccp presets\` for the list, or use --base-url URL --model ID.`);
  } else if (!args['base-url']) die('usage: ccp use <preset> | ccp use --base-url URL --model ID   (see ccp help)');

  if (p && p.reset) return { id, preset: p, reset: true };

  let baseUrl = args['base-url'] || p.baseUrl;
  if (args.workspace) baseUrl = baseUrl.replace('{WorkspaceId}', args.workspace);
  if (/\{\w+\}/.test(baseUrl)) die(`${p.name} needs a value for ${baseUrl.match(/\{\w+\}/)[0]}: pass --workspace ID or --base-url URL.`);
  baseUrl = baseUrl.replace(/\/+$/, '');
  if (hasExtraV1(baseUrl)) die(`base URL ends in /v1. Claude Code appends /v1/messages itself, so it would call ${baseUrl}/v1/messages. Use ${baseUrl.replace(/\/v1\/?$/, '')}`);
  if (!/^https?:\/\//.test(baseUrl)) die('base URL must start with http:// or https://');

  const m = { ...((p && p.models) || {}) };
  if (args.model) for (const s of ['main', 'opus', 'sonnet', 'fable', 'subagent', 'haiku']) m[s] = args.model;
  if (args['small-model']) m.haiku = args['small-model'];
  for (const s of Object.keys(SLOT_VARS)) if (args[s]) m[s] = args[s];
  if (!m.main) die(`${p ? p.name + ' has no default model' : 'no model given'}: pass --model ID (the exact ID the provider accepts).`);
  for (const s of ['opus', 'sonnet', 'fable', 'subagent']) if (!m[s]) m[s] = m.main;
  if (!m.haiku) m.haiku = m.main;

  const auth = (args.auth || 'bearer').toLowerCase();
  if (!['bearer', 'x-api-key'].includes(auth)) die('--auth must be bearer or x-api-key');

  const env = { ANTHROPIC_BASE_URL: baseUrl };
  for (const [s, v] of Object.entries(SLOT_VARS)) env[v] = m[s];
  env.ANTHROPIC_SMALL_FAST_MODEL = m.haiku; // deprecated name, still read by older Claude Code versions
  Object.assign(env, (p && p.extra) || {});
  return { id, preset: p, env, auth, keyEnv: args['key-env'] || (p && p.keyEnv) || 'CCP_API_KEY' };
}

async function getKey(cfg, args) {
  if (args['no-key']) return { key: null, from: null };
  const names = [cfg.keyEnv, 'CCP_API_KEY'];
  for (const n of names) if (process.env[n]) return { key: process.env[n].trim(), from: n };
  if (process.stdin.isTTY) {
    const key = (await promptHidden(`API key for ${cfg.preset ? cfg.preset.name : cfg.env.ANTHROPIC_BASE_URL} (input hidden): `)).trim();
    if (key) return { key, from: 'prompt' };
  }
  die(`no API key. Export ${cfg.keyEnv} (or CCP_API_KEY), run ccp in a terminal to be prompted, or pass --no-key to set the key yourself.`);
}

function authEnv(cfg, key) {
  // Bearer: key in ANTHROPIC_AUTH_TOKEN and ANTHROPIC_API_KEY blanked, so a stale Anthropic key in your
  // shell can't add an x-api-key header (verified: an empty ANTHROPIC_API_KEY sends no header).
  if (cfg.auth === 'bearer') return key === null ? { ANTHROPIC_API_KEY: '' } : { ANTHROPIC_AUTH_TOKEN: key, ANTHROPIC_API_KEY: '' };
  return key === null ? {} : { ANTHROPIC_API_KEY: key };
}

function backupPath(file) { return file + '.ccp-backup'; }
function makeBackup(file) {
  const b = backupPath(file);
  if (fs.existsSync(b)) return null; // keep the original pre-ccp state
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const existed = fs.existsSync(file);
  if (existed) fs.copyFileSync(file, b);
  else fs.writeFileSync(b, ''); // marker: there was no file before ccp
  fs.chmodSync(b, 0o600);
  return existed ? b : null;
}

function printSummary(cfg, keyInfo, target) {
  const e = cfg.env;
  console.log(`${cfg.preset ? cfg.preset.name : 'Custom provider'} -> ${target}`);
  info(`ANTHROPIC_BASE_URL              ${e.ANTHROPIC_BASE_URL}`);
  const keyVar = cfg.auth === 'bearer' ? 'ANTHROPIC_AUTH_TOKEN (sent as Authorization: Bearer)' : 'ANTHROPIC_API_KEY (sent as x-api-key)';
  info(`key                             ${keyInfo.key === null ? 'not written (--no-key): export it yourself as ' + keyVar : keyVar + ', from ' + (keyInfo.from === 'prompt' ? 'prompt' : '$' + keyInfo.from)}`);
  for (const v of [...Object.values(SLOT_VARS), 'ANTHROPIC_SMALL_FAST_MODEL']) info(`${v.padEnd(31)} ${e[v]}`);
  for (const v of Object.keys((cfg.preset && cfg.preset.extra) || {})) info(`${v.padEnd(31)} ${e[v]}`);
  if (cfg.preset && cfg.preset.note) info(c('2', cfg.preset.note));
  if (cfg.preset && cfg.preset.source) info(c('2', 'source: ' + cfg.preset.source));
}

async function cmdUse(args) {
  const cfg = buildConfig(args);
  const profile = args.profile !== undefined ? (args.profile === '' ? defaultProfilePath() : path.resolve(args.profile)) : null;

  if (cfg.reset) return cmdReset({ ...args, defaults: true }, 'Anthropic (default)');

  const keyInfo = await getKey(cfg, args);
  if (profile) {
    const lines = ['# Written by ccp (claude-code-provider). Load it with:  . ' + tilde(profile), '# Values in ~/.claude/settings.json "env" override these exports.'];
    const auth = authEnv(cfg, keyInfo.key);
    const keyVar = cfg.auth === 'bearer' ? 'ANTHROPIC_AUTH_TOKEN' : 'ANTHROPIC_API_KEY';
    const q = (s) => "'" + String(s).replace(/'/g, "'\\''") + "'";
    for (const [k, v] of Object.entries({ ...cfg.env, ...auth })) {
      if (k === keyVar && keyInfo.from && keyInfo.from !== 'prompt') lines.push(`export ${k}="\${${keyInfo.from}}"   # read from $${keyInfo.from} when sourced`);
      else lines.push(`export ${k}=${q(v)}`);
    }
    if (args['dry-run']) { printSummary(cfg, keyInfo, tilde(profile) + ' (dry run, nothing written)'); return; }
    const b = makeBackup(profile);
    writeFileAtomic(profile, lines.join('\n') + '\n', 0o600);
    printSummary(cfg, keyInfo, tilde(profile));
    if (b) info(`backup of the previous file: ${tilde(b)}`);
    console.log(`\nNext: add this line to your ~/.zshrc or ~/.bashrc, open a new shell, then run \`ccp check\`:\n  [ -f ${tilde(profile)} ] && . ${tilde(profile)}`);
    const s = readJson(userSettingsPath());
    const clash = s && s.env ? MANAGED.filter((k) => k in s.env) : [];
    if (clash.length) warn(`${tilde(userSettingsPath())} sets ${clash.join(', ')} in "env", which overrides the profile. Run \`ccp reset --defaults\` for settings.json or remove them.`);
    return;
  }

  const file = args.settings ? path.resolve(args.settings) : userSettingsPath();
  const settings = readJson(file) || {};
  if (typeof settings !== 'object' || Array.isArray(settings)) die(`${tilde(file)} is not a JSON object; nothing was changed.`);
  const env = { ...(settings.env || {}) };
  for (const k of MANAGED) delete env[k];
  Object.assign(env, cfg.env, authEnv(cfg, keyInfo.key));
  if (args['dry-run']) { printSummary(cfg, keyInfo, tilde(file) + ' (dry run, nothing written)'); return; }
  const b = makeBackup(file);
  const out = { ...settings, env };
  writeFileAtomic(file, JSON.stringify(out, null, 2) + '\n', keyInfo.key ? 0o600 : undefined);
  printSummary(cfg, keyInfo, tilde(file) + ' "env"');
  if (b) info(`backup: ${tilde(b)} (\`ccp reset\` restores these values)`);
  if (settings.apiKeyHelper) warn('settings also has "apiKeyHelper"; it sends its own key in both auth headers. Remove it if the provider rejects requests.');
  for (const v of ['ANTHROPIC_BASE_URL', 'ANTHROPIC_AUTH_TOKEN', 'ANTHROPIC_API_KEY', 'ANTHROPIC_MODEL']) {
    if (process.env[v] && process.env[v] !== env[v]) { info(c('2', `Your shell exports ${v}; the settings file wins over it, but other tools still see the export.`)); break; }
  }
  console.log('\nNext: `ccp check` sends one tiny request to confirm the key and model. Restart any open Claude Code session.');
}

// ---------------------------------------------------------------------------
// ccp reset
// ---------------------------------------------------------------------------
function cmdReset(args, label) {
  if (args.profile !== undefined) {
    const profile = args.profile === '' ? defaultProfilePath() : path.resolve(args.profile);
    const b = backupPath(profile);
    if (!args.defaults && fs.existsSync(b) && fs.readFileSync(b, 'utf8') !== '') { fs.copyFileSync(b, profile); fs.unlinkSync(b); console.log(`Restored ${tilde(profile)} from backup.`); }
    else { if (fs.existsSync(profile)) fs.unlinkSync(profile); if (fs.existsSync(b)) fs.unlinkSync(b); console.log(`Removed ${tilde(profile)}.`); }
    console.log(`Open a new shell (or run: unset ${MANAGED.join(' ')}).`);
    return;
  }
  const file = args.settings ? path.resolve(args.settings) : userSettingsPath();
  const settings = readJson(file);
  const b = backupPath(file);
  if (!settings) { console.log(`${tilde(file)} does not exist; nothing to reset.`); return; }
  const env = { ...(settings.env || {}) };
  for (const k of MANAGED) delete env[k];
  let how = 'removed every provider override ccp manages';
  if (!args.defaults && fs.existsSync(b)) {
    const orig = fs.readFileSync(b, 'utf8').trim() ? readJson(b) : {};
    for (const k of MANAGED) if (orig && orig.env && k in orig.env) env[k] = orig.env[k];
    how = 'restored the provider values from before ccp\'s first change';
  }
  const out = { ...settings };
  if (Object.keys(env).length) out.env = env; else delete out.env;
  writeFileAtomic(file, JSON.stringify(out, null, 2) + '\n', fs.statSync(file).mode & 0o777);
  if (fs.existsSync(b)) fs.unlinkSync(b);
  console.log(`${label ? label + ': ' : ''}${how} in ${tilde(file)}. Other settings were left as they were.`);
  const leftover = ['ANTHROPIC_BASE_URL', 'ANTHROPIC_AUTH_TOKEN', 'ANTHROPIC_API_KEY', 'ANTHROPIC_MODEL'].filter((v) => process.env[v]);
  if (leftover.length) warn(`your shell still exports ${leftover.join(', ')}; Claude Code will use those. Unset them to get Anthropic defaults.`);
}

// ---------------------------------------------------------------------------
// ccp check
// ---------------------------------------------------------------------------
function effectiveEnv(args) {
  // Claude Code precedence (low -> high): shell env, user settings, project settings, local project settings.
  const env = {}, from = {};
  for (const k of MANAGED) if (process.env[k] !== undefined) { env[k] = process.env[k]; from[k] = 'shell'; }
  const files = args.settings ? [path.resolve(args.settings)] : [userSettingsPath(), path.resolve('.claude/settings.json'), path.resolve('.claude/settings.local.json')];
  let helper = null;
  for (const f of files) {
    const s = readJson(f);
    if (!s) continue;
    if (s.apiKeyHelper) helper = tilde(f);
    for (const k of MANAGED) if (s.env && k in s.env) { env[k] = String(s.env[k]); from[k] = tilde(f); }
  }
  return { env, from, helper };
}

function curlMessages(baseUrl, headers, model) {
  const body = JSON.stringify({ model, max_tokens: 16, messages: [{ role: 'user', content: 'Reply with OK.' }] });
  const url = `${baseUrl}/v1/messages`;
  // Headers (including the key) go to curl on stdin, so the key is not visible in the process list.
  const hdr = Object.entries(headers).map(([k, v]) => `${k}: ${v}`).join('\n') + '\n';
  const r = spawnSync('curl', ['-sS', '-m', '60', '-o', '-', '-w', '\n%{http_code}', '-X', 'POST', '-H', '@-', '--data-binary', body, url], { input: hdr, encoding: 'utf8' });
  if (r.error) die('`ccp check` needs curl on your PATH.');
  const out = r.stdout || '';
  const i = out.lastIndexOf('\n');
  return { url, curlExit: r.status, stderr: (r.stderr || '').trim(), code: Number(out.slice(i + 1)) || 0, body: out.slice(0, i) };
}

const MODEL_RX = /model[_ ]?not[_ ]?found|not_found_error[^}]*model|model[^.]{0,80}(not found|does not exist|doesn'?t exist|not exist|is not (a )?valid|invalid|unknown|not supported|unsupported|not available|no access|not allowed)|(unknown|invalid|unsupported|no such) model|no endpoints found/i;

function errMessage(body) {
  try { const j = JSON.parse(body); const e = j.error || j; return String(e.message || e.msg || e.detail || JSON.stringify(e)).slice(0, 300); } catch { return body.replace(/\s+/g, ' ').slice(0, 300); }
}

function classify(res, baseUrl) {
  if (res.curlExit !== 0 && !res.code) return ['UNREACHABLE', `could not connect to ${res.url} (${res.stderr || 'curl exit ' + res.curlExit}).`];
  const msg = errMessage(res.body);
  if (res.code >= 200 && res.code < 300) return ['OK', null];
  if ((res.code === 404 || res.code === 405) && hasExtraV1(baseUrl)) return ['EXTRA_V1', `HTTP ${res.code} from ${res.url}.`];
  if (MODEL_RX.test(res.body)) return ['MODEL_NOT_FOUND', `HTTP ${res.code}: ${msg}`];
  if (res.code === 401 || res.code === 403) return ['AUTH', `HTTP ${res.code}: ${msg}`];
  if (res.code === 404) return ['WRONG_URL', `HTTP 404 from ${res.url}: ${msg}`];
  if (res.code === 429) return ['RATE_LIMITED', `HTTP 429: ${msg}`];
  if (res.code >= 500) return ['PROVIDER_ERROR', `HTTP ${res.code}: ${msg}`];
  return ['BAD_REQUEST', `HTTP ${res.code}: ${msg}`];
}

function cmdCheck(args) {
  const { env, from, helper } = effectiveEnv(args);
  let baseUrl = (args['base-url'] || env.ANTHROPIC_BASE_URL || 'https://api.anthropic.com').replace(/\/+$/, '');
  console.log(`Claude Code will call: ${baseUrl}/v1/messages` + (env.ANTHROPIC_BASE_URL ? `   (ANTHROPIC_BASE_URL from ${from.ANTHROPIC_BASE_URL})` : '   (ANTHROPIC_BASE_URL not set)'));
  let problems = 0;

  // Auth, as Claude Code sends it.
  const headers = { 'content-type': 'application/json', 'anthropic-version': '2023-06-01' };
  const token = env.ANTHROPIC_AUTH_TOKEN;
  const apiKey = env.ANTHROPIC_API_KEY;
  const sent = [];
  if (token) { headers.authorization = 'Bearer ' + token; sent.push(`Authorization: Bearer (ANTHROPIC_AUTH_TOKEN from ${from.ANTHROPIC_AUTH_TOKEN})`); }
  if (apiKey) { headers['x-api-key'] = apiKey; sent.push(`x-api-key (ANTHROPIC_API_KEY from ${from.ANTHROPIC_API_KEY})`); }
  if (!sent.length) {
    bad(`no key: neither ANTHROPIC_AUTH_TOKEN nor ANTHROPIC_API_KEY is set${helper ? ` (apiKeyHelper in ${helper} is not run by ccp)` : ''}.`);
    info('A non-Anthropic provider needs one of them. Run `ccp use ...` again, or export ANTHROPIC_AUTH_TOKEN.');
    return process.exit(1);
  }
  info('auth: ' + sent.join(' + '));
  if (sent.length > 1) warn('both auth variables are set, so Claude Code sends both headers. Most gateways want one; blank the other (ANTHROPIC_API_KEY="").');

  // Model slots.
  const slots = {};
  for (const [s, v] of Object.entries(SLOT_VARS)) slots[s] = env[v] || null;
  if (!slots.haiku && env.ANTHROPIC_SMALL_FAST_MODEL) slots.haiku = env.ANTHROPIC_SMALL_FAST_MODEL;
  const custom = baseUrl !== 'https://api.anthropic.com';
  for (const [s, v] of Object.entries(SLOT_VARS)) {
    const val = slots[s];
    if (val) info(`${v.padEnd(31)} ${val}`);
    else if (custom && s !== 'subagent') { warn(`${v} is not set: Claude Code requests ${BUILTIN[s]} for that slot.`); problems++; }
  }
  if (custom && !slots.sonnet) info(c('2', 'Auto mode\'s permission classifier also uses the Sonnet slot (claude-sonnet-5 when unset, Claude Code 2.1.296).'));

  if (hasExtraV1(baseUrl)) {
    bad(`base URL ends in /v1, so Claude Code calls ${baseUrl}/v1/messages (/v1/v1/...). Set ANTHROPIC_BASE_URL=${baseUrl.replace(/\/v1\/?$/, '')}`);
    problems++;
  }

  // Requests.
  let models = [];
  if (args.model) models = [args.model];
  else if (args.all) models = [...new Set(Object.entries(slots).map(([s, v]) => v || (custom && s !== 'subagent' ? BUILTIN[s] : null)).filter(Boolean))];
  else models = [slots.main || BUILTIN.main];

  for (const m of models) {
    const sentModel = stripOneM(m);
    const res = curlMessages(baseUrl, headers, sentModel);
    const [kind, detail] = classify(res, baseUrl);
    const label = `model ${sentModel}${sentModel !== m ? ' (Claude Code drops the [1m] suffix)' : ''}`;
    switch (kind) {
      case 'OK': {
        let echoed = ''; try { echoed = JSON.parse(res.body).model; } catch {}
        ok(`${label}: request accepted (HTTP ${res.code}${echoed && echoed !== sentModel ? ', answered by ' + echoed : ''}).`);
        break;
      }
      case 'EXTRA_V1': {
        bad(`${label}: extra /v1 in the base URL. ${detail}`);
        const fixed = baseUrl.replace(/\/v1\/?$/, '');
        const r2 = curlMessages(fixed, headers, sentModel);
        const [k2] = classify(r2, fixed);
        info(k2 === 'OK' ? `Without /v1 the same request works: set ANTHROPIC_BASE_URL=${fixed}`
          : r2.code && r2.code !== 404 ? `Without /v1 the endpoint answers (HTTP ${r2.code}, ${k2.toLowerCase().replace('_', ' ')}): set ANTHROPIC_BASE_URL=${fixed} and run ccp check again.`
          : `Without /v1 it is not found either (HTTP ${r2.code}): check the provider's Anthropic base URL.`);
        problems++;
        break;
      }
      case 'MODEL_NOT_FOUND':
        bad(`${label}: model_not_found. ${detail}`);
        info('Use the exact ID from the provider\'s docs or GET /v1/models, then `ccp use <preset> --model ID`.');
        problems++;
        break;
      case 'AUTH':
        bad(`${label}: auth rejected. ${detail}`);
        info(sent.length === 1 && token ? 'The key went as Authorization: Bearer. If the key is right, the provider may want x-api-key: `ccp use ... --auth x-api-key`.'
          : sent.length === 1 ? 'The key went as x-api-key. If the key is right, the provider may want Bearer: `ccp use ...` (default --auth bearer).'
          : 'Check the key is for this provider (and region).');
        problems++;
        break;
      case 'WRONG_URL':
        bad(`${label}: no /v1/messages at this base URL. ${detail}`);
        info('Use the provider\'s Anthropic-compatible base URL (often ends in /anthropic), without /v1.');
        problems++;
        break;
      case 'RATE_LIMITED':
        warn(`${label}: key accepted but rate-limited or out of quota. ${detail}`);
        break;
      case 'UNREACHABLE':
        bad(`${label}: ${detail}`);
        problems++;
        break;
      default:
        bad(`${label}: ${kind.toLowerCase().replace('_', ' ')}. ${detail}`);
        problems++;
    }
  }
  if (!args.all && !args.model && Object.values(slots).filter(Boolean).some((v) => stripOneM(v) !== stripOneM(models[0]))) info(c('2', 'Other slots use other models; `ccp check --all` tests each one (one tiny request per model).'));
  process.exit(problems ? 1 : 0);
}

// ---------------------------------------------------------------------------
// ccp show / presets / help
// ---------------------------------------------------------------------------
function cmdShow(args) {
  const { env, from, helper } = effectiveEnv(args);
  if (!Object.keys(env).length) { console.log('No provider overrides found: Claude Code uses Anthropic defaults.'); return; }
  for (const k of MANAGED) {
    if (!(k in env)) continue;
    const secret = k === 'ANTHROPIC_AUTH_TOKEN' || k === 'ANTHROPIC_API_KEY';
    const v = secret ? (env[k] ? `set (${env[k].length} chars)` : '"" (blank)') : env[k];
    console.log(`${k.padEnd(31)} ${v}   ${c('2', '<- ' + from[k])}`);
  }
  if (helper) console.log(`apiKeyHelper is set in ${helper}`);
}

function cmdPresets() {
  for (const [id, p] of Object.entries(PRESETS)) {
    console.log(`${c('1', id.padEnd(16))}${p.name}${p.aliases ? c('2', '  (also: ' + p.aliases.join(', ') + ')') : ''}`);
    if (p.baseUrl) info(`${p.baseUrl}   key: $${p.keyEnv}   model: ${p.models ? p.models.main : '--model required'}`);
    info(c('2', p.source));
  }
}

const HELP = `ccp ${VERSION} - point Claude Code at another Anthropic-compatible provider, with every model slot set.

Usage:
  ccp use <preset> [options]            write the provider's env block to ~/.claude/settings.json (backup first)
  ccp use --base-url URL --model ID     any Anthropic-compatible provider
  ccp check [--all] [--model ID]        send one tiny /v1/messages request and say what is wrong
  ccp reset [--defaults]                restore the values from before ccp's first change (or remove them all)
  ccp show                              print the effective provider settings (keys masked)
  ccp presets                           list presets with their documentation links

Options for use:
  --model ID          every model slot (main, opus, sonnet, haiku, fable, subagent)
  --small-model ID    only the Haiku slot (background tasks) and ANTHROPIC_SMALL_FAST_MODEL
  --opus/--sonnet/--haiku/--fable/--subagent/--main ID   one slot
  --auth bearer|x-api-key   header for the key (default bearer = ANTHROPIC_AUTH_TOKEN)
  --key-env NAME      read the key from $NAME (default: the preset's variable, then $CCP_API_KEY, then a hidden prompt)
  --no-key            don't write a key; you export ANTHROPIC_AUTH_TOKEN yourself
  --workspace ID      fill {WorkspaceId} in the Alibaba pay-as-you-go URL
  --profile [PATH]    write a shell file to source instead of settings.json (default ~/.config/claude-code-provider/env.sh)
  --settings PATH     use another settings file, e.g. .claude/settings.local.json
  --dry-run           show what would be written

Presets: ${Object.keys(PRESETS).join(', ')}
Docs: https://github.com/henrikdukefoss/claude-code-provider`;

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const cmd = args._[0];
  if (args.version || cmd === 'version') return console.log(VERSION);
  if (args.help || !cmd || cmd === 'help') return console.log(HELP);
  if (cmd === 'use') return cmdUse(args);
  if (cmd === 'check') return cmdCheck(args);
  if (cmd === 'reset') return cmdReset(args);
  if (cmd === 'show') return cmdShow(args);
  if (cmd === 'presets' || cmd === 'list') return cmdPresets();
  die(`unknown command "${cmd}". Run \`ccp help\`.`);
}

main().catch((e) => die(e.stack || String(e)));
