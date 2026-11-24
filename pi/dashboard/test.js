// node test.js — runs the server against an in-memory database on a random port.
'use strict'
process.env.DB_PATH = ':memory:'
process.env.DASHBOARD_TOKEN = 'test-token'
process.env.WATCH_SERVICES = '--now ;x $(id)' // option/shell-like names must be dropped
const test = require('node:test')
const assert = require('node:assert/strict')
const { server } = require('./server.js')

let base
test.before(() => new Promise((r) => server.listen(0, '127.0.0.1', () => { base = `http://127.0.0.1:${server.address().port}`; r() })))
test.after(() => server.close())

const call = (path, opts = {}) => fetch(base + path, { ...opts, headers: { 'Content-Type': 'application/json', ...opts.headers } })

test('health and static files', async () => {
  assert.equal((await call('/api/health')).status, 200)
  const page = await call('/')
  assert.equal(page.status, 200)
  assert.match(page.headers.get('content-security-policy'), /default-src 'self'/)
  assert.equal((await call('/%2e%2e/server.js')).status, 404)
  assert.equal((await call('/../test.js')).status, 404)
})

test('to-do lifecycle and validation', async () => {
  assert.equal((await call('/api/todos', { method: 'POST', body: JSON.stringify({ text: '' }) })).status, 400)
  assert.equal((await call('/api/todos', { method: 'POST', body: JSON.stringify({ text: 'x', due: 'tomorrow' }) })).status, 400)
  assert.equal((await call('/api/todos', { method: 'POST', body: '{bad' })).status, 400)
  const created = await (await call('/api/todos', { method: 'POST', body: JSON.stringify({ text: 'Update the Pi', due: '2030-01-01' }) })).json()
  assert.equal(created.text, 'Update the Pi')
  const done = await (await call(`/api/todos/${created.id}`, { method: 'PATCH', body: JSON.stringify({ done: true }) })).json()
  assert.equal(done.done, 1)
  assert.equal(done.due, '2030-01-01')
  assert.equal((await call(`/api/todos/${created.id}`, { method: 'DELETE' })).status, 204)
  assert.deepEqual(await (await call('/api/todos')).json(), [])
})

test('cross-origin browser writes are blocked', async () => {
  const r = await call('/api/todos', { method: 'POST', headers: { Origin: 'https://evil.example' }, body: JSON.stringify({ text: 'x' }) })
  assert.equal(r.status, 403)
  const ok = await call('/api/todos', { method: 'POST', headers: { Origin: base }, body: JSON.stringify({ text: 'same origin' }) })
  assert.equal(ok.status, 201)
})

test('PC heartbeat needs the token', async () => {
  const body = JSON.stringify({ host: 'desk-pc', diskFreePct: 42, uptimeH: 5 })
  assert.equal((await call('/api/pc', { method: 'POST', body })).status, 401)
  assert.equal((await call('/api/pc', { method: 'POST', headers: { Authorization: 'Bearer nope' }, body })).status, 401)
  assert.equal((await call('/api/pc', { method: 'POST', headers: { Authorization: 'Bearer test-token' }, body: JSON.stringify({ host: '<x>' }) })).status, 400)
  assert.equal((await call('/api/pc', { method: 'POST', headers: { Authorization: 'Bearer test-token' }, body })).status, 204)
  const s = await (await call('/api/status')).json()
  assert.equal(s.pcs[0].host, 'desk-pc')
  assert.equal(s.pcs[0].diskFreePct, 42)
  assert.deepEqual(s.services, [])
})

test('oversized bodies are rejected', async () => {
  const r = await call('/api/todos', { method: 'POST', body: JSON.stringify({ text: 'a'.repeat(70000) }) }).catch(() => ({ status: 413 }))
  assert.equal(r.status, 413)
})
