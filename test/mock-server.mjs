// Mock Anthropic /v1/messages server for test/e2e.sh. Logs the model and which auth header arrived; never logs keys.
// env: PORT, MOCK_KEY (accepted key), MOCK_MODELS (comma list; empty = accept all), LOG (jsonl path),
//      MOCK_SUBAGENT=1: answer the first request that offers the Agent tool with a tool_use that starts a subagent
//      MOCK_TOOL=Name:{json}: answer the first request that offers tool Name with that tool_use (e.g. WebFetch)
import http from 'node:http';
import fs from 'node:fs';

const PORT = +(process.env.PORT || 8788);
const KEY = process.env.MOCK_KEY || 'test-key-123';
const MODELS = (process.env.MOCK_MODELS || '').split(',').filter(Boolean);
const LOG = process.env.LOG || 'requests.jsonl';
let spawned = false;

function send(res, code, obj) {
  res.writeHead(code, { 'content-type': 'application/json' });
  res.end(JSON.stringify(obj));
}

http.createServer((req, res) => {
  let body = '';
  req.on('data', (c) => (body += c));
  req.on('end', () => {
    let j = {};
    try { j = JSON.parse(body || '{}'); } catch {}
    const auth = req.headers['authorization'];
    const xkey = req.headers['x-api-key'];
    const tools = (j.tools || []).map((t) => t.name);
    const entry = {
      method: req.method, path: req.url, model: j.model,
      bearer: auth ? (auth === `Bearer ${KEY}` ? 'ok' : 'wrong') : null,
      xapikey: xkey !== undefined ? (xkey === KEY ? 'ok' : xkey === '' ? 'empty' : 'wrong') : null,
      thinking: j.thinking, stream: !!j.stream,
    };
    fs.appendFileSync(LOG, JSON.stringify(entry) + '\n');

    if (req.method === 'GET' && req.url.startsWith('/v1/models')) return send(res, 200, { data: MODELS.map((id) => ({ id, type: 'model' })) });
    if (!(req.method === 'POST' && /^\/v1\/messages(\?|$)/.test(req.url))) {
      if (req.method === 'HEAD' || req.method === 'GET') return send(res, 200, {});
      return send(res, 404, { type: 'error', error: { type: 'not_found_error', message: `Not found: ${req.method} ${req.url}` } });
    }
    if (entry.bearer !== 'ok' && entry.xapikey !== 'ok') return send(res, 401, { type: 'error', error: { type: 'authentication_error', message: 'invalid x-api-key' } });
    if (MODELS.length && !MODELS.includes(j.model)) return send(res, 404, { type: 'error', error: { type: 'not_found_error', message: `model: ${j.model}` } });

    const id = 'msg_' + Math.random().toString(36).slice(2);
    let content = [{ type: 'text', text: 'OK' }];
    let stop = 'end_turn';
    const agentTool = tools.find((t) => t === 'Agent' || t === 'Task');
    if (process.env.MOCK_SUBAGENT && agentTool && !spawned && !(j.system && JSON.stringify(j.system).includes('subagent'))) {
      spawned = true;
      content = [{ type: 'tool_use', id: 'toolu_' + id, name: agentTool, input: { description: 'say hi', prompt: 'Reply with the word hi.', subagent_type: 'general-purpose' } }];
      stop = 'tool_use';
    }
    if (process.env.MOCK_TOOL && !spawned && tools.includes(process.env.MOCK_TOOL.split(':')[0])) {
      spawned = true;
      const [name, ...rest] = process.env.MOCK_TOOL.split(':');
      content = [{ type: 'tool_use', id: 'toolu_' + id, name, input: JSON.parse(rest.join(':')) }];
      stop = 'tool_use';
    }
    const usage = { input_tokens: 5, output_tokens: 1, cache_creation_input_tokens: 0, cache_read_input_tokens: 0 };
    if (!j.stream) return send(res, 200, { id, type: 'message', role: 'assistant', model: j.model, content, stop_reason: stop, stop_sequence: null, usage });

    res.writeHead(200, { 'content-type': 'text/event-stream', 'cache-control': 'no-cache' });
    const ev = (name, data) => res.write(`event: ${name}\ndata: ${JSON.stringify(data)}\n\n`);
    ev('message_start', { type: 'message_start', message: { id, type: 'message', role: 'assistant', model: j.model, content: [], stop_reason: null, stop_sequence: null, usage } });
    content.forEach((c, i) => {
      if (c.type === 'text') {
        ev('content_block_start', { type: 'content_block_start', index: i, content_block: { type: 'text', text: '' } });
        ev('content_block_delta', { type: 'content_block_delta', index: i, delta: { type: 'text_delta', text: c.text } });
      } else {
        ev('content_block_start', { type: 'content_block_start', index: i, content_block: { type: 'tool_use', id: c.id, name: c.name, input: {} } });
        ev('content_block_delta', { type: 'content_block_delta', index: i, delta: { type: 'input_json_delta', partial_json: JSON.stringify(c.input) } });
      }
      ev('content_block_stop', { type: 'content_block_stop', index: i });
    });
    ev('message_delta', { type: 'message_delta', delta: { stop_reason: stop, stop_sequence: null }, usage: { output_tokens: 1 } });
    ev('message_stop', { type: 'message_stop' });
    res.end();
  });
}).listen(PORT, '127.0.0.1', () => console.log('mock on', PORT));
