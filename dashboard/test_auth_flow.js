import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import vm from 'node:vm';

const AUTH_FLOW_SOURCE = readFileSync(new URL('./auth-flow.js', import.meta.url), 'utf8');

function loadAuthFlow({
  hostname = '127.0.0.1',
  origin = 'http://127.0.0.1:18083',
  metaApiBase = '',
  runtimeApiBase,
} = {}) {
  const requests = [];
  const window = {
    location: { hostname, origin },
    ...(runtimeApiBase === undefined
      ? {}
      : { __HYFENS_RUNTIME_CONFIG__: { apiBase: runtimeApiBase } }),
  };
  const document = {
    querySelector(selector) {
      assert.equal(selector, 'meta[name="hyfens-api-base"]');
      return { content: metaApiBase };
    },
  };
  const fetch = async (url) => {
    requests.push(String(url));
    return {
      ok: true,
      async json() {
        return {};
      },
    };
  };

  vm.runInNewContext(AUTH_FLOW_SOURCE, { URL, document, fetch, window });
  return { api: window.HyfensAuthFlow, requests };
}

test('auth requests use the injected control-plane API base on Docker-served pages', async () => {
  const { api, requests } = loadAuthFlow({ runtimeApiBase: 'http://127.0.0.1:18082/' });

  await api.request('auth/login', { method: 'POST', body: '{}' });

  assert.deepEqual(requests, ['http://127.0.0.1:18082/auth/login']);
});

test('an explicit API meta tag takes precedence over runtime configuration', () => {
  const { api } = loadAuthFlow({
    metaApiBase: 'http://127.0.0.1:18084',
    runtimeApiBase: 'http://127.0.0.1:18082/',
  });

  assert.equal(api.apiBase(), 'http://127.0.0.1:18084/');
});

test('the managed dashboard keeps its public control-plane fallback', () => {
  const { api } = loadAuthFlow({
    hostname: 'app.hyfens.com',
    origin: 'https://app.hyfens.com',
  });

  assert.equal(api.apiBase(), 'https://api.hyfens.com/');
  assert.equal(api.displayApiBase(), 'Hyfens Cloud (managed)');
});

test('an unconfigured self-hosted instance uses its own origin', () => {
  const { api } = loadAuthFlow({
    hostname: 'instance.example.com',
    origin: 'https://instance.example.com',
  });

  assert.equal(api.apiBase(), 'https://instance.example.com/');
  assert.equal(api.displayApiBase(), 'https://instance.example.com/');
});
